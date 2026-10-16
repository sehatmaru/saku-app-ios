import Foundation

enum SpendingStatus: Comparable {
    case normal
    case warning
    case overbudget
}

struct Budget: Identifiable, Codable {
    let id: String
    let categoryId: String
    let name: String
    var amount: Double
    let periodUnit: String
    let periodInterval: Int
    let startDate: String
    let endDate: String?
    let isActive: Bool
    var spent: Double = 0
    /// The temporary change in force this period, if any; `amount` is then its amount.
    var temporary: BudgetAmountChange?
    /// The budget's own amount, which the temporary change will hand back to.
    var baseAmount: Double?

    var remaining: Double { amount - spent }
    var progress: Double { amount > 0 ? spent / amount : 0 }

    /// Days in the current period; monthly budgets run from payday (see PaydayCycle).
    var daysInMonth: Int { PaydayCycle.current.days().total }

    /// Day number within the current period, 1 on payday.
    var currentDay: Int { daysInMonth - daysRemaining }

    var daysRemaining: Int { PaydayCycle.current.days().left }

    var idealDailyBudget: Double {
        amount / Double(daysInMonth)
    }

    var dailyRemaining: Double {
        daysRemaining > 0 ? remaining / Double(daysRemaining) : remaining
    }

    /// The budget's period in force now: start included, end excluded. Read locally so the Budget
    /// page never needs one HTTP call per budget just to know what was spent (BUG-31).
    func currentPeriod(calendar: Calendar = .current, now: Date = Date()) -> DateInterval? {
        switch periodUnit {
        case "month":
            let start = PaydayCycle.current.period(containing: now, calendar: calendar).start
            guard let later = calendar.date(byAdding: .month, value: periodInterval - 1, to: start) else { return nil }
            return DateInterval(start: start, end: PaydayCycle.current.period(containing: later, calendar: calendar).end)
        case "week":
            guard let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)),
                  let end = calendar.date(byAdding: .weekOfYear, value: periodInterval, to: start) else { return nil }
            return DateInterval(start: start, end: end)
        default:
            guard let start = ISO8601DateFormatter().date(from: startDate) else { return nil }
            let end = endDate.flatMap { ISO8601DateFormatter().date(from: $0) } ?? .distantFuture
            return DateInterval(start: start, end: end)
        }
    }

    /// Spent in this budget's category during its current period, from transactions already fetched
    /// on the device. Local on purpose (BUG-31): the old per-budget server call showed 0 when it failed.
    func spentInCurrentPeriod(transactions: [Transaction], calendar: Calendar = .current, now: Date = Date()) -> Double {
        guard let period = currentPeriod(calendar: calendar, now: now) else { return 0 }
        return transactions
            .filter { $0.type == .expense && $0.categoryId == categoryId && $0.date >= period.start && $0.date < period.end }
            .reduce(0) { $0 + $1.amount }
    }

    var spendingStatus: SpendingStatus {
        if spent >= amount { return .overbudget }
        guard daysRemaining > 0 else { return .normal }
        if dailyRemaining < idealDailyBudget * 0.5 { return .warning }
        return .normal
    }

    enum CodingKeys: String, CodingKey {
        case id, name, amount
        case categoryId = "category_id"
        case periodUnit = "period_unit"
        case periodInterval = "period_interval"
        case startDate = "start_date"
        case endDate = "end_date"
        case isActive = "is_active"
    }
}
