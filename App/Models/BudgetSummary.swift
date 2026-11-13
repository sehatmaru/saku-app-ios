import Foundation

/// The Budget tab's top block: every budget of the period added up and compared with how much of the period has passed.
struct BudgetSummary: Equatable {
    let total: Double
    let spent: Double
    /// Day of the period, 1 on payday, today counted.
    let dayNumber: Int
    let totalDays: Int

    /// Projection needs this many days of spending, or one big purchase makes it wild.
    static let projectionAfterDays = 7
    /// A gap smaller than this share of the total budget still counts as on pace.
    static let paceTolerance = 0.03

    enum Pace: Equatable {
        case onPace
        /// Spending is ahead of the calendar by this much.
        case fast(Double)
        /// Spending is behind the calendar by this much.
        case slow(Double)
        case over(Double)
    }

    var remaining: Double { total - spent }
    var timeShare: Double { totalDays > 0 ? min(Double(dayNumber) / Double(totalDays), 1) : 0 }
    var spentShare: Double { total > 0 ? spent / total : 0 }
    /// What a straight line through the period would have spent by today.
    var expectedSpent: Double { total * timeShare }
    var daysLeftIncludingToday: Int { max(totalDays - dayNumber + 1, 1) }

    var pace: Pace {
        if spent > total { return .over(spent - total) }
        let gap = spent - expectedSpent
        if gap > total * Self.paceTolerance { return .fast(gap) }
        if gap < -total * Self.paceTolerance { return .slow(-gap) }
        return .onPace
    }

    /// What is left to spend per remaining day, today counted; never negative.
    var perDayLeft: Double { max(remaining, 0) / Double(daysLeftIncludingToday) }
    var dailyAverage: Double { dayNumber > 0 ? spent / Double(dayNumber) : 0 }
    /// Spending at the end of the period if the daily average holds; nil while there is too little to go on.
    var projected: Double? { dayNumber >= Self.projectionAfterDays ? dailyAverage * Double(totalDays) : nil }

    /// Nil when there is nothing to sum.
    init?(budgets: [Budget], dayNumber: Int, totalDays: Int) {
        let total = budgets.reduce(0) { $0 + $1.amount }
        guard total > 0 else { return nil }
        self.total = total
        self.spent = budgets.reduce(0) { $0 + $1.spent }
        self.dayNumber = dayNumber
        self.totalDays = totalDays
    }

    /// Budgets at 80% or more, fullest first.
    static func needingAttention(_ budgets: [Budget], limit: Int = 3) -> [Budget] {
        Array(budgets.filter { $0.progress >= 0.8 }.sorted { $0.progress > $1.progress }.prefix(limit))
    }
}
