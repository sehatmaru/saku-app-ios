import Foundation

/// A month that runs from payday to the day before the next payday, e.g. payday 25 gives
/// 25 Sep – 24 Okt. Budgets and "bulan ini" use it; payday 1 is the calendar month.
/// A payday past the month's end (29–31) lands on the month's last day.
struct PaydayCycle: Equatable {
    /// 1...31. With a schedule, the payday in force today.
    let day: Int
    /// Payday history, oldest first: from `from` on, the payday is `day`. Empty = `day` always.
    /// A change takes effect at a period boundary, so past and running periods keep their dates.
    let schedule: [PaydayEntry]

    init(day: Int, schedule: [PaydayEntry] = []) {
        self.day = min(max(day, 1), 31)
        self.schedule = schedule.sorted { $0.from < $1.from }
    }

    /// The user's cycle: the payday history saved for them, else the payday on their profile, else the 1st.
    static var current: PaydayCycle {
        let schedule = PaydaySetting.schedule
        guard !schedule.isEmpty else { return PaydayCycle(day: PaydaySetting.day ?? 1) }
        let today = Calendar.current.startOfDay(for: Date())
        let inForce = schedule.last { $0.from <= today } ?? schedule[0]
        return PaydayCycle(day: inForce.day, schedule: schedule)
    }

    /// A payday change that has not taken effect yet, if any.
    var pending: PaydayEntry? {
        let today = Calendar.current.startOfDay(for: Date())
        return schedule.last.flatMap { $0.from > today ? $0 : nil }
    }

    /// The period that contains `date`: start of its first day up to (not including) the next start.
    func period(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        let day = calendar.startOfDay(for: date)
        guard !schedule.isEmpty else { return naivePeriod(containing: day, payday: self.day, calendar: calendar) }
        let index = schedule.lastIndex { $0.from <= day } ?? 0
        let entry = schedule[index]
        let naive = naivePeriod(containing: day, payday: entry.day, calendar: calendar)
        // The first period under a new payday starts where the change takes effect; the one before
        // a pending change ends there. Either can be shorter or longer than a normal month.
        let start = index > 0 ? max(naive.start, entry.from) : naive.start
        var end = naive.end
        if index + 1 < schedule.count { end = min(end, schedule[index + 1].from) }
        return DateInterval(start: start, end: end)
    }

    /// The period `offset` periods away from the one containing `date` (-1 = the last one).
    func period(offset: Int, from date: Date = Date(), calendar: Calendar = .current) -> DateInterval {
        var period = period(containing: date, calendar: calendar)
        for _ in 0..<abs(offset) {
            let probe = offset < 0
                ? calendar.date(byAdding: .day, value: -1, to: period.start) ?? period.start
                : period.end
            period = self.period(containing: probe, calendar: calendar)
        }
        return period
    }

    private func naivePeriod(containing day: Date, payday: Int, calendar: Calendar) -> DateInterval {
        let thisMonth = self.payday(payday, inMonthOf: day, calendar: calendar)
        let start = thisMonth <= day
            ? thisMonth
            : self.payday(payday, inMonthOf: calendar.date(byAdding: .month, value: -1, to: day) ?? day, calendar: calendar)
        let end = self.payday(payday, inMonthOf: calendar.date(byAdding: .month, value: 1, to: start) ?? start, calendar: calendar)
        return DateInterval(start: start, end: end)
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

    private func payday(_ day: Int, inMonthOf date: Date, calendar: Calendar) -> Date {
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let length = calendar.range(of: .day, in: .month, for: first)?.count ?? 28
        return calendar.date(byAdding: .day, value: min(day, length) - 1, to: first) ?? first
    }
}

struct PaydayEntry: Codable, Equatable {
    let day: Int
    let from: Date
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

    private static let scheduleKey = "paydaySchedule"

    /// The payday history from `payday_changes`, mirrored for sync period math.
    static var schedule: [PaydayEntry] {
        get {
            UserDefaults.standard.data(forKey: scheduleKey)
                .flatMap { try? JSONDecoder().decode([PaydayEntry].self, from: $0) } ?? []
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: scheduleKey) }
    }
}

/// What Beranda's "Total saldo" adds up. The profile row is the source of truth (so it follows
/// the user across devices); `SupabaseSDK` mirrors it here and views read it with `@AppStorage`.
enum HomeBalanceMode: String, CaseIterable {
    case cash, all
}

enum HomeBalanceSetting {
    static let key = "homeBalanceMode"

    static var mode: String? {
        get { UserDefaults.standard.string(forKey: key) }
        set { UserDefaults.standard.set(newValue ?? HomeBalanceMode.cash.rawValue, forKey: key) }
    }
}
