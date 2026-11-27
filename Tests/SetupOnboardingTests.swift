import XCTest
@testable import Saku

/// Enhancement 2 - Setup awal pendaftaran: the numbers and texts behind the new steps and the welcome screen.
@MainActor
final class SetupOnboardingTests: XCTestCase {
    override func setUp() {
        UserDefaults.standard.set("id", forKey: "appLanguage")
    }

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }

    // US: the period card on the payday step
    func testPeriodCardNumbersForPayday25() {
        let n = SetupPeriodCard.numbers(day: 25, now: date(2026, 10, 22), calendar: calendar)
        XCTAssertEqual(n, .init(total: 30, elapsed: 28, left: 3))
    }

    func testPeriodCardOnPaydayItselfIsDayOne() {
        let n = SetupPeriodCard.numbers(day: 25, now: date(2026, 10, 25), calendar: calendar)
        XCTAssertEqual(n.elapsed, 1)
        XCTAssertEqual(n.left, n.total)
    }

    func testEndOfMonthPaydayUsesTheLastDayOfShortMonths() {
        // 31 in February is the 28th: the period from Jan 31 to Feb 28 is 28 days long
        let n = SetupPeriodCard.numbers(day: 31, now: date(2027, 2, 10), calendar: calendar)
        XCTAssertEqual(n.total, 28)
        XCTAssertEqual(n.elapsed, 11)
    }

    // US5: the welcome screen rows
    private func rows(payday: Int? = 25, wallets: [String] = ["BNC", "Tunai"]) -> [SetupSummaryRow] {
        SetupSummaryRow.rows(wallets: wallets, expense: 7, income: 4, paydayDay: payday)
    }

    func testSummaryRowsCountWalletsCategoriesAndPayday() {
        let r = rows()
        XCTAssertEqual(r.count, 3)
        XCTAssertEqual(r[0].number, 2)
        XCTAssertEqual(r[0].detail, "BNC, Tunai")
        XCTAssertEqual(r[1].number, 11)
        XCTAssertEqual(r[2].number, 25)
        XCTAssertEqual(r[2].count(25), "Tgl 25")
    }

    func testSummaryPaydayRowForTheSpecialChoicesAndSkipping() {
        XCTAssertEqual(rows(payday: 31)[2].text, "Akhir bulan")
        XCTAssertEqual(rows(payday: 1)[2].text, "Tgl 1")
        XCTAssertEqual(rows(payday: nil)[2].text, "Tgl 1", "skipped reads as the 1st")
    }

    // the setup that is applied
    func testSetupDefaultsToNoBudgetNoAgreementNoTrial() {
        let setup = OnboardingSetup(name: "Dina", wallets: [], hiddenCategoryKeys: [], paydayDay: nil)
        XCTAssertTrue(setup.budgets.isEmpty)
        XCTAssertFalse(setup.smartTrackerConsent)
        XCTAssertFalse(setup.joinsPlus)
    }

    // US1: a card made in setup has a name only, so it has no bill until limit and due day are filled in
    private func card(limit: Double?, due: String?) -> Account {
        Account(id: "c", name: "Kartu kredit", type: .credit, icon: nil, isArchived: false, isDefault: false,
                openingBalance: 0, currentBalance: 0, creditLimit: limit, dueDate: due)
    }

    func testCardFromSetupHasNoBillUntilDetailsAreFilled() {
        let bare = card(limit: nil, due: nil)
        XCTAssertTrue(bare.needsCardDetails)
        XCTAssertNil(CreditStatement(card: bare, transactions: [], installments: []))
        XCTAssertTrue(card(limit: 5_000_000, due: nil).needsCardDetails)
        XCTAssertTrue(card(limit: nil, due: "20").needsCardDetails)
    }

    func testCompleteCardKeepsItsBill() {
        let full = card(limit: 5_000_000, due: "20")
        XCTAssertFalse(full.needsCardDetails)
        XCTAssertNotNil(CreditStatement(card: full, transactions: [], installments: []))
    }
}
