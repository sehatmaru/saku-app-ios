import Foundation

/// The numbers behind the Statistik page (Enhancement 1, Epic 8): one payday period, its calendar, the last five
/// periods, categories, wallets, weekday pattern, budgets and highlights. Worked out on the device from the
/// transactions already loaded. Pure, so every figure can be tested without drawing anything.
enum PeriodStatistics {
    // MARK: Pieces

    struct Summary {
        let income: Double
        let expense: Double
        var net: Double { income - expense }
        /// Net ÷ income; nil without income.
        let savingsRate: Double?
        let transactions: Int
        let perDay: Double
        /// Average amount of one expense; nil without any.
        let perTransaction: Double?
        /// Expense at the end of the period at the pace so far; nil when it would be a guess (first period) or the period is over.
        let projection: Double?
        let projectionNote: ProjectionNote
        /// What is left of the income after each day's spending, one value per elapsed day: the sparkline.
        let remaining: [Double]
    }

    enum ProjectionNote: Equatable {
        case fromAverage(Double)
        case needsHistory
        case finished
    }

    struct CalendarDay: Equatable {
        let day: Int
        /// nil for days still to come.
        let amount: Double?
        /// 0 = no spending, 1...4 by intensity.
        let level: Int
    }

    struct SpendingCalendar {
        /// Empty cells before the first day, with Monday first.
        let leadingBlanks: Int
        let days: [CalendarDay]
        let total: Double
        let peakDate: Date?
        let peakAmount: Double
        let zeroDays: Int
    }

    struct TrendPoint {
        let label: String
        let income: Double
        let expense: Double
        var net: Double { income - expense }
        /// The running period: its expense is the projection once there is one.
        let isCurrent: Bool
    }

    struct Trend {
        let points: [TrendPoint]
        /// Fractions against the period before; nil with a single period or nothing to divide by.
        let expenseChange: Double?
        let netChange: Double?
        let averageIncome: Double
        let averageExpense: Double
    }

    struct Slice {
        let name: String
        let amount: Double
        let share: Double
        /// Against the same stretch of the period before; nil when there is no earlier period to compare with.
        let change: Double?
    }

    struct WalletRow {
        let name: String
        let expense: Double
        let income: Double
        /// Share of the expense.
        let share: Double
        let transactions: Int
    }

    struct Weekday {
        /// 0 = Monday.
        let index: Int
        /// Average spent on that weekday over the elapsed days.
        let average: Double
    }

    struct TimePattern {
        let weekdays: [Weekday]
        let peak: Int?
        let topDays: [(date: Date, amount: Double)]
        /// Longest run of days without spending.
        let longestZeroStreak: Int
    }

    struct BudgetRow {
        let name: String
        let spent: Double
        let amount: Double
        var ratio: Double { amount > 0 ? spent / amount : 0 }
    }

    struct Comparison {
        let now: Double
        let previous: Double
        /// Fraction; nil when the earlier stretch had no spending.
        let change: Double?
        /// The stretch of the earlier period that is compared, e.g. "25 Agu – 20 Sep".
        let label: String
    }

    struct Highlights {
        let biggest: [(name: String, date: Date, amount: Double)]
        let frequent: (name: String, count: Int)?
        /// nil until one full period is on record.
        let comparison: Comparison?
    }

    struct Result {
        let interval: DateInterval
        let label: String
        let isCurrent: Bool
        /// Days of the period that have passed (all of them for a finished period).
        let elapsedDays: Int
        let totalDays: Int
        /// Nothing recorded in the period: the page says so instead of drawing empty charts.
        let isEmpty: Bool
        /// Less than one full period on record: no projection, no comparison.
        let isFirstPeriod: Bool
        let summary: Summary
        let calendar: SpendingCalendar
        let trend: Trend
        let expenseSlices: [Slice]
        let incomeSlices: [Slice]
        let wallets: [WalletRow]
        let mostUsedWallet: (name: String, count: Int)?
        let time: TimePattern
        let budgets: [BudgetRow]
        let budgetRemaining: Double
        let hasBudget: Bool
        let highlights: Highlights
    }

    // MARK: Build

    /// The most a donut shows before the rest becomes "Lainnya".
    static let expenseSliceLimit = 4
    static let incomeSliceLimit = 3
    static let walletLimit = 4
    static let trendPeriods = 5

    /// The calendar heat of a day among the days that had spending: quartiles of those days, so one huge day does not
    /// flatten all the others into the palest shade. Level 4 is the top quarter, 1 the bottom quarter; a day without
    /// spending is 0. When every spending day is the same, they all get the middle shade.
    private static func heatLevels(for amounts: [Double]) -> (Double) -> Int {
        let sorted = amounts.filter { $0 > 0 }.sorted()
        guard let low = sorted.first, let high = sorted.last else { return { _ in 0 } }
        if low == high { return { $0 > 0 ? 3 : 0 } }
        func quantile(_ p: Double) -> Double { sorted[max(Int((p * Double(sorted.count)).rounded(.up)) - 1, 0)] }
        let q1 = quantile(0.25), q2 = quantile(0.5), q3 = quantile(0.75)
        return { $0 <= 0 ? 0 : $0 > q3 ? 4 : $0 > q2 ? 3 : $0 > q1 ? 2 : 1 }
    }

    private static func change(_ now: Double, _ previous: Double) -> Double? {
        previous > 0 ? (now - previous) / previous : nil
    }

    /// `interval` is the payday period shown; `budgetLines` are that period's budgets as they stood then.
    static func make(transactions: [Transaction], categories: [Category], accounts: [Account], budgetLines: [ReportModel.BudgetLine],
                     cycle: PaydayCycle, interval: DateInterval, now: Date = Date(), calendar: Calendar = .current) -> Result {
        let counted = transactions.filter { $0.type == .income || $0.type == .expense }
        let first = counted.map(\.date).min()
        let categoryNames = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let walletNames = Dictionary(accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        func categoryName(_ txn: Transaction) -> String { txn.categoryId.flatMap { categoryNames[$0] } ?? L("Tanpa kategori") }
        func inside(_ range: DateInterval) -> [Transaction] { counted.filter { $0.date >= range.start && $0.date < range.end } }

        let startOfPeriod = calendar.startOfDay(for: interval.start)
        let totalDays = max(calendar.dateComponents([.day], from: startOfPeriod, to: interval.end).day ?? 30, 1)
        let isCurrent = interval.contains(now)
        let elapsed = isCurrent
            ? min(max((calendar.dateComponents([.day], from: startOfPeriod, to: calendar.startOfDay(for: now)).day ?? 0) + 1, 1), totalDays)
            : totalDays
        let rows = inside(interval)
        let expenses = rows.filter { $0.type == .expense }
        let incomes = rows.filter { $0.type == .income }
        let income = incomes.reduce(0) { $0 + $1.amount }
        let expense = expenses.reduce(0) { $0 + $1.amount }
        // A period that starts before any record has nothing earlier to compare with.
        let isFirstPeriod = first.map { $0 >= interval.start } ?? true

        // The same stretch of the period before, for fair comparisons while this one is still running.
        let before = cycle.period(offset: -1, from: interval.start, calendar: calendar)
        let comparable: DateInterval = {
            guard isCurrent, let end = calendar.date(byAdding: .day, value: elapsed, to: before.start) else { return before }
            return DateInterval(start: before.start, end: min(end, before.end))
        }()
        let earlier = inside(comparable)

        // Per day
        var daily = [Double](repeating: 0, count: totalDays)
        for txn in expenses {
            let index = calendar.dateComponents([.day], from: startOfPeriod, to: calendar.startOfDay(for: txn.date)).day ?? 0
            if daily.indices.contains(index) { daily[index] += txn.amount }
        }
        let spent = Array(daily.prefix(elapsed))
        var running = 0.0
        let remaining = spent.map { running += $0; return income - running }
        let perDay = expense / Double(elapsed)
        let projection: Double? = isCurrent && !isFirstPeriod ? perDay * Double(totalDays) : nil
        let summary = Summary(
            income: income, expense: expense, savingsRate: income > 0 ? (income - expense) / income : nil,
            transactions: rows.count, perDay: perDay, perTransaction: expenses.isEmpty ? nil : expense / Double(expenses.count),
            projection: projection,
            projectionNote: !isCurrent ? .finished : isFirstPeriod ? .needsHistory : .fromAverage(perDay), remaining: remaining)

        // Calendar
        let weekday = calendar.component(.weekday, from: startOfPeriod)
        let peak = spent.max() ?? 0
        let peakIndex = spent.firstIndex(of: peak)
        let heat = heatLevels(for: spent)
        let cells = (0..<totalDays).map { index -> CalendarDay in
            let day = calendar.component(.day, from: calendar.date(byAdding: .day, value: index, to: startOfPeriod) ?? startOfPeriod)
            return index < elapsed ? CalendarDay(day: day, amount: daily[index], level: heat(daily[index]))
                                   : CalendarDay(day: day, amount: nil, level: 0)
        }
        let spendingCalendar = SpendingCalendar(
            leadingBlanks: (weekday + 5) % 7, days: cells, total: expense,
            peakDate: peak > 0 ? peakIndex.flatMap { calendar.date(byAdding: .day, value: $0, to: startOfPeriod) } : nil,
            peakAmount: peak, zeroDays: spent.filter { $0 == 0 }.count)

        // Trend: the periods up to this one that could hold records
        let monthFormat = DateFormatter()
        monthFormat.locale = AppLanguage.locale
        monthFormat.dateFormat = "MMM"
        let periods = (0..<trendPeriods).reversed().map { cycle.period(offset: -$0, from: interval.start, calendar: calendar) }
            .filter { period in first.map { $0 < period.end } ?? false }
        let points = periods.map { period -> TrendPoint in
            let current = period.contains(interval.start)
            let range = inside(period)
            let periodExpense = range.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
            return TrendPoint(label: monthFormat.string(from: period.start),
                              income: range.filter { $0.type == .income }.reduce(0) { $0 + $1.amount },
                              expense: current ? (projection ?? periodExpense) : periodExpense, isCurrent: current && isCurrent)
        }
        let trend = Trend(
            points: points,
            expenseChange: points.count > 1 ? change(points[points.count - 1].expense, points[points.count - 2].expense) : nil,
            netChange: points.count > 1 ? change(points[points.count - 1].net, points[points.count - 2].net) : nil,
            averageIncome: points.isEmpty ? 0 : points.reduce(0) { $0 + $1.income } / Double(points.count),
            averageExpense: points.isEmpty ? 0 : points.reduce(0) { $0 + $1.expense } / Double(points.count))

        // Categories
        func slices(_ list: [Transaction], limit: Int, against previous: [Transaction]) -> [Slice] {
            var totals: [String: Double] = [:], before: [String: Double] = [:]
            for txn in list { totals[categoryName(txn), default: 0] += txn.amount }
            for txn in previous where txn.type == list.first?.type { before[categoryName(txn), default: 0] += txn.amount }
            let sum = totals.values.reduce(0, +)
            let sorted = totals.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            func slice(_ name: String, _ amount: Double, _ previousAmount: Double?) -> Slice {
                Slice(name: name, amount: amount, share: sum > 0 ? amount / sum : 0,
                      change: isFirstPeriod ? nil : previousAmount.flatMap { change(amount, $0) })
            }
            var result = sorted.prefix(limit).map { slice($0.key, $0.value, before[$0.key]) }
            if sorted.count > limit {
                let rest = sorted.dropFirst(limit)
                result.append(slice(L("Lainnya"), rest.reduce(0) { $0 + $1.value }, rest.reduce(0) { $0 + (before[$1.key] ?? 0) }))
            }
            return result
        }
        let expenseSlices = slices(expenses, limit: expenseSliceLimit, against: earlier)
        let incomeSlices = slices(incomes, limit: incomeSliceLimit, against: earlier)

        // Wallets
        var walletTotals: [String: (expense: Double, income: Double, count: Int)] = [:]
        for txn in rows {
            var entry = walletTotals[txn.accountId] ?? (0, 0, 0)
            if txn.type == .expense { entry.expense += txn.amount } else { entry.income += txn.amount }
            entry.count += 1
            walletTotals[txn.accountId] = entry
        }
        let walletSorted = walletTotals.map { (id: $0.key, value: $0.value) }.sorted { a, b in
            if a.value.expense != b.value.expense { return a.value.expense > b.value.expense }
            if a.value.income != b.value.income { return a.value.income > b.value.income }
            return a.id < b.id
        }
        func walletRow(_ name: String, _ value: (expense: Double, income: Double, count: Int)) -> WalletRow {
            WalletRow(name: name, expense: value.expense, income: value.income, share: expense > 0 ? value.expense / expense : 0, transactions: value.count)
        }
        var wallets = walletSorted.prefix(walletLimit).map { walletRow(walletNames[$0.id] ?? L("Dompet"), $0.value) }
        if walletSorted.count > walletLimit {
            let rest = walletSorted.dropFirst(walletLimit)
            wallets.append(walletRow(L("Lainnya"), (rest.reduce(0) { $0 + $1.value.expense }, rest.reduce(0) { $0 + $1.value.income },
                                                    rest.reduce(0) { $0 + $1.value.count })))
        }
        let mostUsed = walletTotals.max { $0.value.count != $1.value.count ? $0.value.count < $1.value.count : $0.key > $1.key }
            .map { (name: walletNames[$0.key] ?? L("Dompet"), count: $0.value.count) }

        // Weekday pattern
        var weekdayTotals = [Double](repeating: 0, count: 7), weekdayDays = [Int](repeating: 0, count: 7)
        for index in 0..<elapsed {
            let slot = (weekday + 5 + index) % 7
            weekdayTotals[slot] += daily[index]
            weekdayDays[slot] += 1
        }
        let weekdays = (0..<7).map { Weekday(index: $0, average: weekdayDays[$0] > 0 ? weekdayTotals[$0] / Double(weekdayDays[$0]) : 0) }
        let topAverage = weekdays.map(\.average).max() ?? 0
        var streak = 0, run = 0
        for amount in spent { run = amount == 0 ? run + 1 : 0; streak = max(streak, run) }
        let topDays = spent.enumerated().filter { $0.element > 0 }.sorted { $0.element != $1.element ? $0.element > $1.element : $0.offset < $1.offset }
            .prefix(3).map { (date: calendar.date(byAdding: .day, value: $0.offset, to: startOfPeriod) ?? startOfPeriod, amount: $0.element) }
        let time = TimePattern(weekdays: weekdays, peak: topAverage > 0 ? weekdays.firstIndex { $0.average == topAverage } : nil,
                               topDays: Array(topDays), longestZeroStreak: streak)

        // Budgets
        let budgetRows = budgetLines.map { BudgetRow(name: $0.name, spent: $0.spent, amount: $0.amount) }
        let topBudgets = budgetRows.sorted { $0.ratio != $1.ratio ? $0.ratio > $1.ratio : $0.name < $1.name }.prefix(3)

        // Highlights
        func title(_ txn: Transaction) -> String {
            [txn.description, txn.note].compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? categoryName(txn)
        }
        let biggest = expenses.sorted { $0.amount != $1.amount ? $0.amount > $1.amount : $0.date < $1.date }.prefix(5)
            .map { (name: title($0), date: $0.date, amount: $0.amount) }
        var categoryCounts: [String: Int] = [:]
        for txn in expenses { categoryCounts[categoryName(txn), default: 0] += 1 }
        let frequent = categoryCounts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }.map { (name: $0.key, count: $0.value) }
        let earlierSpend = earlier.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
        let comparison: Comparison? = isFirstPeriod ? nil : Comparison(
            now: expense, previous: earlierSpend, change: change(expense, earlierSpend), label: label(for: comparable, calendar: calendar))

        return Result(
            interval: interval, label: cycle.label(for: interval.start, calendar: calendar), isCurrent: isCurrent, elapsedDays: elapsed,
            totalDays: totalDays, isEmpty: rows.isEmpty, isFirstPeriod: isFirstPeriod, summary: summary, calendar: spendingCalendar,
            trend: trend, expenseSlices: expenseSlices, incomeSlices: incomeSlices, wallets: wallets, mostUsedWallet: mostUsed, time: time,
            budgets: Array(topBudgets), budgetRemaining: max(0, budgetRows.reduce(0) { $0 + $1.amount } - budgetRows.reduce(0) { $0 + $1.spent }),
            hasBudget: !budgetRows.isEmpty,
            highlights: Highlights(biggest: Array(biggest), frequent: frequent, comparison: comparison))
    }

    /// "25 Agu – 20 Sep" for a stretch whose end is exclusive.
    private static func label(for range: DateInterval, calendar: Calendar) -> String {
        let format = DateFormatter()
        format.locale = AppLanguage.locale
        format.calendar = calendar
        format.dateFormat = "d MMM"
        let last = calendar.date(byAdding: .day, value: -1, to: range.end) ?? range.end
        return format.string(from: range.start) + " – " + format.string(from: last)
    }
}
