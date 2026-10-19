import XCTest
@testable import Saku

/// Design "Sheet Pengaturan": "Ekspor XLS" writes a real workbook (a zip of XML parts),
/// with the same columns as the CSV files and numbers that a spreadsheet can sum.
final class XlsxExportTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private let wallet = Account(id: "bca", name: "BCA <Utama>", type: .bank, icon: nil, isArchived: false, isDefault: true,
                                 openingBalance: 1_000_000, currentBalance: 2_500_000, creditLimit: nil, dueDate: nil)
    private let coffee = Saku.Category(id: "kopi", name: "Makan, Minum", icon: nil, color: nil, type: .expense, systemKey: nil)

    private var transaction: Transaction {
        Transaction(id: "t1", accountId: "bca", counterpartyAccountId: nil, categoryId: "kopi", amount: 25_000,
                    type: .expense, description: "Kopi Kenangan", note: nil, date: date(2026, 10, 10), delta: nil)
    }

    private func count(of pattern: [UInt8], in data: Data) -> Int {
        var found = 0
        let bytes = [UInt8](data)
        guard bytes.count >= pattern.count else { return 0 }
        for index in 0...(bytes.count - pattern.count) where Array(bytes[index..<index + pattern.count]) == pattern {
            found += 1
        }
        return found
    }

    /// The file is a zip that opens as a workbook: five parts, ending with the central directory.
    func testWorkbookIsAZipWithTheExpectedParts() throws {
        let sheet = XlsxExport.transactions([transaction], accounts: [wallet], categories: [coffee])
        let data = try XCTUnwrap(XlsxExport.data([sheet]))

        XCTAssertEqual(Array(data.prefix(4)), [0x50, 0x4B, 0x03, 0x04], "local file header")
        XCTAssertEqual(Array(data.suffix(22).prefix(4)), [0x50, 0x4B, 0x05, 0x06], "end of central directory")
        XCTAssertEqual(count(of: [0x50, 0x4B, 0x01, 0x02], in: data), 5, "4 fixed parts + 1 worksheet")

        let text = String(decoding: data, as: UTF8.self)
        for name in ["[Content_Types].xml", "_rels/.rels", "xl/workbook.xml", "xl/_rels/workbook.xml.rels", "xl/worksheets/sheet1.xml"] {
            XCTAssertTrue(text.contains(name), "part \(name)")
        }
    }

    /// Same columns as the CSV sheet (TC 46) so the workbook matches the app's words.
    func testTransactionsSheetKeepsTheAppColumns() {
        let sheet = XlsxExport.transactions([transaction], accounts: [wallet], categories: [coffee])

        XCTAssertEqual(sheet.name, "Transaksi")
        XCTAssertEqual(sheet.header, ["Tanggal", "Jenis", "Kategori", "Dompet", "Dompet tujuan", "Nominal", "Catatan"])
        XCTAssertEqual(sheet.rows.first, ["2026-10-10", "Pengeluaran", "Makan, Minum", "BCA <Utama>", "", "25000", "Kopi Kenangan"])
    }

    /// Amounts become real numbers so the sheet can sum them, text is escaped inside the cell.
    func testCellsAreEscapedTextAndRealNumbers() throws {
        let sheet = XlsxExport.transactions([transaction], accounts: [wallet], categories: [coffee])
        let data = try XCTUnwrap(XlsxExport.data([sheet]))
        let text = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(text.contains("<is><t xml:space=\"preserve\">BCA &lt;Utama&gt;</t></is>"), "escaped wallet name")
        XCTAssertTrue(text.contains("<is><t xml:space=\"preserve\">Makan, Minum</t></is>"), "a comma stays untouched")
        XCTAssertTrue(text.contains("<v>25000</v>"), "plain number, no separators")
        XCTAssertFalse(text.contains("'25000"), "numbers are not text")
    }

    /// Picked periods keep only what is inside them; nil keeps everything.
    func testIntervalsFilterTheRows() {
        let other = Transaction(id: "t2", accountId: "bca", counterpartyAccountId: nil, categoryId: nil, amount: 5_000,
                                type: .expense, description: nil, note: nil, date: date(2026, 9, 1), delta: nil)
        let interval = DateInterval(start: date(2026, 10, 1), end: date(2026, 10, 15))
        let sheets = XlsxExport.transactions([transaction, other], accounts: [wallet], categories: [coffee], intervals: [interval])
        XCTAssertEqual(sheets.rows.count, 1, "only the October transaction")

        let all = XlsxExport.transactions([transaction, other], accounts: [wallet], categories: [coffee], intervals: nil)
        XCTAssertEqual(all.rows.count, 2)
    }

    func testWalletsAndBudgetsSheets() {
        let wallets = XlsxExport.wallets([wallet])
        XCTAssertEqual(wallets.header, ["Nama", "Jenis", "Saldo Saat Ini", "Saldo Awal"])
        XCTAssertEqual(wallets.rows.first, ["BCA <Utama>", "Bank", "2500000", "1000000"])

        let budget = Budget(id: "b1", categoryId: "kopi", name: "Kopi", amount: 500_000, periodUnit: "month",
                            periodInterval: 1, startDate: "2026-01-01", endDate: nil, isActive: true,
                            spent: 123_456, temporary: nil, baseAmount: nil)
        let budgets = XlsxExport.budgets([budget], categories: [coffee])
        XCTAssertEqual(budgets.header, ["Kategori", "Nominal", "Periode", "Terpakai"])
        XCTAssertEqual(budgets.rows.first?[0], "Makan, Minum")
        XCTAssertEqual(budgets.rows.first?[1], "500000")
        XCTAssertEqual(budgets.rows.first?[3], "123456")
    }

    /// Excel refuses some characters in sheet names, and caps them at 31.
    func testSheetNamesAreSanitized() throws {
        let bad = XlsxExport.Sheet(name: "A/B:C*D?E[F]G]H\\I - a very very long name that runs over the cap",
                                   header: ["H"], rows: [["1"]])
        let data = try XCTUnwrap(XlsxExport.data([bad]))
        let text = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(text.contains("A/B:C*D"), "forbidden characters are replaced")
        XCTAssertTrue(text.contains("A B C D E F G H I - a very very"), "name is cut to 31 characters")
    }

    func testNothingToWriteReturnsNil() {
        XCTAssertNil(XlsxExport.data([]))
    }

    func testWritePlacesTheFileInTemporaryFolder() throws {
        let sheet = XlsxExport.transactions([transaction], accounts: [wallet], categories: [coffee])
        let url = try XCTUnwrap(XlsxExport.write([sheet], name: "saku-test.xlsx"))
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertGreaterThan((try Data(contentsOf: url)).count, 500)
    }
}
