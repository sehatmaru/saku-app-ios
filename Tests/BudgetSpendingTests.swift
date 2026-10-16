import XCTest
@testable import Saku

/// BUG-31: what was spent in a budget's current period is computed on the device from the
/// transactions already fetched, instead of one HTTP call per budget that failed silently to 0.
final class BudgetSpendingTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return c
    }()

    private func txn(_ id: String, type: Transaction.TransactionType = .expense, amount: Double, date: Date,
                     categoryId: String?) -> Transaction {
        Transaction(id: id, accountId: "bca", counterpartyAccountId: nil, categoryId: categoryId, amount: amount,
                    type: type, description: nil, note: nil, date: date, delta: nil)
    }

    private func monthBudget(_ categoryId: String = "kopi") -> Budget {
        Budget(id: "b1", categoryId: categoryId, name: "Kopi", amount: 500_000, periodUnit: "month",
               periodInterval: 1, startDate: "2026-01-01", endDate: nil, isActive: true, spent: 0,
               temporary: nil, baseAmount: nil)
    }

    /// Sums only this category, in the period in force now.
    func testSumsOnlyTheCategoryInTheCurrentPeriod() {
        let now = Date()
        let period = PaydayCycle.current.period(containing: now, calendar: calendar)
        let inside = calendar.date(byAdding: .hour, value: 2, to: period.start)!
        let before = calendar.date(byAdding: .day, value: -1, to: period.start)!

        let transactions = [
            txn("a", amount: 10_000, date: inside, categoryId: "kopi"),
            txn("b", amount: 15_000, date: inside, categoryId: "kopi"),
            txn("c", amount: 99_000, date: inside, categoryId: "lain"),
            txn("d", amount: 7_000, date: before, categoryId: "kopi"),
            txn("e", type: .income, amount: 3_000, date: inside, categoryId: "kopi"),
        ]

        XCTAssertEqual(monthBudget().spentInCurrentPeriod(transactions: transactions), 25_000)
    }

    /// The period's start day counts, the next period's first day doesn't.
    func testPeriodBoundaries() {
        let now = Date()
        let period = PaydayCycle.current.period(containing: now, calendar: calendar)
        let transactions = [
            txn("start", amount: 1_000, date: period.start, categoryId: "kopi"),
            txn("end", amount: 2_000, date: period.end, categoryId: "kopi"),
        ]

        XCTAssertEqual(monthBudget().spentInCurrentPeriod(transactions: transactions), 1_000)
    }

    func testNoTransactionsIsZero() {
        XCTAssertEqual(monthBudget().spentInCurrentPeriod(transactions: []), 0)
    }

    /// A weekly budget runs from the start of its own week, for as many weeks as it is set to.
    func testWeeklyBudgetUsesItsOwnWeek() {
        let now = Date()
        let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
        let inside = calendar.date(byAdding: .day, value: 1, to: start)!
        let before = calendar.date(byAdding: .day, value: -1, to: start)!
        let budget = Budget(id: "w1", categoryId: "kopi", name: "Kopi", amount: 200_000, periodUnit: "week",
                            periodInterval: 1, startDate: "2026-01-01", endDate: nil, isActive: true, spent: 0,
                            temporary: nil, baseAmount: nil)

        let transactions = [txn("a", amount: 12_000, date: inside, categoryId: "kopi"),
                            txn("b", amount: 30_000, date: before, categoryId: "kopi")]

        XCTAssertEqual(budget.spentInCurrentPeriod(transactions: transactions), 12_000)
    }
}
