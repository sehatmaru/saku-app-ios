import Foundation

/// Reads a bank or e-wallet notification (title, subtitle, body) into a draft. No amount means there is
/// nothing to record ("Ada transaksi baru, buka aplikasi") and nothing is made. Balances and account
/// numbers are dropped before anything is read; the text itself is never stored.
enum NotificationParser {
    static let supportedApps = ["BCA", "BNI", "Mandiri", "BRI", "Jago", "BNC", "CIMB", "GoPay", "OVO", "DANA"]

    static func parse(app: String, title: String, subtitle: String, body: String, context: SmartParser.Context) -> [Draft] {
        let text = sanitize([title, subtitle, body].filter { !$0.isEmpty }.joined(separator: ". "))
        let foreign = foreignAmount(in: text)
        guard let amount = firstAmount(in: text) ?? foreign?.rupiah else { return [] }
        let lower = text.lowercased()

        let kindWord: String
        if has(lower, ["top up", "topup", "isi saldo"]) { kindWord = "top up" }
        else if has(lower, ["terima", "diterima", "masuk", "kredit", "cashback", "received", "transfer dari", "dikirim oleh", "refund"]) { kindWord = "terima" }
        else { kindWord = "bayar" }

        let merchant = merchantName(in: text) ?? ""
        // The sentence only carries the kind, amount and app (the wallet). Free text such as "Account Transfer
        // category" must not steer the kind, so the merchant is read separately for a title and category.
        let sentence = [kindWord == "bayar" ? "" : kindWord, String(Int(amount)), app].filter { !$0.isEmpty }.joined(separator: " ")
        var drafts = SmartParser.parse(sentence, source: .notification, context: context)
        let hint = merchant.isEmpty ? [] : SmartParser.parse("\(merchant) \(Int(amount))", source: .notification, context: context)
        for index in drafts.indices where drafts[index].amount != nil {
            if !merchant.isEmpty { drafts[index].title = merchant.capitalized }
            if let foreign { drafts[index].title = [drafts[index].title, "(\(foreign.label))"].filter { !$0.isEmpty }.joined(separator: " ") }
            if drafts[index].kind == .expense || drafts[index].kind == .income, drafts[index].categoryId == nil,
               let id = hint.first?.categoryId { drafts[index].categoryId = id }
        }
        return drafts.filter { $0.amount != nil }
    }

    /// Removes balances ("saldo Rp1.234") and long digit runs (account/phone numbers).
    static func sanitize(_ text: String) -> String {
        var result = text
        for pattern in [#"(?i)(sisa\s+)?saldo[^.;]*"#, #"(?<![\d.,])\d{8,}(?![\d.,])"#, #"(?i)no\.?\s*rek[^.;]*"#] {
            result = result.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        return result
    }

    static func firstAmount(in text: String) -> Double? {
        let regex = try! NSRegularExpression(pattern: #"(?i)(?:rp|idr)\.?\s*([\d.,]+\d)"#)
        guard let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        var raw = String(text[r])
        // "12.345,67" and "12,345.67" both end in two decimals; "12.345" is thousands
        if let last = raw.lastIndex(where: { $0 == "," || $0 == "." }) {
            let tail = raw[raw.index(after: last)...]
            if tail.count == 2 { raw = String(raw[..<last]) }
        }
        let value = Double(raw.filter(\.isNumber)) ?? 0
        return value >= 100 ? value : nil
    }

    /// Rupiah per unit of foreign currency. Placeholder estimates: the bank's own statement decides the real amount,
    /// so the draft title keeps the original ("(USD 5.54)") for the owner to check. ponytail: fixed table, fetch rates if it drifts.
    static let rates: [String: Double] = ["USD": 16_500, "SGD": 12_300, "EUR": 18_000, "MYR": 3_700, "AUD": 10_800, "JPY": 110, "GBP": 21_000]

    /// "USD 5.54", "$5,54", "EUR 1,234.50" -> amount in rupiah (estimate) and the original text.
    static func foreignAmount(in text: String) -> (rupiah: Double, label: String)? {
        let codes = rates.keys.joined(separator: "|")
        let regex = try! NSRegularExpression(pattern: "(?i)(?:\\b(\(codes))|(\\$))\\s?([\\d.,]*\\d)")
        guard let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 3), in: text) else { return nil }
        let code = Range(m.range(at: 1), in: text).map { text[$0].uppercased() } ?? "USD"
        var raw = String(text[r])
        var decimals = ""
        if let last = raw.lastIndex(where: { $0 == "," || $0 == "." }) {
            let tail = raw[raw.index(after: last)...]
            if tail.count <= 2 { decimals = "." + tail; raw = String(raw[..<last]) }
        }
        guard let value = Double(raw.filter(\.isNumber) + decimals), value > 0, let rate = rates[code] else { return nil }
        return ((value * rate).rounded(), "\(code) \(String(text[r]))")
    }

    private static func merchantName(in text: String) -> String? {
        let regex = try! NSRegularExpression(pattern: #"(?i)\b(?:ke|kepada|di|to|at|dari|from)\s+([A-Za-z0-9&' ]{2,30}?)(?=\s+(?:rp|idr|senilai|sebesar|berhasil|pada|tgl)|[.,;]|$)"#)
        guard let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        let name = text[r].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    private static func has(_ text: String, _ words: [String]) -> Bool { words.contains { text.contains($0) } }
}
