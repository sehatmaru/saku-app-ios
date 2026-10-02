import XCTest
@testable import Saku

@MainActor
final class FinancialHealthTests: XCTestCase {
    override func setUp() {
        UserDefaults.standard.set("id", forKey: "appLanguage")
    }

    private func input(
        income: [Double] = [10_000_000, 10_000_000, 10_000_000],
        expense: [Double] = [7_000_000, 7_000_000, 7_000_000],
        liquid: Double = 50_000_000,
        debt: Double = 0, limit: Double = 0, hasCard: Bool = false,
        budget: Double = 5_000_000, spent: Double = 2_000_000, progress: Double = 0.5,
        activeDays: Int = 25,
        overdue: [FinancialHealth.OverdueBill] = []
    ) -> FinancialHealth.Input {
        .init(monthlyIncome: income, monthlyExpense: expense, liquidBalance: liquid,
              creditDebt: debt, creditLimit: limit, hasCreditCard: hasCard,
              budgetTotal: budget, budgetSpent: spent, monthProgress: progress,
              activeDays: activeDays, topExpenseCategory: "Makan", hasTransactions: true, overdueBills: overdue)
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

    private func debt(_ health: FinancialHealth) -> FinancialHealth.Factor { health.factors.first { $0.kind == .debt }! }

    func testHighUseButCashCoversTheBillScoresFullWithAGentleTip() {
        // 85% of the limit, cash (Rp50 jt) well above the card balance, nothing late.
        let health = FinancialHealth(input(liquid: 10_000_000, debt: 8_500_000, limit: 10_000_000, hasCard: true))
        XCTAssertEqual(points(health, .debt), 20)
        XCTAssertEqual(debt(health).tip, "Pemakaian kartu tinggi. Pastikan kas cukup untuk melunasi sebelum jatuh tempo.")
        XCTAssertTrue(debt(health).summary.contains("85%"))
        XCTAssertTrue(debt(health).summary.contains("kas cukup untuk melunasi"))
    }

    func testDebtScoreFollowsCoverageNotUse() {
        // Coverage = cash / card balance: >= 1 -> 20, 0.5..<1 -> 15, < 0.5 -> 8.
        XCTAssertEqual(points(FinancialHealth(input(liquid: 8_500_000, debt: 8_500_000, limit: 10_000_000, hasCard: true)), .debt), 20)
        XCTAssertEqual(points(FinancialHealth(input(liquid: 4_250_000, debt: 8_500_000, limit: 10_000_000, hasCard: true)), .debt), 15)
        let thin = FinancialHealth(input(liquid: 3_400_000, debt: 8_500_000, limit: 10_000_000, hasCard: true)) // 40%
        XCTAssertEqual(points(thin, .debt), 8)
        XCTAssertNotNil(debt(thin).tip) // 85% use still earns the tip
        // Light use never costs points or earns a tip.
        let light = FinancialHealth(input(liquid: 100_000, debt: 500_000, limit: 10_000_000, hasCard: true))
        XCTAssertEqual(points(light, .debt), 8)
        XCTAssertNil(debt(light).tip)
        // No card: full points.
        XCTAssertEqual(points(FinancialHealth(input()), .debt), 20)
    }

    func testOverdueBillCapsTheDebtFactor() {
        let week = FinancialHealth.OverdueBill(cardName: "BCA Visa", amount: 838_084, daysLate: 3)
        let late = FinancialHealth.OverdueBill(cardName: "BCA Visa", amount: 838_084, daysLate: 10)
        // Cash covers the card (20 on its own); up to a week late holds it to 8, later to 0.
        XCTAssertEqual(points(FinancialHealth(input(debt: 500_000, limit: 10_000_000, hasCard: true, overdue: [week])), .debt), 8)
        XCTAssertEqual(points(FinancialHealth(input(debt: 500_000, limit: 10_000_000, hasCard: true, overdue: [late])), .debt), 0)
        // The longest overdue bill decides.
        XCTAssertEqual(points(FinancialHealth(input(debt: 500_000, limit: 10_000_000, hasCard: true, overdue: [week, late])), .debt), 0)
        // Nothing overdue any more: back to full points, no tip.
        let paid = FinancialHealth(input(debt: 500_000, limit: 10_000_000, hasCard: true))
        XCTAssertEqual(points(paid, .debt), 20)
        XCTAssertNil(debt(paid).tip)
    }

    func testOverdueBillExplainsItselfAndBecomesTheTip() {
        let late = FinancialHealth.OverdueBill(cardName: "BCA Visa", amount: 838_084, daysLate: 10)
        let health = FinancialHealth(input(debt: 500_000, limit: 10_000_000, hasCard: true, overdue: [late]))
        XCTAssertTrue(debt(health).summary.contains("BCA Visa"))
        XCTAssertTrue(debt(health).summary.contains("10 hari"))
        XCTAssertNotNil(debt(health).tip)
        XCTAssertLessThan(health.score, 100)
    }

    func testBudgetPace() {
        XCTAssertEqual(points(FinancialHealth(input(spent: 2_500_000, progress: 0.5)), .budget), 15)
        XCTAssertEqual(points(FinancialHealth(input(spent: 3_500_000, progress: 0.5)), .budget), 0)
        XCTAssertEqual(points(FinancialHealth(input(spent: 6_000_000, progress: 0.9)), .budget), 0) // over budget
    }

    func testYoungAccountScoresOnlyTheFactorsWithEnoughData() {
        var young = input()
        young.daysOfData = 30
        let early = FinancialHealth(young)
        XCTAssertTrue(early.isAvailable)
        XCTAssertTrue(early.isPartial)
        XCTAssertEqual(early.factors.filter(\.isPending).map(\.kind), [.cashflow, .emergencyFund])
        // Debt 20/20, budget 15/15, habit 10/10 -> full marks out of the 45 that count.
        XCTAssertEqual(early.score, 100)
        XCTAssertTrue(early.recommendations.isEmpty)

        young.daysOfData = FinancialHealth.minDays
        let ready = FinancialHealth(young)
        XCTAssertFalse(ready.isPartial)
        XCTAssertEqual(points(ready, .cashflow), 30)
    }

    func testPendingFactorsDoNotDragTheScoreDown() {
        var young = input(budget: 5_000_000, spent: 6_000_000)   // over budget: 0/15
        young.daysOfData = 10
        let health = FinancialHealth(young)
        // (20 + 0 + 10) of 45 possible, not 30 of 100.
        XCTAssertEqual(health.score, 67)
    }

    func testYoungAccountIsProvisionalAndNeverRated() {
        var young = input()          // no card, budget on track, logged 25 days
        young.daysOfData = 20
        let health = FinancialHealth(young)
        XCTAssertTrue(health.isProvisional)
        XCTAssertFalse(health.isHealthy)
        XCTAssertNil(health.label)
        XCTAssertEqual(health.score, 100) // still computed, just not rated

        young.daysOfData = FinancialHealth.minDays
        let full = FinancialHealth(young)
        XCTAssertFalse(full.isProvisional)
        XCTAssertEqual(full.label, "Sehat")
    }

    // MARK: Payday cycle inputs

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private func tx(_ type: Transaction.TransactionType, _ amount: Double, on date: Date) -> Transaction {
        Transaction(id: UUID().uuidString, accountId: "a", counterpartyAccountId: nil, categoryId: "c",
                    amount: amount, type: type, description: nil, note: nil, date: date, delta: nil)
    }

    func testBudgetPaceFollowsThePaydayCycle() {
        // Payday 25, today 5 Oct: cycle 25 Sep - 24 Oct (30 days), 11th day -> 11/30, not 5/31.
        let progress = FinancialHealth.cycleProgress(PaydayCycle(day: 25), on: date(2026, 10, 5), calendar: calendar)
        XCTAssertEqual(progress, 11.0 / 30.0, accuracy: 0.0001)
        XCTAssertNotEqual(progress, 5.0 / 31.0, accuracy: 0.01)
        // Payday 1 is the calendar month.
        XCTAssertEqual(FinancialHealth.cycleProgress(PaydayCycle(day: 1), on: date(2026, 10, 5), calendar: calendar),
                       5.0 / 31.0, accuracy: 0.0001)
    }

    func testCashflowUsesFinishedCyclesNotTheRunningOne() {
        let history = [
            tx(.income, 10_000_000, on: date(2026, 9, 10)), tx(.expense, 4_000_000, on: date(2026, 9, 12)),
            tx(.income, 99_000_000, on: date(2026, 10, 1)), tx(.expense, 98_000_000, on: date(2026, 10, 2)),
        ]
        // Payday 1, today 2 Oct: September is the one finished cycle with data; October is left out.
        let flow = FinancialHealth.cashflowCycles(history, cycle: PaydayCycle(day: 1), now: date(2026, 10, 2), calendar: calendar)
        XCTAssertEqual(flow.income, [10_000_000])
        XCTAssertEqual(flow.expense, [4_000_000])
    }

    func testCashflowTakesThreeFinishedCyclesAndFallsBackToTheRunningOne() {
        let history = [
            tx(.income, 1, on: date(2026, 6, 10)), tx(.income, 2, on: date(2026, 7, 10)),
            tx(.income, 3, on: date(2026, 8, 10)), tx(.income, 4, on: date(2026, 9, 10)),
            tx(.income, 5, on: date(2026, 10, 3)),
        ]
        let three = FinancialHealth.cashflowCycles(history, cycle: PaydayCycle(day: 1), now: date(2026, 10, 5), calendar: calendar)
        XCTAssertEqual(three.income, [2, 3, 4]) // Jul, Aug, Sep, oldest first
        // Only the running cycle has data: use it rather than return nothing.
        let fresh = FinancialHealth.cashflowCycles([tx(.income, 7, on: date(2026, 10, 3))], cycle: PaydayCycle(day: 1),
                                                   now: date(2026, 10, 5), calendar: calendar)
        XCTAssertEqual(fresh.income, [7])
    }
}
