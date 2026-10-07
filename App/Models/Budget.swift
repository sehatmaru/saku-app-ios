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

    func currentPeriodStart() -> String {
        let calendar = Calendar.current
        let now = Date()
        let formatter = ISO8601DateFormatter()

        switch periodUnit {
        case "month":
            return formatter.string(from: PaydayCycle.current.period(containing: now, calendar: calendar).start)
        case "week":
            let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            return formatter.string(from: start)
        default:
            return startDate
        }
    }

    func currentPeriodEnd() -> String? {
        let calendar = Calendar.current
        let now = Date()
        let formatter = ISO8601DateFormatter()

        switch periodUnit {
        case "month":
            let start = PaydayCycle.current.period(containing: now, calendar: calendar).start
            guard let later = calendar.date(byAdding: .month, value: periodInterval - 1, to: start) else { return nil }
            return formatter.string(from: PaydayCycle.current.period(containing: later, calendar: calendar).end)
        case "week":
            guard let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)),
                  let next = calendar.date(byAdding: .weekOfYear, value: periodInterval, to: start) else { return nil }
            return formatter.string(from: next)
        default:
            return endDate
        }
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
