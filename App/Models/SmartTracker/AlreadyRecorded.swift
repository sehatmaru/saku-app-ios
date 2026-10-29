import Foundation

/// A notification that was not turned into a draft because it is already recorded in Saku: the
/// monthly part of a running installment or an active recurring bill (Enhancement 3, K1, K5).
/// Kept until the day of the notification is over, so the queue can show it and the user can undo it (K10).
struct SkippedNotice: Identifiable, Codable, Hashable {
    var id = UUID()
    /// What the notification would have become; Batalkan hands it back as a normal draft.
    var draft: Draft
    var match: AlreadyRecorded.Match
    var at = Date()

    var expiresAt: Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: draft.date)) ?? at
    }
}

/// Matches a notification draft against what is already recorded: running installment parts and
/// registered recurring bills (Enhancement 3). Read-only: nothing is written back to any of them.
enum AlreadyRecorded {
    enum Match: Codable, Hashable {
        case installment(title: String)
        case bill(name: String)
    }

    /// A billing date within this many days of the notification (K4).
    static let dayWindow = 3
    /// The bank's own rounding may differ a little from the purchase divided by the months (K3, K11).
    static let installmentTolerance = 2.0
    /// Recurring bills match on the exact amount (K3).
    static let billTolerance = 0.005

    /// The one thing this notification is already recorded as, or nil when none match or more than
    /// one matches without a wallet to tell them apart (K7).
    static func match(draft: Draft, installments: [RunningInstallment], subscriptions: [CardSubscription],
                      recent: [Transaction], calendar: Calendar = .current) -> Match? {
        guard draft.source == .notification, let amount = draft.amount, amount > 0 else { return nil }

        struct Candidate {
            let key: String
            let match: Match
            let accountId: String
        }
        var candidates: [Candidate] = []

        for plan in installments where abs(plan.monthly - amount) <= installmentTolerance {
            guard plan.billingDates.contains(where: { within(days: dayWindow, of: $0, draft.date, calendar) }) else { continue }
            candidates.append(Candidate(key: "i:\(plan.id)", match: .installment(title: plan.title), accountId: plan.accountId))
        }
        for sub in subscriptions where sub.isActive && abs(sub.amount - amount) < billTolerance {
            guard let billingDate = sub.nextBillingDateAsDate,
                  within(days: dayWindow, of: billingDate, draft.date, calendar) else { continue }
            candidates.append(Candidate(key: "b:\(sub.name)", match: .bill(name: sub.name), accountId: sub.accountId))
        }
        // A bill may already have posted its transaction; the roll-forward moves the registered
        // bill's own date away, so the posted transaction is what still matches (K1, US2).
        for txn in recent where txn.isRecurring && abs(txn.amount - amount) < billTolerance {
            guard within(days: dayWindow, of: txn.date, draft.date, calendar) else { continue }
            let name = txn.recurringName ?? ""
            candidates.append(Candidate(key: "b:\(name)", match: .bill(name: name), accountId: txn.accountId))
        }

        // The registered bill and its posted transaction are the same thing.
        var seen = Set<String>()
        let unique = candidates.filter { seen.insert($0.key).inserted }

        switch unique.count {
        case 0: return nil
        case 1: return unique[0].match
        default:
            // Ambiguous: only the wallet can tell them apart, and without one the draft stays (K7).
            guard let wallet = draft.accountId else { return nil }
            let onWallet = unique.filter { $0.accountId == wallet }
            return onWallet.count == 1 ? onWallet[0].match : nil
        }
    }

    /// Whether `date` is within `days` of `reference` (either side), by whole days.
    static func within(days: Int, of reference: Date, _ date: Date, _ calendar: Calendar) -> Bool {
        let delta = calendar.dateComponents([.day], from: calendar.startOfDay(for: reference),
                                            to: calendar.startOfDay(for: date)).day ?? 99
        return abs(delta) <= days
    }
}
