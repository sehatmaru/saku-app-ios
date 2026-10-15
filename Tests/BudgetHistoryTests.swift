import XCTest
@testable import Saku

final class BudgetHistoryTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { calendar.startOfDay(for: calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!) }

    private func budget(_ id: String, created: Date, deleted: Date? = nil) -> BudgetHistoryBudget {
        BudgetHistoryBudget(id: id, categoryId: "c\(id)", amount: 1_000_000, isActive: true,
                            createdAt: created, updatedAt: created, deletedAt: deleted)
    }

    private func tx(_ type: Transaction.TransactionType, _ amount: Double, on date: Date, category: String? = nil) -> Transaction {
        Transaction(id: UUID().uuidString, accountId: "a", counterpartyAccountId: nil, categoryId: category,
                    amount: amount, type: type, description: nil, note: nil, date: date, delta: nil)
    }

    /// Five monthly periods back from Okt 2026; three per page, newest first, then "older" continues.
    func testPaginationAndDeletedBudgetStaysVisible() {
        let budgets = [budget("1", created: day(2026, 1, 1)), budget("2", created: day(2026, 1, 1), deleted: day(2026, 8, 15))]
        let shown: Set<String> = ["c1", "c2"]
        let now = day(2026, 10, 7)
        let first = BudgetHistory.page(budgets: budgets, changes: [], transactions: [], shownCategoryIds: shown,
                                       cycle: PaydayCycle(day: 1), now: now, calendar: calendar)
        XCTAssertEqual(first.periods.map { $0.interval.start }, [day(2026, 9, 1), day(2026, 8, 1), day(2026, 7, 1)])
        XCTAssertEqual(first.periods[1].rows.count, 2, "deleted mid-August: still in August")
        XCTAssertEqual(first.periods[0].rows.count, 1, "gone in September")
        let more = BudgetHistory.page(from: first.next!, budgets: budgets, changes: [], transactions: [], shownCategoryIds: shown,
                                      cycle: PaydayCycle(day: 1), now: now, calendar: calendar)
        XCTAssertEqual(more.periods.first?.interval.start, day(2026, 6, 1))
    }

    /// Spent follows transactions; Net counts income and expense only.
    func testSpentAndNet() {
        let budgets = [budget("1", created: day(2026, 1, 1))]
        let txs = [tx(.expense, 300_000, on: day(2026, 9, 10), category: "c1"), tx(.income, 5_000_000, on: day(2026, 9, 25)),
                   tx(.transfer, 700_000, on: day(2026, 9, 12)), tx(.expense, 100_000, on: day(2026, 9, 12), category: "other")]
        let p = BudgetHistory.period(DateInterval(start: day(2026, 9, 1), end: day(2026, 10, 1)), budgets: budgets, changes: [],
                                     transactions: txs, shownCategoryIds: ["c1"], calendar: calendar)!
        XCTAssertEqual(p.totalSpent, 300_000)
        XCTAssertEqual(p.income, 5_000_000)
        XCTAssertEqual(p.expense, 400_000)
        XCTAssertEqual(p.net, 4_600_000)
        XCTAssertEqual(p.rows[0].transactions.count, 1)
    }

    func testNoBudgetNoPeriod() {
        XCTAssertNil(BudgetHistory.period(DateInterval(start: day(2025, 1, 1), end: day(2025, 2, 1)),
                                          budgets: [budget("1", created: day(2026, 1, 1))], changes: [], transactions: [],
                                          shownCategoryIds: ["c1"], calendar: calendar))
    }

    /// A budget made after the user's first transaction, from before history existed, still shows earlier periods as estimates.
    func testBudgetBornBeforeHistoryShowsEarlierPeriods() {
        let b = budget("1", created: day(2026, 10, 1))
        let changes = [BudgetAmountChange(budgetId: "1", kind: "base", amount: 1_000_000, effectiveFrom: day(1970, 1, 1),
                                          isEstimate: true, createdAt: day(2026, 10, 7))]
        let txs = [tx(.expense, 50_000, on: day(2026, 8, 20), category: "c1")]
        let page = BudgetHistory.page(budgets: [b], changes: changes, transactions: txs, shownCategoryIds: ["c1"],
                                      cycle: PaydayCycle(day: 1), now: day(2026, 10, 7), calendar: calendar)
        XCTAssertEqual(page.periods.map { $0.interval.start }, [day(2026, 9, 1), day(2026, 8, 1)])
        XCTAssertTrue(page.periods.allSatisfy { $0.hasEstimate })
        XCTAssertEqual(page.periods[1].totalSpent, 50_000)
    }
}
