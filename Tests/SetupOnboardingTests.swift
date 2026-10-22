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

    // US5: the welcome screen
    private func tiles(_ welcome: SetupWelcome) -> [SetupWelcomeView.Tile] {
        SetupWelcomeView(welcome: welcome, onOpen: { _ in }).tiles
    }

    private func welcome(payday: Int? = 25, budget: Double = 0, plus: Bool = false) -> SetupWelcome {
        SetupWelcome(name: "Dina", wallets: 2, categories: 9, paydayDay: payday, budgetTotal: budget, joinedPlus: plus, plusUntil: nil)
    }

    func testWelcomeTilesCountWalletsCategoriesAndPayday() {
        let t = tiles(welcome())
        XCTAssertEqual(t.count, 3)
        XCTAssertEqual(t[0], .init(number: 2, text: "", label: "dompet"))
        XCTAssertEqual(t[1], .init(number: 9, text: "", label: "kategori"))
        XCTAssertEqual(t[2], .init(number: 25, text: "", label: "tanggal gajian"))
    }

    func testWelcomePaydayTileForTheSpecialChoicesAndSkipping() {
        XCTAssertEqual(tiles(welcome(payday: 31))[2].text, "Akhir")
        XCTAssertEqual(tiles(welcome(payday: 1))[2].text, "Tgl 1")
        XCTAssertEqual(tiles(welcome(payday: nil))[2].text, "Tgl 1", "skipped reads as the 1st")
    }

    func testWelcomeShowsABudgetTileOnlyWhenOneWasSet() {
        XCTAssertEqual(tiles(welcome()).count, 3)
        let t = tiles(welcome(budget: 3_500_000))
        XCTAssertEqual(t.count, 4)
        XCTAssertEqual(t[3].text, "Rp3,5 jt")
        XCTAssertEqual(t[3].label, "budget per periode")
    }

    // the setup that is applied
    func testSetupDefaultsToNoBudgetNoAgreementNoTrial() {
        let setup = OnboardingSetup(name: "Dina", wallets: [], hiddenCategoryKeys: [], paydayDay: nil)
        XCTAssertTrue(setup.budgets.isEmpty)
        XCTAssertFalse(setup.smartTrackerConsent)
        XCTAssertFalse(setup.memorySync)
        XCTAssertFalse(setup.joinsPlus)
    }
}
