import Foundation

/// Turns the text read from a picture (payment proof, bank history, receipt) into drafts. Rules only, on the device.
/// One picture is one draft with its total; a bank history screenshot becomes one draft per row (at most 20).
/// Balances and account numbers are dropped first; the text is never stored.
enum ImageParser {
    static let limit = 20

    struct Reading {
        var drafts: [Draft] = []
        /// More rows than `limit`; the rest were left out.
        var truncated = false
    }

    private static let apps: [(name: String, words: [String])] = [
        ("GoPay", ["gopay", "gojek"]), ("OVO", ["ovo"]), ("DANA", ["dana"]), ("BCA", ["bca"]), ("BNI", ["bni", "wondr"]),
        ("Mandiri", ["mandiri", "livin"]), ("BRI", ["bri", "brimo"]), ("Jago", ["jago"]), ("BNC", ["bnc", "neo commerce"]),
        ("CIMB", ["cimb"])]

    static func parse(lines raw: [String], context: SmartParser.Context) -> Reading {
        let lines = raw.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !isBalance($0) }
        guard !lines.isEmpty else { return Reading() }
        let joined = lines.joined(separator: "\n").lowercased()
        let app = apps.first { entry in entry.words.contains { word in wordMatch(word, in: joined) } }?.name ?? ""

        // a history: several dated rows that each carry an amount
        let blocks = dateBlocks(lines)
        let rows = blocks.filter { amount(in: $0.lines.joined(separator: " ")) != nil }
        if rows.count >= 2 {
            var reading = Reading()
            reading.truncated = rows.count > limit
            reading.drafts = rows.prefix(limit).compactMap { row in
                let text = row.lines.joined(separator: " ")
                guard let value = amount(in: text) else { return nil }
                return makeDraft(kindText: text.lowercased(), amount: value, title: title(from: row.lines), date: row.date, app: app, context: context)
            }
            return reading
        }

        // one proof or receipt
        var uncertain = false
        guard let total = total(in: lines, uncertain: &uncertain) else { return Reading() }
        let found = lines.lazy.compactMap { date(in: $0, calendar: context.calendar) }.first
        var draft = makeDraft(kindText: joined, amount: total, title: merchant(in: lines), date: found ?? context.now, app: app, context: context)
        if found == nil { draft.note = L("Tanggal tidak terlihat, dipakai hari ini. Cek lagi.") }
        else if uncertain { draft.note = L("Total kurang yakin. Cek lagi.") }
        if found == nil && uncertain { draft.note = L("Tanggal dan total kurang yakin. Cek lagi.") }
        return Reading(drafts: [draft])
    }

    // MARK: Building

    private static func makeDraft(kindText: String, amount: Double, title: String, date: Date, app: String, context: SmartParser.Context) -> Draft {
        let kindWord: String
        if has(kindText, ["top up", "topup", "isi saldo"]) { kindWord = "top up" }
        else if has(kindText, ["diterima", "terima", "masuk", "kredit", " cr ", "cashback", "refund", "received"]) { kindWord = "terima" }
        else { kindWord = "bayar" }
        let sentence = [kindWord == "bayar" ? "" : kindWord, String(Int(amount)), app].filter { !$0.isEmpty }.joined(separator: " ")
        var draft = SmartParser.parse(sentence, source: .photo, context: context).first ?? Draft()
        draft.source = .photo
        draft.amount = amount
        draft.date = date
        draft.sourceName = app.isEmpty ? nil : app
        if !title.isEmpty {
            draft.title = title
            let hint = SmartParser.parse("\(title) \(Int(amount))", source: .photo, context: context).first
            if (draft.kind == .expense || draft.kind == .income), draft.categoryId == nil { draft.categoryId = hint?.categoryId }
        }
        return draft
    }

    private static func has(_ text: String, _ words: [String]) -> Bool { words.contains { text.contains($0) } }

    private static func wordMatch(_ word: String, in text: String) -> Bool {
        text.range(of: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b", options: .regularExpression) != nil
    }

    // MARK: Lines

    private static func isBalance(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("saldo") || lower.contains("balance") || lower.contains("no. rek") || lower.contains("no rek")
            || line.range(of: #"(?<![\d.,])\d{9,}(?![\d.,])"#, options: .regularExpression) != nil
    }

    private struct Block { var date: Date; var lines: [String] }

    private static func dateBlocks(_ lines: [String]) -> [Block] {
        var blocks: [Block] = []
        for line in lines {
            if let d = date(in: line, calendar: .current) { blocks.append(Block(date: d, lines: [line])) }
            else if !blocks.isEmpty { blocks[blocks.count - 1].lines.append(line) }
        }
        return blocks
    }

    // MARK: Fields

    private static let amountRegex = try! NSRegularExpression(
        pattern: #"(?i)(?:rp|idr)\.?\s*([\d.,]*\d)|(?<![\d.,])(\d{1,3}(?:\.\d{3})+(?:,\d{2})?)(?![\d.])"#)

    /// The first amount in a text: with Rp, or written with thousands dots (25.000). Under 100 is ignored.
    static func amount(in text: String) -> Double? { amounts(in: text).first }

    static func amounts(in text: String) -> [Double] {
        let range = NSRange(text.startIndex..., in: text)
        return amountRegex.matches(in: text, range: range).compactMap { m in
            let group = [1, 2].compactMap { Range(m.range(at: $0), in: text) }.first
            guard let group else { return nil }
            var raw = String(text[group])
            if let last = raw.lastIndex(where: { $0 == "," || $0 == "." }), raw[raw.index(after: last)...].count == 2 {
                raw = String(raw[..<last])
            }
            let value = Double(raw.filter(\.isNumber)) ?? 0
            return value >= 100 ? value : nil
        }
    }

    private static let totalWords = #"(?i)\b(total(\s*(bayar|pembayaran|tagihan|belanja|transaksi))?|grand\s*total|jumlah|nominal|amount|total\s*payment)\b"#
    private static let skipWords = #"(?i)(sub\s*total|pajak|ppn|tax|service|tunai|cash|kembali|change|diskon|hemat|admin|biaya)"#

    /// The total: the last line labelled "Total", "Jumlah" or "Nominal" (amount on it or on the next line);
    /// otherwise the largest amount, marked uncertain.
    private static func total(in lines: [String], uncertain: inout Bool) -> Double? {
        var labelled: Double?
        for (i, line) in lines.enumerated() where line.range(of: totalWords, options: .regularExpression) != nil
            && line.range(of: skipWords, options: .regularExpression) == nil {
            if let value = amount(in: line) ?? (i + 1 < lines.count ? amount(in: lines[i + 1]) : nil) { labelled = value }
        }
        if let labelled { return labelled }
        let all = lines.filter { $0.range(of: skipWords, options: .regularExpression) == nil }.flatMap { amounts(in: $0) }
        uncertain = true
        return all.max()
    }

    /// "ke X", "kepada X", "merchant X", else the first line that looks like a shop name.
    private static func merchant(in lines: [String]) -> String {
        let label = try! NSRegularExpression(pattern: #"(?i)^(?:ke|kepada|penerima|merchant|to|tujuan)\s*[:\-]?\s+(.{2,30})$"#)
        for line in lines {
            if let m = label.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)), let r = Range(m.range(at: 1), in: line),
               amount(in: line) == nil { return clean(String(line[r])) }
        }
        for (i, line) in lines.enumerated() where line.range(of: #"(?i)^(penerima|merchant|kepada|tujuan)\s*:?$"#, options: .regularExpression) != nil {
            if i + 1 < lines.count, amount(in: lines[i + 1]) == nil { return clean(lines[i + 1]) }
        }
        return title(from: lines)
    }

    /// The first line made of words: no date, amount, phone, address or label.
    private static func title(from lines: [String]) -> String {
        let skip = #"(?i)(struk|nota|invoice|receipt|npwp|telp|tel\.|jl\.|jalan|berhasil|sukses|berhasil|transaksi|pembayaran|bukti|total|jumlah|nominal|tanggal|waktu|status|kode|ref|id )"#
        for line in lines {
            let letters = line.filter(\.isLetter).count
            if letters >= 3, line.range(of: skip, options: .regularExpression) == nil, amount(in: line) == nil,
               date(in: line, calendar: .current) == nil || letters > 8 { return clean(strip(line)) }
        }
        return ""
    }

    /// Removes dates, times and amounts from a row so only the name is left.
    private static func strip(_ line: String) -> String {
        var s = line
        for p in [#"\d{1,2}[\s/.-](\d{1,2}|[A-Za-z]{3,9})[\s/.-]\d{2,4}"#, #"\d{1,2}[:.]\d{2}(:\d{2})?"#, #"(?i)(rp|idr)\.?\s*[\d.,]+"#,
                  #"[-+]?\d{1,3}(\.\d{3})+(,\d{2})?"#, #"(?i)\b(db|cr)\b"#] {
            s = s.replacingOccurrences(of: p, with: " ", options: .regularExpression)
        }
        return s
    }

    private static func clean(_ text: String) -> String {
        let t = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " :-.,*#"))
        return String(t.prefix(30)).capitalized
    }

    // MARK: Dates

    private static let months: [String: Int] = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "mei": 5, "may": 5, "jun": 6, "jul": 7,
                                                "agu": 8, "ags": 8, "aug": 8, "sep": 9, "okt": 10, "oct": 10, "nov": 11, "des": 12, "dec": 12]
    private static let dateRegex = try! NSRegularExpression(pattern: #"(?<!\d)(\d{1,2})[\s/.-]([A-Za-z]{3,9}|\d{1,2})[\s/.-](\d{4}|\d{2})(?!\d)"#)

    /// "14 Okt 2026", "14/10/2026", "14-10-26"; nil when the line has no date.
    static func date(in line: String, calendar: Calendar) -> Date? {
        guard let m = dateRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let r1 = Range(m.range(at: 1), in: line), let r2 = Range(m.range(at: 2), in: line), let r3 = Range(m.range(at: 3), in: line),
              let day = Int(line[r1]) else { return nil }
        let monthText = line[r2].lowercased()
        guard let month = Int(monthText) ?? months[String(monthText.prefix(3))], (1...12).contains(month), (1...31).contains(day),
              var year = Int(line[r3]) else { return nil }
        if year < 100 { year += 2000 }
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }
}
