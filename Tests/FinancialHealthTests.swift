import XCTest
@testable import SakuQ

@MainActor
final class FinancialHealthTests: XCTestCase {
    private func input(
        income: [Double] = [10_000_000, 10_000_000, 10_000_000],
        expense: [Double] = [7_000_000, 7_000_000, 7_000_000],
        liquid: Double = 50_000_000,
        debt: Double = 0, limit: Double = 0, hasCard: Bool = false,
        budget: Double = 5_000_000, spent: Double = 2_000_000, progress: Double = 0.5,
        activeDays: Int = 25
    ) -> FinancialHealth.Input {
        .init(monthlyIncome: income, monthlyExpense: expense, liquidBalance: liquid,
              creditDebt: debt, creditLimit: limit, hasCreditCard: hasCard,
              budgetTotal: budget, budgetSpent: spent, monthProgress: progress,
              activeDays: activeDays, topExpenseCategory: "Makan", hasTransactions: true)
    }

    private func points(_ health: FinancialHealth, _ kind: FinancialHealth.Kind) -> Int {
        health.factors.first { $0.kind == kind }!.points
    }

    func testHealthyUserScoresFullWithNoTips() {
        let health = FinancialHealth(input())
        XCTAssertEqual(health.score, 100)
        XCTAssertEqual(health.label, "Sehat")
        XCTAssertTrue(health.recommendations.isEmpty)
    }

    func testOverspendingAndNoSavingsGetTipsWorstFirst() {
        let health = FinancialHealth(input(expense: [12_000_000, 12_000_000, 12_000_000], liquid: 0,
                                           budget: 0, spent: 0))
        XCTAssertEqual(points(health, .cashflow), 0) // −20% savings rate
        XCTAssertEqual(points(health, .emergencyFund), 0)
        XCTAssertEqual(points(health, .budget), 0)
        XCTAssertEqual(health.weakest?.kind, .cashflow) // 30 points missing beats 25 and 15
        XCTAssertEqual(health.label, "Perlu perbaikan")
    }

    func testEmergencyFundAveragesOnlyActiveMonths() {
        // One active month of Rp5 jt spending; Rp20 jt covers 4 months, not 12.
        let health = FinancialHealth(input(income: [0, 0, 10_000_000], expense: [0, 0, 5_000_000], liquid: 20_000_000))
        XCTAssertEqual(points(health, .emergencyFund), 18)
    }

    func testCreditUseAgainstLimit() {
        XCTAssertEqual(points(FinancialHealth(input(debt: 500_000, limit: 10_000_000, hasCard: true)), .debt), 20)
        XCTAssertEqual(points(FinancialHealth(input(debt: 4_000_000, limit: 10_000_000, hasCard: true)), .debt), 8)
        XCTAssertEqual(points(FinancialHealth(input(debt: 9_000_000, limit: 10_000_000, hasCard: true)), .debt), 0)
    }

    func testBudgetPace() {
        XCTAssertEqual(points(FinancialHealth(input(spent: 2_500_000, progress: 0.5)), .budget), 15)
        XCTAssertEqual(points(FinancialHealth(input(spent: 3_500_000, progress: 0.5)), .budget), 0)
        XCTAssertEqual(points(FinancialHealth(input(spent: 6_000_000, progress: 0.9)), .budget), 0) // over budget
    }
}
