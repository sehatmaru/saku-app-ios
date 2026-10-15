import Foundation

/// Hapus akun: the sentence to type, the survey reasons, and reading the date the server answers with.
/// The account waits 30 days after the request and can be cancelled by signing in again.
enum AccountDeletion {
    static let graceDays = 30

    /// Typed to enable the button: matched without regard to case and ignoring spaces at the ends, in either language.
    static func phraseMatches(_ input: String) -> Bool {
        let typed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return typed == "hapus akun saya" || typed == "delete my account"
    }

    /// The reasons of the one-question survey; `key` is what the server stores.
    enum Reason: String, CaseIterable, Identifiable {
        case notUsing = "tidak_pakai", otherApp = "pindah_aplikasi", features = "fitur_kurang"
        case privacy = "privasi", price = "mahal", other = "lainnya"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .notUsing: return L("Tidak lagi menggunakan Saku")
            case .otherApp: return L("Pindah ke aplikasi lain")
            case .features: return L("Fiturnya kurang sesuai")
            case .privacy: return L("Khawatir privasi data")
            case .price: return L("Terlalu mahal (Saku Plus)")
            case .other: return L("Lainnya")
            }
        }
    }

    static let noteLimit = 200

    /// The server sends a timestamptz such as `2026-11-14T06:00:00.123456+00:00`.
    static func parse(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        // Postgres writes microseconds; keep three digits so the formatter accepts it
        if let dot = raw.firstIndex(of: "."), let zone = raw[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            let digits = raw[raw.index(after: dot)..<zone]
            return withFraction.date(from: String(raw[..<dot]) + "." + digits.prefix(3) + String(raw[zone...]))
        }
        let plain = ISO8601DateFormatter()
        return plain.date(from: raw)
    }

    /// "14 November 2026" in the app language.
    static func dayText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = AppLanguage.locale
        f.dateStyle = .long
        f.timeStyle = .none
        return f.string(from: date)
    }
}
