import Foundation

/// Runs on the phone before any text goes to the language model: long digit runs (account and card numbers) and
/// one-time codes are cut out, so they never leave the device.
enum SmartTextScrubber {
    static let removed = "•••"

    static func clean(_ text: String) -> String {
        var out = text
        // one-time codes: the digits that follow "OTP", "kode", "pin" or "verifikasi"
        out = out.replacingOccurrences(
            of: #"(?i)\b(otp|kode|code|pin|verifikasi|verification)\b([^0-9\n]{0,14})\d{4,8}\b"#,
            with: "$1$2" + removed, options: .regularExpression)
        // 10 or more digits in a row, also when split by spaces or hyphens (accounts, cards); amounts use dots and commas
        out = out.replacingOccurrences(of: #"\b\d(?:[ \-]?\d){9,}\b"#, with: removed, options: .regularExpression)
        return out
    }
}
