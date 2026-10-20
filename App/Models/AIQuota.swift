import Foundation

/// AI help left this month (design "Plus D Jatah AI"). The server does not count it yet, so for now this is a
/// sample, shown in test builds only.
struct AIQuota: Equatable {
    var left: Int
    var total: Int
    var isPlus = false
    /// What friends added this month.
    var fromFriends = 5

    enum Level { case normal, low, empty }

    var level: Level { left == 0 ? .empty : left <= 3 ? .low : .normal }
    var used: Int { total - left }
    /// The monthly base: 10 free, or what Plus gives.
    var base: Int { total - fromFriends }

    static let sample = AIQuota(left: 9, total: 15)

    /// Free sample at a level, or Plus.
    static func sample(_ level: Level, isPlus: Bool) -> AIQuota {
        if isPlus { return AIQuota(left: 182, total: 200, isPlus: true) }
        switch level {
        case .normal: return AIQuota(left: 9, total: 15)
        case .low: return AIQuota(left: 2, total: 15)
        case .empty: return AIQuota(left: 0, total: 15)
        }
    }

    /// Used / total split the way the page lists it: free text, receipt photos, email.
    var uses: [(icon: String, label: String, count: Int)] {
        let text = Int((Double(used) * 0.6).rounded()), photo = Int((Double(used) * 0.3).rounded())
        return [("textformat", L("Teks bebas"), text), ("camera", L("Foto struk"), photo), ("envelope", L("Email"), used - text - photo)]
    }
}

/// The "Ajak teman" page (design "Plus C Ajak Teman"): this account's code, this month's progress and every friend
/// who joined with it. Comes from the server's `referral_summary()` (Fitur 2).
struct ReferralSummary: Equatable {
    struct Friend: Identifiable, Equatable {
        let id: String
        /// "Teman" unless the friend allowed their name to show.
        let name: String
        /// "14 Okt" once the first transaction is recorded; nil while the friend is still waiting.
        let joined: String?
        /// The month the friend counts in: the month of the first transaction, else of joining.
        let month: String
        /// Over the month's cap of 4: listed, but adds nothing.
        let counts: Bool
    }

    static let monthlyLimit = 4
    static let perFriend = 5
    /// Where the invitation link points; one place to change once the App Store page exists.
    static let inviteLinkBase = "https://saku.app/u/"

    var code: String
    var friends: [Friend]
    var thisMonth: Int
    var reward: Int

    var isMaxed: Bool { thisMonth >= Self.monthlyLimit }
    var waiting: Int { friends.filter { $0.joined == nil }.count }
    var inviteLink: String { Self.inviteLinkBase + code }

    /// How many friends newly counted since the app last looked, for the small "hadiah masuk" notice. The first look
    /// of a month only remembers the count (a new month starts at zero), so nothing is announced twice.
    /// `stored` is "yyyy-MM:count" from the last look; returns what to show and what to store.
    static func rewardDelta(thisMonth: Int, monthKey: String, stored: String?) -> (newFriends: Int, stored: String) {
        let now = "\(monthKey):\(thisMonth)"
        guard let stored, stored.hasPrefix(monthKey + ":"), let seen = Int(stored.dropFirst(monthKey.count + 1)) else {
            // no earlier look in this month: only an earlier look in another month means these are new
            return (stored == nil ? 0 : thisMonth, now)
        }
        return (max(0, thisMonth - seen), now)
    }

    private struct DTO: Decodable {
        struct FriendDTO: Decodable {
            let id: String
            let name: String?
            let status: String
            let joined_at: String
            let first_transaction_at: String?
            let counts: Bool
        }
        let code: String?
        let this_month: Int
        let bonus: Int
        let friends: [FriendDTO]
    }

    /// nil code (a guest) is not a valid summary: guests have no referral.
    static func decode(_ data: Data) throws -> ReferralSummary {
        let dto = try JSONDecoder().decode(DTO.self, from: data)
        guard let code = dto.code else { throw DecodingError.valueNotFound(String.self, .init(codingPath: [], debugDescription: "no code")) }
        let month = DateFormatter(); month.locale = AppLanguage.locale; month.dateFormat = "MMMM yyyy"
        let day = DateFormatter(); day.locale = AppLanguage.locale; day.dateFormat = "d MMM"
        let friends = dto.friends.map { f -> Friend in
            let done = f.first_transaction_at.flatMap(parse)
            let when = done ?? parse(f.joined_at) ?? Date()
            return Friend(id: f.id, name: f.name ?? L("Teman"), joined: done.map { day.string(from: $0) },
                          month: month.string(from: when), counts: f.counts)
        }
        return ReferralSummary(code: code, friends: friends, thisMonth: dto.this_month, reward: dto.bonus)
    }

    private static func parse(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

/// Why a code was refused, in words the user can act on (server codes from `redeem_referral_code`).
enum ReferralFailure {
    static func message(for error: Error) -> String {
        let text = "\(error)"
        if text.contains("referral_invalid_code") { return L("Kode tidak ditemukan. Periksa lagi atau kosongkan untuk melewati.") }
        if text.contains("referral_own_code") { return L("Kamu tidak bisa memakai kodemu sendiri.") }
        if text.contains("referral_already_used") { return L("Akunmu sudah memakai satu kode. Satu akun hanya bisa memakai satu kode.") }
        if text.contains("referral_too_late") { return L("Kode hanya bisa dipakai oleh akun baru yang belum mencatat transaksi.") }
        if text.contains("referral_guest") { return L("Akun tamu belum bisa memakai kode ajak.") }
        return L("Kode belum bisa diperiksa. Periksa koneksimu lalu coba lagi.")
    }
}
