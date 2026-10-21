import PDFKit
import XCTest
@testable import Saku

/// Analisis Periode (Fitur 7) US3-US6: suggestions, edge cases, free preview and privacy, short texts.
@MainActor
final class PeriodAdviceTests: XCTestCase {
    override func setUp() {
        UserDefaults.standard.set("id", forKey: "appLanguage")
    }

    private func totals(income: Double = 15_000_000, expense: Double, _ categories: [String: Double] = [:]) -> PeriodAnalysis.Totals {
        .init(income: income, expense: expense, categories: categories)
    }

    private func health(debt: Double = 0, liquid: Double = 20_000_000, budgetTotal: Double = 4_000_000, budgetSpent: Double = 3_000_000,
                        activeDays: Int = 10) -> FinancialHealth.Input {
        .init(monthlyIncome: [15_000_000, 15_000_000, 15_000_000], monthlyExpense: [9_000_000, 9_000_000, 9_000_000],
              liquidBalance: liquid, creditDebt: debt, creditLimit: 0, hasCreditCard: debt > 0,
              budgetTotal: budgetTotal, budgetSpent: budgetSpent, monthProgress: 0.8,
              activeDays: activeDays, topExpenseCategory: "Makan Harian", hasTransactions: true)
    }

    private func input(previous: Int = 3, debt: Double = 0, liquid: Double = 20_000_000, budgetTotal: Double = 4_000_000,
                       isPrivate: Bool = false, income: Double = 15_000_000) -> PeriodAnalysis.Input {
        let before = Array(repeating: totals(expense: 9_000_000, ["Makan Harian": 2_300_000, "Tagihan & Langganan": 800_000]), count: previous)
        return .init(current: totals(income: income, expense: 10_000_000, ["Makan Harian": 3_150_000, "Jajan & Kopi": 900_000, "Tagihan & Langganan": 1_410_000]),
                     previous: before, health: health(debt: debt, liquid: liquid, budgetTotal: budgetTotal),
                     budgets: budgetTotal > 0 ? [ReportModel.BudgetLine(name: "Makan Harian", spent: 3_150_000, amount: 3_000_000, isProvisional: false)] : [],
                     charges: [.init(name: "Netflix", amount: 186_000), .init(name: "Spotify", amount: 55_000), .init(name: "Listrik", amount: 781_000)],
                     billsTotal: 1_410_000, flexibleCategories: ["Jajan & Kopi"], isPrivate: isPrivate)
    }

    // US3

    func testThreeDistinctSuggestionsMostEffectiveFirst() {
        let advice = PeriodAnalysis.advice(input())
        XCTAssertEqual(advice.suggestions.count, 3)
        XCTAssertEqual(Set(advice.suggestions.map(\.kind)).count, 3, "no action twice")
        let gains = advice.suggestions.map(\.scoreImpact)
        XCTAssertEqual(gains, gains.sorted(by: >))
    }

    func testProjectedScoreIsAtLeastTheCurrentOneAndAtMost100() {
        let current = FinancialHealth(input().health).score
        let projected = PeriodAnalysis.advice(input()).projectedScore
        XCTAssertGreaterThanOrEqual(projected, current)
        XCTAssertLessThanOrEqual(projected, 100)
    }

    func testEstimatesAreRoundedAndMarked() throws {
        let advice = PeriodAnalysis.advice(input())
        let withRupiah = try XCTUnwrap(advice.suggestions.first { !$0.impact.isEmpty })
        XCTAssertTrue(withRupiah.impact.hasPrefix("±Rp"), withRupiah.impact)
        XCTAssertEqual(PeriodAnalysis.rounded(153_400), 150_000)
        XCTAssertEqual(PeriodAnalysis.rounded(1_234_000), 1_250_000)
    }

    func testNeverAdvisesAnEmergencyFundOrMentionsCardInterest() {
        for scenario in [input(), input(debt: 2_000_000), input(budgetTotal: 0), input(previous: 0)] {
            for suggestion in PeriodAnalysis.advice(scenario).suggestions {
                let text = (suggestion.action + suggestion.reason + suggestion.shortAction + suggestion.shortReason).lowercased()
                XCTAssertFalse(text.contains("dana darurat") || text.range(of: #"\bbunga\b"#, options: .regularExpression) != nil, text)
            }
        }
    }

    func testCardPaymentIsOnlySuggestedWhenCashCoversIt() {
        let covered = PeriodAnalysis.Suggestion.Kind.payCardInFull
        let kinds = { (i: PeriodAnalysis.Input) in PeriodAnalysis.advice(i).suggestions.map(\.kind) }
        // Not every candidate makes the top three, so check the one that would: a big debt the cash covers.
        let big = input(debt: 12_000_000, liquid: 20_000_000)
        XCTAssertTrue(kinds(big).contains(covered))
        XCTAssertFalse(kinds(input(debt: 12_000_000, liquid: 1_000_000)).contains(covered))
    }

    // US4

    func testFewerThanThreePeriodsUsesTheHealthyReferenceAndSaysSo() throws {
        let analysis = try XCTUnwrap(PeriodAnalysis.make(input(previous: 1)))
        XCTAssertEqual(analysis.note, "Perbandingan butuh minimal 3 periode. Analisis ini memakai data periode ini saja.")
        let comparison = try XCTUnwrap(analysis.findings.first)
        XCTAssertTrue(comparison.body.contains("acuan sehat 20%"), comparison.body)
        XCTAssertNil(try XCTUnwrap(PeriodAnalysis.make(input())).note)
    }

    func testWithoutBudgetTheFindingAndAdviceInviteOne() throws {
        let analysis = try XCTUnwrap(PeriodAnalysis.make(input(budgetTotal: 0)))
        XCTAssertFalse(analysis.hasBudgets)
        XCTAssertEqual(analysis.findings[1].title, "Belum ada budget untuk dibandingkan")
        XCTAssertTrue(analysis.suggestions.contains { $0.kind == .createBudget })
    }

    func testNothingRecordedMeansNoAnalysis() {
        var empty = input()
        empty.current = totals(income: 0, expense: 0)
        XCTAssertNil(PeriodAnalysis.make(empty))
    }

    func testAlwaysThreeFindingsAndThreeSuggestions() throws {
        for scenario in [input(), input(previous: 0), input(budgetTotal: 0), input(income: 0)] {
            let analysis = try XCTUnwrap(PeriodAnalysis.make(scenario))
            XCTAssertEqual(analysis.findings.count, 3)
            XCTAssertEqual(analysis.suggestions.count, 3)
        }
    }

    func testScoreIsLeftOutWhenThereIsNothingToScore() throws {
        var scenario = input()
        scenario.health.hasTransactions = false
        XCTAssertNil(try XCTUnwrap(PeriodAnalysis.make(scenario)).score)
    }

    // US5 privacy

    func testPrivateModeHasNoRupiahAmountInAnyText() throws {
        let analysis = try XCTUnwrap(PeriodAnalysis.make(input(debt: 2_000_000, isPrivate: true)))
        var texts: [String] = []
        for f in analysis.findings { texts += [f.title, f.evidence, f.caption, f.body, f.shortBody] + f.bars.map(\.text) }
        for s in analysis.suggestions { texts += [s.action, s.reason, s.shortAction, s.shortReason, s.impact] }
        for text in texts {
            XCTAssertNil(text.range(of: #"Rp\s?\d"#, options: .regularExpression), "amount shown in private mode: \(text)")
        }
    }

    // US6

    func testDisclaimerIsFixed() {
        XCTAssertEqual(PeriodAnalysis.disclaimer, "Analisis otomatis dari catatanmu. Bukan nasihat keuangan profesional.")
    }

    func testEveryFindingAndSuggestionHasAShortVersion() throws {
        let analysis = try XCTUnwrap(PeriodAnalysis.make(input(debt: 2_000_000)))
        for f in analysis.findings { XCTAssertFalse(f.shortBody.isEmpty) }
        for s in analysis.suggestions { XCTAssertFalse(s.shortAction.isEmpty); XCTAssertFalse(s.shortReason.isEmpty) }
    }

    // The report (design "Laporan Keuangan v3")

    private func report(isPreview: Bool, isPrivate: Bool = false) -> ReportModel {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone.current
        func d(_ m: Int, _ day: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: m, day: day, hour: 12))! }
        let cats = [Saku.Category(id: "makan", name: "Makan Harian", icon: nil, color: nil, type: .expense, systemKey: "expense_daily_meals")]
        var txns: [Transaction] = []
        for (n, m) in [6, 7, 8, 9].enumerated() {
            txns.append(Transaction(id: "i\(n)", accountId: "bca", counterpartyAccountId: nil, categoryId: nil, amount: 15_000_000, type: .income,
                                    description: nil, note: nil, date: d(m, 26), delta: nil))
            txns.append(Transaction(id: "e\(n)", accountId: "bca", counterpartyAccountId: nil, categoryId: "makan", amount: m == 9 ? 3_150_000 : 2_300_000,
                                    type: .expense, description: nil, note: nil, date: d(m, 27), delta: nil))
        }
        let interval = DateInterval(start: d(9, 25), end: d(10, 25))
        let rows = [BudgetHistoryRow(budgetId: "b1", categoryId: "makan", amount: 3_000_000, spent: 3_150_000, source: .base, isDeleted: false, transactions: [])]
        let wallet = Account(id: "bca", name: "BCA", type: .bank, icon: nil, isArchived: false, isDefault: true, openingBalance: 0,
                             currentBalance: 12_500_000, creditLimit: nil, dueDate: nil)
        return ReportModel.make(interval: interval, cycle: PaydayCycle(day: 25), userName: "Rina", transactions: txns, accounts: [wallet],
                                categories: cats, period: BudgetHistoryPeriod(interval: interval, rows: rows, income: 0, expense: 0),
                                isPrivate: isPrivate, isPreview: isPreview, now: d(10, 25))
    }

    func testReportCarriesTheAnalysis() throws {
        let model = report(isPreview: false)
        let analysis = try XCTUnwrap(model.analysis)
        XCTAssertEqual(analysis.findings.count, 3)
        XCTAssertEqual(analysis.suggestions.count, 3)
        XCTAssertEqual(model.headline.map(\.text).joined(), PeriodAnalysis.headline(income: model.income, expense: model.expense))
        XCTAssertFalse(model.headline.map(\.text).joined().lowercased().contains("menyisihkan"))
    }

    func testPdfHasOnePageWithTheDisclaimerAndTheAnalysis() throws {
        let pdf = try XCTUnwrap(PDFDocument(data: ReportRenderer.data(report(isPreview: false))))
        XCTAssertEqual(pdf.pageCount, 1, "analysis and suggestions never run onto a second page")
        let text = try XCTUnwrap(pdf.string)
        XCTAssertTrue(text.contains("Bukan nasihat keuangan profesional"))
        XCTAssertTrue(text.contains("Rp150.000 di atas Rp3.000.000"), "the over-budget finding is in the file")
    }

    func testFreePreviewKeepsHeadlineScoreAndTitlesButNotTheDetail() throws {
        let model = report(isPreview: true)
        let analysis = try XCTUnwrap(model.analysis)
        // Text extraction breaks lines where the page wraps them.
        let text = try XCTUnwrap(PDFDocument(data: ReportRenderer.data(model))?.string).replacingOccurrences(of: "\n", with: " ")
        XCTAssertTrue(text.contains("Net positif"))
        XCTAssertTrue(text.contains("Skor kesehatan"))
        for finding in analysis.findings {
            XCTAssertTrue(text.contains(finding.title), "title stays readable")
            XCTAssertFalse(text.contains(finding.body), "body must not be in the file")
            // Short ones ("100%") can also appear in the supporting data, which stays readable.
            if finding.evidence.count > 4 { XCTAssertFalse(text.contains(finding.evidence), "evidence must not be in the file") }
        }
        for suggestion in analysis.suggestions { XCTAssertFalse(text.contains(suggestion.action), "advice must not be in the file") }
    }
}
