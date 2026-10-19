import Foundation

/// Builds real .xlsx workbooks for Profil › Ekspor data (design "Sheet Pengaturan").
/// Pure and read only: the file is assembled on the device, nothing is sent anywhere.
///
/// An xlsx is a zip of a few XML parts. The zip is written with the store method (no
/// compression), which is the simplest valid form and opens in Excel, Numbers and Sheets.
enum XlsxExport {
    /// One worksheet: sheet name plus a header row and rows of plain text values.
    struct Sheet {
        let name: String
        let header: [String]
        let rows: [[String]]
    }

    // MARK: Files

    /// Same columns as the CSV file, so the workbook matches the app's words (Fitur 8).
    static func transactions(_ transactions: [Transaction], accounts: [Account], categories: [Category],
                             intervals: [DateInterval]? = nil) -> Sheet {
        let wallets = Dictionary(accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let names = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let rows = transactions
            .filter { txn in
                guard let intervals else { return true }
                return intervals.contains { txn.date >= $0.start && txn.date < $0.end }
            }
            .newestFirst()
            .map { txn in
                [CsvExport.date(txn.date), CsvExport.typeLabel(txn.type),
                 txn.categoryId.flatMap { names[$0] } ?? "",
                 wallets[txn.accountId] ?? "",
                 txn.counterpartyAccountId.flatMap { wallets[$0] } ?? "",
                 CsvExport.amount(txn.amount), txn.displayNote ?? ""]
            }
        return Sheet(name: L("Transaksi"),
                     header: [L("Tanggal"), L("Jenis"), L("Kategori"), L("Dompet"), L("Dompet tujuan"), L("Nominal"), L("Catatan")],
                     rows: rows)
    }

    static func wallets(_ accounts: [Account]) -> Sheet {
        let rows = accounts.map { [CsvExport.text($0.name), CsvExport.walletTypeLabel($0.type),
                                   CsvExport.amount($0.balance), CsvExport.amount($0.openingBalance)] }
        return Sheet(name: L("Dompet"),
                     header: [L("Nama"), L("Jenis"), L("Saldo Saat Ini"), L("Saldo Awal")],
                     rows: rows)
    }

    static func budgets(_ budgets: [Budget], categories: [Category]) -> Sheet {
        let names = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let rows = budgets.map { budget in
            [names[budget.categoryId] ?? budget.name, CsvExport.amount(budget.amount),
             CsvExport.period(budget), CsvExport.amount(budget.spent)]
        }
        return Sheet(name: L("Budget"),
                     header: [L("Kategori"), L("Nominal"), L("Periode"), L("Terpakai")],
                     rows: rows)
    }

    // MARK: Workbook

    /// The workbook bytes for `sheets`, or nil when there is nothing to write.
    static func data(_ sheets: [Sheet]) -> Data? {
        guard !sheets.isEmpty else { return nil }
        var parts: [(String, Data)] = []
        let names = sheets.enumerated().map { sanitized($0.element.name, index: $0.offset) }

        parts.append(("[Content_Types].xml", xml(contentTypes(count: sheets.count))))
        parts.append(("_rels/.rels", xml(rels(officeDocumentRels))))
        parts.append(("xl/workbook.xml", xml(workbook(names))))
        parts.append(("xl/_rels/workbook.xml.rels", xml(rels(workbookRels(count: sheets.count)))))
        for (index, sheet) in sheets.enumerated() {
            parts.append(("xl/worksheets/sheet\(index + 1).xml", xml(worksheet(sheet, columnWidths: widths(for: sheet)))))
        }
        return zip(parts)
    }

    /// Writes the workbook to the temporary folder for the share sheet.
    static func write(_ sheets: [Sheet], name: String) -> URL? {
        guard let data = data(sheets) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    // MARK: Worksheet XML

    private static func worksheet(_ sheet: Sheet, columnWidths: [Double]) -> String {
        var rows: [String] = []
        rows.append(row(1, cells: sheet.header, isHeader: true))
        for (offset, values) in sheet.rows.enumerated() {
            rows.append(row(offset + 2, cells: values, isHeader: false))
        }
        let cols = columnWidths.enumerated()
            .map { "<col min=\"\($0.offset + 1)\" max=\"\($0.offset + 1)\" width=\"\(String(format: "%.1f", $0.element))\" customWidth=\"1\"/>" }
            .joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><cols>\(cols)</cols><sheetData>\(rows.joined())</sheetData></worksheet>
        """
    }

    private static func row(_ index: Int, cells: [String], isHeader: Bool) -> String {
        let values = cells.enumerated().map { cell(column: $0.offset, row: index, value: $0.element, numeric: !isHeader) }.joined()
        return "<row r=\"\(index)\">\(values)</row>"
    }

    /// Numbers go in as real numbers so the sheet can sum them (US1); everything else is text.
    private static func cell(column: Int, row: Int, value: String, numeric: Bool) -> String {
        let ref = "\(Self.column(column))\(row)"
        if numeric, let number = Double(value.trimmingCharacters(in: .whitespaces)), !value.isEmpty,
           value.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789")) != nil {
            return "<c r=\"\(ref)\"><v>\(value)</v></c>"
        }
        guard !value.isEmpty else { return "<c r=\"\(ref)\"/>" }
        return "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escaped(value))</t></is></c>"
    }

    /// A, B, … Z, AA, AB … for any column we can produce.
    private static func column(_ index: Int) -> String {
        var value = index
        var letters = ""
        repeat {
            letters = String(UnicodeScalar(UInt8(65 + value % 26))) + letters
            value = value / 26 - 1
        } while value >= 0
        return letters
    }

    /// Readable widths: a fixed default with a little room for long names.
    private static func widths(for sheet: Sheet) -> [Double] {
        (0..<sheet.header.count).map { column in
            let longest = sheet.rows.compactMap { $0.indices.contains(column) ? $0[column].count : nil }.max() ?? 0
            return Double(min(max(sheet.header[column].count, longest) + 2, 40))
        }
    }

    // MARK: Workbook XML

    private static func workbook(_ names: [String]) -> String {
        let sheets = names.enumerated()
            .map { "<sheet name=\"\(escaped($0.element))\" sheetId=\"\($0.offset + 1)\" r:id=\"rId\($0.offset + 1)\"/>" }
            .joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>\(sheets)</sheets></workbook>
        """
    }

    private static func workbookRels(count: Int) -> String {
        (1...count).map {
            "<Relationship Id=\"rId\($0)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\($0).xml\"/>"
        }.joined()
    }

    private static let officeDocumentRels = """
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
    """

    private static func contentTypes(count: Int) -> String {
        let overrides = (1...count).map {
            "<Override PartName=\"/xl/worksheets/sheet\($0).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }.joined()
        return """
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\(overrides)
        """
    }

    private static func rels(_ body: String) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(body)</Relationships>"
    }

    private static func xml(_ body: String) -> Data {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let document = trimmed.hasPrefix("<?xml") ? trimmed : "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n" + trimmed
        return Data(document.utf8)
    }

    /// Sheet names Excel accepts: 31 chars, no []:*?/\ and never empty.
    private static func sanitized(_ name: String, index: Int) -> String {
        var clean = name
        for bad in "[]:*?/\\" {
            clean = clean.replacingOccurrences(of: String(bad), with: " ")
        }
        clean = String(clean.prefix(31)).trimmingCharacters(in: .whitespaces)
        return clean.isEmpty ? L("Sheet %d", index + 1) : clean
    }

    private static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: Zip (store, no compression)

    private static func zip(_ parts: [(String, Data)]) -> Data {
        var data = Data()
        var directory = Data()
        for (name, payload) in parts {
            let nameBytes = Data(name.utf8)
            let crc = crc32(payload)
            let offset = UInt32(data.count)
            data.append(contentsOf: [0x50, 0x4B, 0x03, 0x04])          // local file header
            data.append(littleEndian(UInt16(20)))                      // version needed
            data.append(littleEndian(UInt16(0x0800)))                  // UTF-8 names
            data.append(littleEndian(UInt16(0)))                       // store
            data.append(littleEndian(UInt16(0)))                       // time
            data.append(littleEndian(UInt16(0x2821)))                  // date (2000-01-01)
            data.append(littleEndian(crc))
            data.append(littleEndian(UInt32(payload.count)))
            data.append(littleEndian(UInt32(payload.count)))
            data.append(littleEndian(UInt16(nameBytes.count)))
            data.append(littleEndian(UInt16(0)))
            data.append(nameBytes)
            data.append(payload)

            directory.append(contentsOf: [0x50, 0x4B, 0x01, 0x02])     // central directory entry
            directory.append(littleEndian(UInt16(20)))                 // version made by
            directory.append(littleEndian(UInt16(20)))                 // version needed
            directory.append(littleEndian(UInt16(0x0800)))
            directory.append(littleEndian(UInt16(0)))
            directory.append(littleEndian(UInt16(0)))
            directory.append(littleEndian(UInt16(0x2821)))
            directory.append(littleEndian(crc))
            directory.append(littleEndian(UInt32(payload.count)))
            directory.append(littleEndian(UInt32(payload.count)))
            directory.append(littleEndian(UInt16(nameBytes.count)))
            directory.append(littleEndian(UInt16(0)))                  // extra
            directory.append(littleEndian(UInt16(0)))                  // comment
            directory.append(littleEndian(UInt16(0)))                  // disk
            directory.append(littleEndian(UInt16(0)))                  // internal attrs
            directory.append(littleEndian(UInt32(0)))                  // external attrs
            directory.append(littleEndian(offset))
            directory.append(nameBytes)
        }
        let directoryOffset = UInt32(data.count)
        data.append(directory)
        data.append(contentsOf: [0x50, 0x4B, 0x05, 0x06])              // end of central directory
        data.append(littleEndian(UInt16(0)))
        data.append(littleEndian(UInt16(0)))
        data.append(littleEndian(UInt16(parts.count)))
        data.append(littleEndian(UInt16(parts.count)))
        data.append(littleEndian(UInt32(directory.count)))
        data.append(littleEndian(directoryOffset))
        data.append(littleEndian(UInt16(0)))
        return data
    }

    private static func littleEndian(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    private static func littleEndian(_ value: UInt32) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8(value >> 24)])
    }

    /// Standard CRC-32 (IEEE 802.3), required by the zip format.
    private static func crc32(_ data: Data) -> UInt32 {
        let table = (0..<256).map { index -> UInt32 in
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) == 1 ? (0xEDB88320 ^ (value >> 1)) : (value >> 1)
            }
            return value
        }
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}
