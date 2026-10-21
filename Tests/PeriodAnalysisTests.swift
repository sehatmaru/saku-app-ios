import XCTest
@testable import Saku

/// Analisis Periode (Fitur 7) US1: headline and projected score.
@MainActor
final class PeriodAnalysisTests: XCTestCase {
    override func setUp() {
        UserDefaults.standard.set("id", forKey: "appLanguage")
    }

    private func input(income: [Double] = [10_000_000, 10_000_000, 10_000_000],
                       expense: [Double] = [9_000_000, 9_000_000, 9_000_000],
                       spent: Double = 4_500_000) -> FinancialHealth.Input {
        .init(monthlyIncome: income, monthlyExpense: expense, liquidBalance: 5_000_000,
              creditDebt: 0, creditLimit: 0, hasCreditCard: false,
              budgetTotal: 5_000_000, budgetSpent: spent, monthProgress: 0.5,
              activeDays: 25, topExpenseCategory: "Makan", hasTransactions: true)
    }

    // TC 26
    func testPositiveNetHeadline() {
        XCTAssertEqual(PeriodAnalysis.headline(income: 15_000_000, expense: 9_840_000),
                       "Net positif +Rp5.160.000. Sisa periode ini 34% dari pemasukan.")
    }

    // TC 27
    func testDeficitHeadlineIsHelpfulAndNeverSaysMenyisihkan() {
        let text = PeriodAnalysis.headline(income: 10_000_000, expense: 11_200_000)
        XCTAssertTrue(text.hasPrefix("Net negatif −Rp1.200.000."))
        XCTAssertTrue(text.contains("112%"))
        XCTAssertFalse(text.lowercased().contains("menyisihkan"))
    }

    func testNoIncomeHeadlineHasNoPercentage() {
        let text = PeriodAnalysis.headline(income: 0, expense: 500_000)
        XCTAssertEqual(text, "Net negatif −Rp500.000. Belum ada pemasukan tercatat di periode ini.")
    }

    func testBalancedPeriod() {
        XCTAssertTrue(PeriodAnalysis.headline(income: 1_000_000, expense: 1_000_000).hasPrefix("Net seimbang"))
    }

    // TC 28
    func testProjectedScoreRecomputesTogetherAndStaysUnder100() {
        let base = input()
        let cutSpending: (inout FinancialHealth.Input) -> Void = { $0.monthlyExpense = $0.monthlyExpense.map { $0 * 0.7 } }
        let lowerBudget: (inout FinancialHealth.Input) -> Void = { $0.budgetSpent *= 0.5 }

        var hypothetical = base
        cutSpending(&hypothetical)
        lowerBudget(&hypothetical)
        let together = PeriodAnalysis.projectedScore(base, applying: [cutSpending, lowerBudget])
        XCTAssertEqual(together, FinancialHealth(hypothetical).score)

        let current = FinancialHealth(base).score
        let sumOfGains = (PeriodAnalysis.projectedScore(base, applying: [cutSpending]) - current)
            + (PeriodAnalysis.projectedScore(base, applying: [lowerBudget]) - current)
        XCTAssertLessThanOrEqual(together, 100)
        XCTAssertLessThanOrEqual(together, current + sumOfGains)
    }

    func testNoEditsKeepsTheCurrentScore() {
        let base = input()
        XCTAssertEqual(PeriodAnalysis.projectedScore(base, applying: []), FinancialHealth(base).score)
    }
}
