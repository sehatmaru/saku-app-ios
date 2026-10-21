import XCTest
@testable import Saku

/// Analisis Periode (Fitur 7) US2: the three findings.
@MainActor
final class PeriodFindingsTests: XCTestCase {
    override func setUp() {
        UserDefaults.standard.set("id", forKey: "appLanguage")
    }

    private func totals(income: Double = 10_000_000, expense: Double, _ categories: [String: Double] = [:]) -> PeriodAnalysis.Totals {
        .init(income: income, expense: expense, categories: categories)
    }

    private func health(budgetTotal: Double = 5_000_000, budgetSpent: Double = 2_000_000) -> FinancialHealth {
        FinancialHealth(.init(
            monthlyIncome: [10_000_000, 10_000_000, 10_000_000], monthlyExpense: [7_000_000, 7_000_000, 7_000_000],
            liquidBalance: 50_000_000, creditDebt: 0, creditLimit: 0, hasCreditCard: false,
            budgetTotal: budgetTotal, budgetSpent: budgetSpent, monthProgress: 0.5,
            activeDays: 25, topExpenseCategory: "Makan", hasTransactions: true))
    }

    // TC 29
    func testNetRatioRiseNamesThePercentagePoints() throws {
        let before = Array(repeating: totals(expense: 7_900_000), count: 3) // Net 21%
        let finding = try XCTUnwrap(PeriodAnalysis.comparison(current: totals(expense: 6_600_000), previous: before)) // Net 34%
        XCTAssertEqual(finding.group, .comparison)
        XCTAssertEqual(finding.evidence, "+13 poin")
        XCTAssertTrue(finding.body.contains("13 poin persentase"))
        XCTAssertEqual(finding.bars.map(\.value), [34, 21])
    }

    func testSmallShiftsAreNotFindings() {
        let before = Array(repeating: totals(expense: 7_000_000), count: 3)
        XCTAssertNil(PeriodAnalysis.comparison(current: totals(expense: 6_800_000), previous: before)) // 2 points, 3%
    }

    func testCategorySpikeNeedsBothThirtyPercentAndOneHundredThousand() throws {
        let before = Array(repeating: totals(expense: 7_000_000, ["Belanja": 1_000_000, "Kopi": 100_000]), count: 3)
        // Belanja +45% (+Rp450.000) passes both rules; Kopi +90% is only +Rp90.000, under the rupiah floor.
        let spike = try XCTUnwrap(PeriodAnalysis.comparison(
            current: totals(expense: 7_000_000, ["Belanja": 1_450_000, "Kopi": 190_000]), previous: before))
        XCTAssertEqual(spike.title, "Belanja melonjak")
        XCTAssertEqual(spike.evidence, "+45%")
        // With Belanja flat, Kopi's +Rp90.000 alone is not a finding.
        XCTAssertNil(PeriodAnalysis.comparison(
            current: totals(expense: 7_000_000, ["Belanja": 1_000_000, "Kopi": 190_000]), previous: before))
    }

    func testComparisonWaitsForThreePeriods() {
        XCTAssertNil(PeriodAnalysis.comparison(current: totals(expense: 1), previous: [totals(expense: 9_000_000)]))
    }

    // TC 30
    func testBudgetOverrunNamesTheCategoryAndTheAmount() throws {
        let budgets = [ReportModel.BudgetLine(name: "Makan Harian", spent: 3_150_000, amount: 3_000_000, isProvisional: false)]
        let finding = try XCTUnwrap(PeriodAnalysis.holdingBack(health: health(budgetTotal: 3_000_000, budgetSpent: 3_150_000), budgets: budgets))
        XCTAssertEqual(finding.group, .holdingBack)
        XCTAssertTrue(finding.body.contains("Rp150.000 di atas Rp3.000.000"))
        XCTAssertTrue(finding.body.hasPrefix("Makan Harian"))
    }

    func testHealthyScoreHasNothingHoldingItBack() {
        XCTAssertNil(PeriodAnalysis.holdingBack(health: health(), budgets: []))
    }

    // TC 31
    func testStreamingSubscriptionsAreSummedAgainstTagihanDanLangganan() throws {
        let charges: [PeriodAnalysis.Charge] = [.init(name: "Netflix", amount: 186_000), .init(name: "Spotify Premium", amount: 55_000),
                                                .init(name: "Disney+ Hotstar", amount: 388_000), .init(name: "Listrik", amount: 781_000)]
        let finding = try XCTUnwrap(PeriodAnalysis.pattern(current: totals(expense: 5_000_000, ["Makan": 2_000_000]),
                                                           charges: charges, billsTotal: 1_410_000))
        XCTAssertEqual(finding.evidence, "Rp629.000")
        XCTAssertTrue(finding.body.hasPrefix("3 langganan streaming berjumlah Rp629.000, 45%"))
        XCTAssertTrue(finding.body.contains("Rp1.410.000"))
    }

    // TC 32
    func testWithoutSimilarSubscriptionsTheBiggestCategoryIsUsed() throws {
        let charges: [PeriodAnalysis.Charge] = [.init(name: "Netflix", amount: 186_000), .init(name: "Listrik", amount: 781_000)]
        let finding = try XCTUnwrap(PeriodAnalysis.pattern(current: totals(expense: 5_000_000, ["Makan": 2_000_000, "Transport": 800_000]),
                                                           charges: charges, billsTotal: 967_000))
        XCTAssertEqual(finding.title, "Makan pos terbesar")
        XCTAssertEqual(finding.evidence, "40%")
    }

    func testFindingsKeepGroupOrderAndSkipGroupsWithoutCandidates() {
        let result = PeriodAnalysis.findings(current: totals(expense: 6_600_000, ["Makan": 3_000_000]),
                                             previous: Array(repeating: totals(expense: 7_900_000), count: 3),
                                             health: health(), budgets: [], charges: [], billsTotal: 0)
        XCTAssertEqual(result.map(\.group), [.comparison, .pattern]) // the score is full: nothing holds it back
    }
}
