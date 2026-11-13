import XCTest
@testable import Saku

final class BudgetSummaryTests: XCTestCase {
    private func budget(_ amount: Double, spent: Double) -> Budget {
        Budget(id: UUID().uuidString, categoryId: "c", name: "x", amount: amount, periodUnit: "month", periodInterval: 1,
               startDate: "2026-01-01", endDate: nil, isActive: true, spent: spent, temporary: nil, baseAmount: nil)
    }

    private func summary(spent: Double, day: Int, days: Int = 30, total: Double = 3_000_000) -> BudgetSummary {
        BudgetSummary(budgets: [budget(total / 2, spent: spent / 2), budget(total / 2, spent: spent / 2)], dayNumber: day, totalDays: days)!
    }

    func testSumsAllBudgets() {
        let s = summary(spent: 1_000_000, day: 10)
        XCTAssertEqual(s.total, 3_000_000)
        XCTAssertEqual(s.spent, 1_000_000)
        XCTAssertEqual(s.remaining, 2_000_000)
    }

    func testNoBudgetsNoSummary() {
        XCTAssertNil(BudgetSummary(budgets: [], dayNumber: 3, totalDays: 30))
    }

    func testPaceFastSlowAndOnPace() {
        XCTAssertEqual(summary(spent: 1_500_000, day: 15).pace, .onPace)
        XCTAssertEqual(summary(spent: 1_800_000, day: 15).pace, .fast(300_000))
        XCTAssertEqual(summary(spent: 1_200_000, day: 15).pace, .slow(300_000))
        XCTAssertEqual(summary(spent: 1_540_000, day: 15).pace, .onPace, "inside the 3% tolerance")
    }

    func testOverBudget() {
        XCTAssertEqual(summary(spent: 3_200_000, day: 20).pace, .over(200_000))
    }

    func testPerDayLeftCountsTodayAndNeverGoesNegative() {
        XCTAssertEqual(summary(spent: 1_500_000, day: 21).perDayLeft, 1_500_000 / 10)
        XCTAssertEqual(summary(spent: 3_500_000, day: 21).perDayLeft, 0)
    }

    func testProjectionWaitsSevenDays() {
        XCTAssertNil(summary(spent: 500_000, day: 6).projected)
        XCTAssertEqual(summary(spent: 700_000, day: 7).projected!, 3_000_000, accuracy: 1)
    }

    func testAttentionIsFullestFirstAndCapped() {
        let list = [budget(100, spent: 50), budget(100, spent: 95), budget(100, spent: 120), budget(100, spent: 80), budget(100, spent: 85)]
        XCTAssertEqual(BudgetSummary.needingAttention(list).map(\.progress), [1.2, 0.95, 0.85])
    }
}
