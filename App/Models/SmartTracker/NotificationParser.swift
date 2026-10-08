import Foundation

/// Reads a bank or e-wallet notification (title, subtitle, body) into a draft. No amount means there is
/// nothing to record ("Ada transaksi baru, buka aplikasi") and nothing is made. Balances and account
/// numbers are dropped before anything is read; the text itself is never stored.
enum NotificationParser {
    static let supportedApps = ["BCA", "BNI", "Mandiri", "BRI", "Jago", "BNC", "CIMB", "GoPay", "OVO", "DANA"]

    static func parse(app: String, title: String, subtitle: String, body: String, context: SmartParser.Context) -> [Draft] {
        let text = sanitize([title, subtitle, body].filter { !$0.isEmpty }.joined(separator: ". "))
        guard let amount = firstAmount(in: text) else { return [] }
        let lower = text.lowercased()

        let kindWord: String
        if has(lower, ["top up", "topup", "isi saldo"]) { kindWord = "top up" }
        else if has(lower, ["terima", "diterima", "masuk", "kredit", "cashback", "received", "transfer dari", "dikirim oleh", "refund"]) { kindWord = "terima" }
        else { kindWord = "bayar" }

        let merchant = merchantName(in: text) ?? ""
        // A short sentence the normal parser understands: wallet comes from the app, the rest from the text.
        let sentence = [kindWord == "bayar" ? "" : kindWord, merchant, String(Int(amount)), app].filter { !$0.isEmpty }.joined(separator: " ")
        var drafts = SmartParser.parse(sentence, source: .notification, context: context)
        for index in drafts.indices where drafts[index].amount != nil {
            drafts[index].title = merchant.isEmpty ? drafts[index].title : merchant.capitalized
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

    private static func merchantName(in text: String) -> String? {
        let regex = try! NSRegularExpression(pattern: #"(?i)\b(?:ke|kepada|di|to|at|dari|from)\s+([A-Za-z0-9&' ]{2,30}?)(?=\s+(?:rp|idr|senilai|sebesar|berhasil|pada|tgl)|[.,;]|$)"#)
        guard let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        let name = text[r].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    private static func has(_ text: String, _ words: [String]) -> Bool { words.contains { text.contains($0) } }
}
