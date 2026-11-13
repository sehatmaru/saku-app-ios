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
        overdue: [FinancialHealth.OverdueBill] = [],
        total: Double? = nil, safe: Double? = 50_000_000, daysLeft: Int = 15
    ) -> FinancialHealth.Input {
        .init(monthlyIncome: income, monthlyExpense: expense, liquidBalance: liquid,
              creditDebt: debt, creditLimit: limit, hasCreditCard: hasCard,
              budgetTotal: budget, budgetSpent: spent, monthProgress: progress,
              topExpenseCategory: "Makan", hasTransactions: true, overdueBills: overdue,
              totalBalance: total, safeToSpend: safe, daysLeft: daysLeft)
    }

    private func factor(_ health: FinancialHealth, _ kind: FinancialHealth.Kind) -> FinancialHealth.Factor? {
        health.factors.first { $0.kind == kind }
    }

    private func points(_ health: FinancialHealth, _ kind: FinancialHealth.Kind) -> Int {
        factor(health, kind)!.points
    }

    func testHealthyUserScoresFullWithNoTips() {
        let health = FinancialHealth(input())
        XCTAssertEqual(health.score, 100)
        XCTAssertEqual(health.label, "Sehat")
        XCTAssertTrue(health.recommendations.isEmpty)
        // No credit card: that factor is not there, and the score still runs on a 100 scale.
        XCTAssertNil(factor(health, .debt))
        XCTAssertEqual(health.factors.map(\.kind), [.spendable, .cashflow, .emergencyFund, .budget])
    }

    func testOverspendingAndNoSavingsGetTipsWorstFirst() {
        let health = FinancialHealth(input(expense: [12_000_000, 12_000_000, 12_000_000], liquid: 0,
                                           budget: 0, spent: 0, safe: 0))
        XCTAssertEqual(points(health, .spendable), 0)
        XCTAssertEqual(points(health, .cashflow), 0) // −20% savings rate
        XCTAssertEqual(points(health, .emergencyFund), 0)
        XCTAssertTrue(factor(health, .budget)!.isPending) // no budget: left out, not punished
        XCTAssertEqual(health.weakest?.kind, .spendable) // 30 points missing beats 20 and 20
        XCTAssertEqual(health.label, "Perlu perbaikan")
    }

    func testSpendableFollowsPerDayAgainstUsualSpending() {
        // Rp7 jt a month is about Rp233 rb a day; 15 days left.
        XCTAssertEqual(points(FinancialHealth(input(safe: 3_500_000)), .spendable), 30)   // 1.0x
        XCTAssertEqual(points(FinancialHealth(input(safe: 1_750_000)), .spendable), 18)   // 0.5x
        XCTAssertEqual(points(FinancialHealth(input(safe: 400_000)), .spendable), 5)      // thin
        XCTAssertEqual(points(FinancialHealth(input(safe: -963_674)), .spendable), 0)
        XCTAssertNotNil(factor(FinancialHealth(input(safe: -963_674)), .spendable)?.tip)
        // Not known (a past period in a report): the factor is not there.
        XCTAssertNil(factor(FinancialHealth(input(safe: nil)), .spendable))
    }

    func testEmergencyFundAveragesOnlyActiveMonths() {
        // One active month of Rp5 jt spending; Rp20 jt covers 4 months, not 12: 14 + 6 / 3.
        let health = FinancialHealth(input(income: [0, 0, 10_000_000], expense: [0, 0, 5_000_000], liquid: 20_000_000))
        XCTAssertEqual(points(health, .emergencyFund), 16)
    }

    func testEmergencyFundMarks() {
        func fund(_ months: Double) -> Int {
            points(FinancialHealth(input(expense: [10_000_000, 10_000_000, 10_000_000], liquid: 10_000_000 * months)), .emergencyFund)
        }
        XCTAssertEqual(fund(0.5), 3)
        XCTAssertEqual(fund(1), 6)
        XCTAssertEqual(fund(3), 14)
        XCTAssertEqual(fund(6), 20)
        XCTAssertEqual(fund(12), 20)
    }

    func testEmergencyFundCountsEveryWalletIncludingInvestments() {
        // Cash is only Rp1 jt but all wallets hold Rp70 jt: 10 months of Rp7 jt.
        let health = FinancialHealth(input(liquid: 1_000_000, total: 70_000_000))
        XCTAssertEqual(points(health, .emergencyFund), 20)
    }

    func testEmergencyFundWaitsForTwoWeeksOfData() {
        var young = input(liquid: 0)
        young.daysOfData = 10
        let health = FinancialHealth(young)
        XCTAssertTrue(factor(health, .emergencyFund)!.isPending)
        // The score runs on what is rated: spendable 30, cashflow 20, budget 10 -> full marks out of 60.
        XCTAssertEqual(health.score, 100)
        young.daysOfData = FinancialHealth.minDays
        XCTAssertFalse(factor(FinancialHealth(young), .emergencyFund)!.isPending)
    }

    func testRunningCycleIsProjectedToAWholeCycle() {
        // Half a cycle gone with Rp3 jt spent: about Rp6 jt a cycle, so Rp12 jt covers 2 months.
        var running = input(income: [10_000_000], expense: [3_000_000], liquid: 12_000_000, progress: 0.5)
        running.cyclesAreRunning = true
        XCTAssertEqual(running.averageMonthlyExpense, 6_000_000)
        XCTAssertEqual(points(FinancialHealth(running), .emergencyFund), 10) // 2 months: 6 + 8 / 2
    }

    func testNoIncomeRecordedLeavesCashflowOut() {
        let health = FinancialHealth(input(income: [0, 0, 0], expense: [1_000_000, 1_000_000, 1_000_000]))
        let flow = factor(health, .cashflow)!
        XCTAssertTrue(flow.isPending)
        XCTAssertNotNil(flow.tip)
        XCTAssertEqual(flow.missing, 0)
        XCTAssertEqual(health.score, 100) // the rest is on track
    }

    private func debt(_ health: FinancialHealth) -> FinancialHealth.Factor { factor(health, .debt)! }

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
        // A card with nothing owed: full points.
        XCTAssertEqual(points(FinancialHealth(input(hasCard: true)), .debt), 20)
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
        XCTAssertEqual(points(FinancialHealth(input(spent: 2_500_000, progress: 0.5)), .budget), 10)
        XCTAssertEqual(points(FinancialHealth(input(spent: 3_500_000, progress: 0.5)), .budget), 0)
        XCTAssertEqual(points(FinancialHealth(input(spent: 6_000_000, progress: 0.9)), .budget), 0) // over budget
    }

    func testLabelsUseTheSameCutOffsAsTheRingOnBeranda() {
        // Only "Bisa dipakai" is rated (no income, no budget, 5 days of data): its points over 30 are the score.
        func rated(safe: Double) -> FinancialHealth {
            var user = input(income: [0], expense: [7_000_000], budget: 0, safe: safe)
            user.daysOfData = 5
            return FinancialHealth(user)
        }
        XCTAssertEqual(rated(safe: 3_500_000).score, 100)
        XCTAssertEqual(rated(safe: 3_500_000).label, "Sehat")
        XCTAssertEqual(rated(safe: 1_750_000).score, 60)
        XCTAssertEqual(rated(safe: 1_750_000).label, "Cukup sehat")
        XCTAssertEqual(rated(safe: 1_000_000).score, 33) // 10 of 30
        XCTAssertEqual(rated(safe: 1_000_000).label, "Perlu perbaikan")
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
