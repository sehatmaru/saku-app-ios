import Foundation

/// "Pengingat" on an investment wallet (Fitur 7 US3): how often to be asked to update its value. Kept on the device
/// only, one setting per wallet, off until chosen.
enum InvestmentReminder: String, CaseIterable, Identifiable {
    case off, weekly, biweekly, monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: L("Mati")
        case .weekly: L("Mingguan")
        case .biweekly: L("Dua mingguan")
        case .monthly: L("Bulanan")
        }
    }

    /// The next 09:00 at least one interval after the last update; when that is already past (a stale value),
    /// the coming 09:00, so a late reminder speaks up soon instead of waiting a whole interval more.
    func nextFire(lastUpdated: Date?, now: Date = Date(), calendar: Calendar = .current) -> Date? {
        let days: Int
        switch self {
        case .off: return nil
        case .weekly: days = 7
        case .biweekly: days = 14
        case .monthly: days = 0
        }
        let base = lastUpdated ?? now
        let target = days > 0 ? calendar.date(byAdding: .day, value: days, to: base) : calendar.date(byAdding: .month, value: 1, to: base)
        guard let target,
              let planned = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: calendar.startOfDay(for: target)) else { return nil }
        if planned > now { return planned }
        let today = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: calendar.startOfDay(for: now))
        if let today, today > now { return today }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
    }
}

struct InvestmentReminderStore {
    private let defaults: UserDefaults
    private static let prefix = "investmentReminder."
    private static let offeredKey = "investmentReminderOffered"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func interval(for accountId: String) -> InvestmentReminder {
        defaults.string(forKey: Self.prefix + accountId).flatMap(InvestmentReminder.init(rawValue:)) ?? .off
    }

    func set(_ interval: InvestmentReminder, for accountId: String) {
        if interval == .off { defaults.removeObject(forKey: Self.prefix + accountId) }
        else { defaults.set(interval.rawValue, forKey: Self.prefix + accountId) }
    }

    /// "Mau diingatkan?" is asked once, after the first investment wallet is made.
    var wasOffered: Bool {
        get { defaults.bool(forKey: Self.offeredKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.offeredKey) }
    }

    /// Signing out or deleting the account: nothing of this stays on the device.
    func clearAll() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.prefix) { defaults.removeObject(forKey: key) }
        defaults.removeObject(forKey: Self.offeredKey)
    }
}
