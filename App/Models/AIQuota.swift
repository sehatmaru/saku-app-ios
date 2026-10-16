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

/// Friends who joined with this account's code (design "Plus C Ajak Teman"). Sample data until the server has
/// referral codes; shown in test builds only.
struct ReferralSummary: Equatable {
    struct Friend: Identifiable, Equatable {
        let id = UUID()
        let name: String
        /// nil = still waiting for the first transaction.
        let joined: String?
        let month: String
    }

    static let monthlyLimit = 4
    static let perFriend = 5

    var code: String
    var friends: [Friend]

    var thisMonth: Int { friends.filter { $0.month == "Oktober 2026" && $0.joined != nil }.count }
    var reward: Int { thisMonth * Self.perFriend }
    var isMaxed: Bool { thisMonth >= Self.monthlyLimit }

    static func sample(count: Int) -> ReferralSummary {
        let names = ["Dimas", "Teman", "Siti Nurhaliza Rahmawati Putri", "Agus"]
        var list: [Friend] = []
        for i in 0..<count { list.append(Friend(name: names[i % 3], joined: "\(14 - i) Okt", month: "Oktober 2026")) }
        if count > 0 { list.append(Friend(name: names[2], joined: nil, month: "Oktober 2026")) }
        list.append(Friend(name: names[3], joined: "21 Sep", month: "September 2026"))
        return ReferralSummary(code: "RINA4K7", friends: list)
    }
}
