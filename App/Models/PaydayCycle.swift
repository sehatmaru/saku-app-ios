import Foundation

/// A month that runs from payday to the day before the next payday, e.g. payday 25 gives
/// 25 Sep – 24 Okt. Budgets and "bulan ini" use it; payday 1 is the calendar month.
/// A payday past the month's end (29–31) lands on the month's last day.
struct PaydayCycle: Equatable {
    /// 1...31.
    let day: Int

    init(day: Int) {
        self.day = min(max(day, 1), 31)
    }

    /// The user's cycle: the payday saved on their profile, else the 1st.
    static var current: PaydayCycle { PaydayCycle(day: PaydaySetting.day ?? 1) }

    /// The period that contains `date`: start of its first day up to (not including) the next start.
    func period(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        let day = calendar.startOfDay(for: date)
        let thisMonth = payday(inMonthOf: day, calendar: calendar)
        let start = thisMonth <= day
            ? thisMonth
            : payday(inMonthOf: calendar.date(byAdding: .month, value: -1, to: day) ?? day, calendar: calendar)
        let end = payday(inMonthOf: calendar.date(byAdding: .month, value: 1, to: start) ?? start, calendar: calendar)
        return DateInterval(start: start, end: end)
    }

    /// The period `offset` periods away from the one containing `date` (-1 = the last one).
    func period(offset: Int, from date: Date = Date(), calendar: Calendar = .current) -> DateInterval {
        let base = period(containing: date, calendar: calendar).start
        let shifted = calendar.date(byAdding: .month, value: offset, to: base) ?? base
        return period(containing: payday(inMonthOf: shifted, calendar: calendar), calendar: calendar)
    }

    /// Whether `date` falls in the period containing `reference` (end excluded).
    func contains(_ date: Date, periodOf reference: Date = Date(), calendar: Calendar = .current) -> Bool {
        let period = period(containing: reference, calendar: calendar)
        return date >= period.start && date < period.end
    }

    /// Days in the period and days left after today (today not counted).
    func days(on date: Date = Date(), calendar: Calendar = .current) -> (total: Int, left: Int) {
        let period = period(containing: date, calendar: calendar)
        let total = calendar.dateComponents([.day], from: period.start, to: period.end).day ?? 30
        let passed = calendar.dateComponents([.day], from: period.start, to: calendar.startOfDay(for: date)).day ?? 0
        return (total, max(total - passed - 1, 0))
    }

    /// "25 Sep – 24 Okt", or "September" when payday is the 1st.
    func label(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let period = period(containing: date, calendar: calendar)
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        if day == 1 {
            formatter.dateFormat = "MMMM"
            return formatter.string(from: period.start)
        }
        formatter.dateFormat = "d MMM"
        let last = calendar.date(byAdding: .day, value: -1, to: period.end) ?? period.end
        return formatter.string(from: period.start) + " – " + formatter.string(from: last)
    }

    private func payday(inMonthOf date: Date, calendar: Calendar) -> Date {
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let length = calendar.range(of: .day, in: .month, for: first)?.count ?? 28
        return calendar.date(byAdding: .day, value: min(day, length) - 1, to: first) ?? first
    }
}

/// The payday mirrored on the device so period math needs no network. The profile row is
/// the source of truth; `SupabaseSDK` writes here whenever it reads or saves the profile.
enum PaydaySetting {
    private static let key = "paydayDay"

    /// Nil until the user has set a payday (show the one-time "Kapan kamu gajian?" prompt).
    static var day: Int? {
        get {
            let value = UserDefaults.standard.integer(forKey: key)
            return value == 0 ? nil : value
        }
        set { UserDefaults.standard.set(newValue ?? 0, forKey: key) }
    }
}
