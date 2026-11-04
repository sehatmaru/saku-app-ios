import Foundation
import Supabase

/// This month's AI help from the server: free accounts get a base allowance plus the referral bonus; Plus is
/// unlimited (`left` is nil). Months follow Asia/Jakarta.
struct AIQuotaReading: Equatable, Decodable {
    let isPlus: Bool
    let base: Int
    let referralBonus: Int
    let total: Int?
    let used: Int
    let left: Int?

    enum CodingKeys: String, CodingKey {
        case isPlus = "is_plus", base, referralBonus = "referral_bonus", total, used, left
    }

    var isOut: Bool { left == 0 }

    /// First day of next month in Asia/Jakarta, when the allowance starts over.
    static var resetDate: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jakarta") ?? .current
        let start = calendar.dateInterval(of: .month, for: Date())?.end
        return start ?? Date()
    }
}

/// Keeps the latest quota for Pengaturan and Konfirmasi transaksi; refreshed when those open and after every AI reading.
@MainActor
final class AIQuotaStore: ObservableObject {
    static let shared = AIQuotaStore()
    @Published private(set) var quota: AIQuotaReading?
    /// The last refresh failed and there is nothing to show yet (offline, or the quota migration not run).
    @Published private(set) var failed = false

    func refresh() async {
        guard !DraftStore.shared.isGuest else { quota = nil; failed = false; return }
        if let fresh: AIQuotaReading = try? await SupabaseSDK.client.rpc("ai_quota").execute().value {
            quota = fresh
            failed = false
        } else {
            failed = quota == nil
        }
    }

    func reset() { quota = nil; failed = false }
}
