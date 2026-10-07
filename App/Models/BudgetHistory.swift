import Foundation

/// A budget as history needs it: including deleted ones, with the dates it was alive.
struct BudgetHistoryBudget: Decodable, Identifiable {
    let id: String
    let categoryId: String
    let amount: Double
    let isActive: Bool
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, amount
        case categoryId = "category_id"
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    /// When it stopped counting: deleted, or switched off (the last edit is the best date we have).
    var endedAt: Date? { deletedAt ?? (isActive ? nil : updatedAt) }
}

enum BudgetHistoryStatus {
    case safe, near, over

    init(spent: Double, amount: Double) {
        let progress = amount > 0 ? spent / amount : 0
        self = progress >= 1 ? .over : progress >= 0.8 ? .near : .safe
    }
}

struct BudgetHistoryRow: Identifiable {
    var id: String { budgetId }
    let budgetId: String
    let categoryId: String
    let amount: Double
    let spent: Double
    let source: ResolvedBudgetAmount.Source
    let isDeleted: Bool
    /// The expenses behind `spent`, newest first.
    let transactions: [Transaction]

    var status: BudgetHistoryStatus { .init(spent: spent, amount: amount) }
    var progress: Double { amount > 0 ? spent / amount : 0 }
}

struct BudgetHistoryPeriod: Identifiable {
    var id: Date { interval.start }
    let interval: DateInterval
    let rows: [BudgetHistoryRow]
    let income: Double
    let expense: Double

    var net: Double { income - expense }
    var totalBudget: Double { rows.reduce(0) { $0 + $1.amount } }
    var totalSpent: Double { rows.reduce(0) { $0 + $1.spent } }
    var progress: Double { totalBudget > 0 ? totalSpent / totalBudget : 0 }
    var status: BudgetHistoryStatus { .init(spent: totalSpent, amount: totalBudget) }
    var hasEstimate: Bool { rows.contains { $0.source == .estimate } }
}

enum BudgetHistory {
    /// One finished period, or nil when no budget was alive in it. A budget is alive in a period when
    /// it was created before the period ended and was not deleted (or switched off) before it began.
    /// Spent and Masuk/Keluar are computed from transactions, so edits to old ones show up here.
    static func period(_ interval: DateInterval, budgets: [BudgetHistoryBudget], changes: [BudgetAmountChange],
                       transactions: [Transaction], shownCategoryIds: Set<String>,
                       calendar: Calendar = .current) -> BudgetHistoryPeriod? {
        func inPeriod(_ tx: Transaction) -> Bool { tx.date >= interval.start && tx.date < interval.end }
        let rows: [BudgetHistoryRow] = budgets
            .filter { shownCategoryIds.contains($0.categoryId) }
            .filter { $0.createdAt < interval.end && ($0.endedAt.map { $0 > interval.start } ?? true) }
            .map { budget in
                let resolved = ResolvedBudgetAmount.resolve(
                    base: budget.amount, changes: changes.filter { $0.budgetId == budget.id },
                    periodStart: interval.start, calendar: calendar)
                let spent = transactions.filter { $0.type == .expense && $0.categoryId == budget.categoryId && inPeriod($0) }
                    .sorted { $0.date > $1.date }
                return BudgetHistoryRow(budgetId: budget.id, categoryId: budget.categoryId, amount: resolved.amount,
                                        spent: spent.reduce(0) { $0 + $1.amount }, source: resolved.source,
                                        isDeleted: budget.deletedAt.map { $0 <= interval.end } ?? false,
                                        transactions: spent)
            }
            .sorted { $0.progress > $1.progress }
        guard !rows.isEmpty else { return nil }
        // Same rule as the dashboard: only income and expense; transfers, card payments and corrections stay out.
        let flow = transactions.filter(inPeriod)
        return BudgetHistoryPeriod(
            interval: interval, rows: rows,
            income: flow.filter { $0.type == .income }.reduce(0) { $0 + $1.amount },
            expense: flow.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount })
    }

    /// Up to `count` finished periods that had a budget, newest first, scanning back from `offset`
    /// (-1 = the last finished period). `next` is where to continue; nil when there is nothing older.
    static func page(from offset: Int = -1, count: Int = 3, budgets: [BudgetHistoryBudget], changes: [BudgetAmountChange],
                     transactions: [Transaction], shownCategoryIds: Set<String>, cycle: PaydayCycle = .current,
                     now: Date = Date(), calendar: Calendar = .current) -> (periods: [BudgetHistoryPeriod], next: Int?) {
        guard let oldest = budgets.map(\.createdAt).min() else { return ([], nil) }
        var result: [BudgetHistoryPeriod] = []
        var index = offset
        // 120 periods is ten years of months: a stop for odd data, not a feature limit.
        while result.count < count, index >= -120 {
            let interval = cycle.period(offset: index, from: now, calendar: calendar)
            if interval.end <= oldest { return (result, nil) }
            if let period = period(interval, budgets: budgets, changes: changes, transactions: transactions,
                                   shownCategoryIds: shownCategoryIds, calendar: calendar) {
                result.append(period)
            }
            index -= 1
        }
        let next = index
        let more = index >= -120 && cycle.period(offset: next, from: now, calendar: calendar).end > oldest
        return (result, more ? next : nil)
    }
}
