import XCTest
@testable import Saku

final class BudgetAmountChangeTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { calendar.startOfDay(for: calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!) }

    private func change(_ kind: String, _ amount: Double, from: Date, to: Date? = nil, estimate: Bool = false, created: Date = .distantPast) -> BudgetAmountChange {
        BudgetAmountChange(budgetId: "b", kind: kind, amount: amount, effectiveFrom: from, effectiveTo: to, isEstimate: estimate, createdAt: created)
    }

    /// Base 1jt, temporary 5jt for 3 periods (Jan-Mar): periods 1-3 use 5jt, period 4 is back at 1jt.
    func testTemporaryThenBack() {
        let changes = [change("base", 1_000_000, from: day(1970, 1, 1)),
                       change("temporary", 5_000_000, from: day(2027, 1, 1), to: day(2027, 4, 1))]
        for m in 1...3 {
            XCTAssertEqual(ResolvedBudgetAmount.resolve(base: 1_000_000, changes: changes, periodStart: day(2027, m, 1), calendar: calendar).amount, 5_000_000)
        }
        let back = ResolvedBudgetAmount.resolve(base: 1_000_000, changes: changes, periodStart: day(2027, 4, 1), calendar: calendar)
        XCTAssertEqual(back.amount, 1_000_000)
        XCTAssertEqual(back.source, .base)
    }

    /// Changing the base later leaves earlier periods alone.
    func testBaseChangeDoesNotRewritePast() {
        let changes = [change("base", 1_000_000, from: day(1970, 1, 1)), change("base", 2_000_000, from: day(2027, 5, 1))]
        XCTAssertEqual(ResolvedBudgetAmount.resolve(base: 2_000_000, changes: changes, periodStart: day(2027, 4, 1), calendar: calendar).amount, 1_000_000)
        XCTAssertEqual(ResolvedBudgetAmount.resolve(base: 2_000_000, changes: changes, periodStart: day(2027, 5, 1), calendar: calendar).amount, 2_000_000)
    }

    /// Periods that began before the history existed are estimates.
    func testEstimateBeforeHistory() {
        let changes = [change("base", 1_000_000, from: day(1970, 1, 1), estimate: true, created: day(2026, 10, 7))]
        XCTAssertEqual(ResolvedBudgetAmount.resolve(base: 1_000_000, changes: changes, periodStart: day(2026, 9, 1), calendar: calendar).source, .estimate)
        XCTAssertEqual(ResolvedBudgetAmount.resolve(base: 1_000_000, changes: changes, periodStart: day(2026, 11, 1), calendar: calendar).source, .base)
    }
}
