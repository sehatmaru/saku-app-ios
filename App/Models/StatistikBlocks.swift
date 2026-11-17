import Foundation

/// A stretch of time one Statistik block can show, or be compared with.
struct StatPeriod: Identifiable, Hashable {
    let id: String
    let title: String
    let interval: DateInterval
}

/// The numbers behind the blocks of the Statistik page. Every block has its own period and, if the user wants, one
/// other period to compare with, so each function takes the stretch it is asked about. Pure, so it can be tested.
enum StatistikBlocks {
    // MARK: Periods

    /// What the first chip of a block offers: payday periods, never calendar months.
    static func periods(now: Date = Date(), cycle: PaydayCycle, calendar: Calendar = .current) -> [StatPeriod] {
        func period(_ offset: Int) -> DateInterval { cycle.period(offset: offset, from: now, calendar: calendar) }
        let current = period(0)
        func span(_ count: Int) -> DateInterval { DateInterval(start: period(1 - count).start, end: current.end) }
        return [
            StatPeriod(id: "p0", title: L("Periode ini"), interval: current),
            StatPeriod(id: "p1", title: L("Periode lalu"), interval: period(-1)),
            StatPeriod(id: "p3", title: L("3 periode terakhir"), interval: span(3)),
            StatPeriod(id: "p6", title: L("6 periode terakhir"), interval: span(6)),
        ]
    }

    /// Single payday periods only: this one, the last one, then each earlier one back to the first record.
    static func singles(now: Date = Date(), cycle: PaydayCycle, firstRecord: Date?, calendar: Calendar = .current) -> [StatPeriod] {
        let head = periods(now: now, cycle: cycle, calendar: calendar).filter { $0.id == "p0" || $0.id == "p1" }
        return head + olderPeriods(now: now, cycle: cycle, firstRecord: firstRecord, calendar: calendar)
    }

    /// Each period from two back on, named by its dates.
    static func olderPeriods(now: Date = Date(), cycle: PaydayCycle, firstRecord: Date?, calendar: Calendar = .current) -> [StatPeriod] {
        var list: [StatPeriod] = []
        for back in 2...12 {
            let range = cycle.period(offset: -back, from: now, calendar: calendar)
            if let firstRecord, range.end <= firstRecord { break }
            list.append(StatPeriod(id: "pp\(back)", title: rangeTitle(range, calendar: calendar), interval: range))
        }
        return list
    }

    /// "30 Sep – 29 Okt".
    static func rangeTitle(_ range: DateInterval, calendar: Calendar = .current) -> String {
        let format = DateFormatter()
        format.locale = AppLanguage.locale
        format.dateFormat = "d MMM"
        let last = calendar.date(byAdding: .day, value: -1, to: range.end) ?? range.end
        return format.string(from: range.start) + " – " + format.string(from: last)
    }

    /// What the "Bandingkan" sheet offers: the same choices, then single periods back to the first record.
    static func compareOptions(now: Date = Date(), cycle: PaydayCycle, firstRecord: Date?, excluding id: String,
                               calendar: Calendar = .current) -> [StatPeriod] {
        var list = periods(now: now, cycle: cycle, calendar: calendar).filter { $0.id != id }
        for back in 2...12 {
            let range = cycle.period(offset: -back, from: now, calendar: calendar)
            if let firstRecord, range.end <= firstRecord { break }
            let item = StatPeriod(id: "pp\(back)", title: rangeTitle(range, calendar: calendar), interval: range)
            if item.id != id { list.append(item) }
        }
        return list
    }

    /// The comparison stretch cut to the same number of days as the running period, so a half month is not set
    /// against a whole one. A finished main period leaves it whole.
    static func comparable(_ other: DateInterval, to main: DateInterval, now: Date = Date(), calendar: Calendar = .current) -> DateInterval {
        guard main.contains(now) else { return other }
        let days = (calendar.dateComponents([.day], from: calendar.startOfDay(for: main.start), to: calendar.startOfDay(for: now)).day ?? 0) + 1
        guard let end = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: other.start)) else { return other }
        return DateInterval(start: other.start, end: min(end, other.end))
    }

    private static func monthStart(_ date: Date, _ calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    // MARK: Totals

    static func rows(_ transactions: [Transaction], in range: DateInterval, type: Transaction.TransactionType) -> [Transaction] {
        transactions.filter { $0.type == type && $0.date >= range.start && $0.date < range.end }
    }

    static func flow(_ transactions: [Transaction], in range: DateInterval) -> (income: Double, expense: Double) {
        (rows(transactions, in: range, type: .income).reduce(0) { $0 + $1.amount },
         rows(transactions, in: range, type: .expense).reduce(0) { $0 + $1.amount })
    }

    /// Fraction against `previous`; nil when there is nothing to divide by.
    static func change(_ now: Double, _ previous: Double) -> Double? { previous > 0 ? (now - previous) / previous : nil }

    /// Biggest first; records of one name are added together.
    static func byCategory(_ transactions: [Transaction], categories: [Category], type: Transaction.TransactionType, in range: DateInterval) -> [(name: String, amount: Double)] {
        let names = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        var totals: [String: Double] = [:]
        for txn in rows(transactions, in: range, type: type) {
            totals[txn.categoryId.flatMap { names[$0] } ?? L("Tanpa kategori"), default: 0] += txn.amount
        }
        return totals.map { (name: $0.key, amount: $0.value) }.sorted { $0.amount > $1.amount }
    }

    static func byWallet(_ transactions: [Transaction], accounts: [Account], in range: DateInterval) -> [(name: String, amount: Double)] {
        let names = Dictionary(accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        var totals: [String: Double] = [:]
        for txn in rows(transactions, in: range, type: .expense) {
            totals[names[txn.accountId] ?? L("Tanpa dompet"), default: 0] += txn.amount
        }
        return totals.map { (name: $0.key, amount: $0.value) }.sorted { $0.amount > $1.amount }
    }

    // MARK: Per day

    /// Spending of each day of the stretch, one value per day.
    static func daily(_ transactions: [Transaction], in range: DateInterval, calendar: Calendar = .current) -> [Double] {
        let start = calendar.startOfDay(for: range.start)
        let count = max(calendar.dateComponents([.day], from: start, to: range.end).day ?? 0, 0)
        var days = [Double](repeating: 0, count: count)
        for txn in rows(transactions, in: range, type: .expense) {
            let index = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: txn.date)).day ?? 0
            if days.indices.contains(index) { days[index] += txn.amount }
        }
        return days
    }

    /// Running total of the daily spending; `through` cuts it to the days that have passed.
    static func cumulative(_ daily: [Double], through: Int? = nil) -> [Double] {
        var sum = 0.0
        return daily.prefix(through ?? daily.count).map { sum += $0; return sum }
    }

    /// Days of the stretch that have passed by `now` (all of them for a finished one).
    static func elapsedDays(_ range: DateInterval, now: Date = Date(), calendar: Calendar = .current) -> Int {
        let total = max(calendar.dateComponents([.day], from: calendar.startOfDay(for: range.start), to: range.end).day ?? 0, 0)
        guard range.contains(now) else { return range.end <= now ? total : 0 }
        return min((calendar.dateComponents([.day], from: calendar.startOfDay(for: range.start), to: calendar.startOfDay(for: now)).day ?? 0) + 1, total)
    }

    /// Average spending of each weekday (Monday first) over the days that have passed.
    static func weekdayAverages(_ daily: [Double], start: Date, calendar: Calendar = .current) -> [Double] {
        var sums = [Double](repeating: 0, count: 7), counts = [Int](repeating: 0, count: 7)
        let first = calendar.startOfDay(for: start)
        for (index, amount) in daily.enumerated() {
            guard let date = calendar.date(byAdding: .day, value: index, to: first) else { continue }
            let weekday = (calendar.component(.weekday, from: date) + 5) % 7
            sums[weekday] += amount
            counts[weekday] += 1
        }
        return (0..<7).map { counts[$0] > 0 ? sums[$0] / Double(counts[$0]) : 0 }
    }

    // MARK: Assets

    /// What the wallets held at the end of `date`: the last day on record up to it; nil before the first record.
    static func wealth(on date: Date, history: WealthHistory, calendar: Calendar = .current) -> (total: Double, invested: Double)? {
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        guard let point = history.points.last(where: { $0.date < end }) else { return nil }
        return (point.total, point.invested)
    }

    /// The dates the "Berapa hartaku?" chip offers: today and the last day of each earlier payday period.
    static func assetDates(now: Date = Date(), cycle: PaydayCycle, firstRecord: Date?, calendar: Calendar = .current) -> [StatPeriod] {
        let format = DateFormatter()
        format.locale = AppLanguage.locale
        format.dateFormat = "d MMM yyyy"
        let today = calendar.startOfDay(for: now)
        var list = [StatPeriod(id: "today", title: L("Per hari ini"), interval: DateInterval(start: today, duration: 0))]
        for back in 1...12 {
            let range = cycle.period(offset: -back, from: now, calendar: calendar)
            guard let end = calendar.date(byAdding: .day, value: -1, to: range.end) else { continue }
            if let firstRecord, end < firstRecord { break }
            list.append(StatPeriod(id: "end\(back)", title: format.string(from: end), interval: DateInterval(start: end, duration: 0)))
        }
        return list
    }
}
