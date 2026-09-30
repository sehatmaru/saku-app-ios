import Foundation

/// "Belum" on the overdue-bill reminder: the reminder stays quiet until the given time. Kept
/// on the device, keyed by card and statement, so a new statement asks again on its own.
struct BillReminderStore {
    private let defaults: UserDefaults
    private static let key = "billReminderSnoozedUntil"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func id(card: String, statementDate: Date) -> String {
        "\(card)|\(Int(statementDate.timeIntervalSince1970))"
    }

    private var stored: [String: Double] {
        defaults.dictionary(forKey: Self.key) as? [String: Double] ?? [:]
    }

    func snooze(card: String, statementDate: Date, until: Date) {
        var all = stored
        all[id(card: card, statementDate: statementDate)] = until.timeIntervalSince1970
        defaults.set(all, forKey: Self.key)
    }

    /// When the reminder wakes up again; nil once that time has passed or it was never snoozed.
    func snoozedUntil(card: String, statementDate: Date, now: Date = Date()) -> Date? {
        guard let until = stored[id(card: card, statementDate: statementDate)], until > now.timeIntervalSince1970 else { return nil }
        return Date(timeIntervalSince1970: until)
    }

    func isSnoozed(card: String, statementDate: Date, now: Date = Date()) -> Bool {
        snoozedUntil(card: card, statementDate: statementDate, now: now) != nil
    }

    func clear(card: String, statementDate: Date) {
        var all = stored
        all[id(card: card, statementDate: statementDate)] = nil
        defaults.set(all, forKey: Self.key)
    }

    /// Tomorrow at 09:00, when the reminder speaks up again.
    static func tomorrowMorning(from now: Date = Date(), calendar: Calendar = .current) -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}
