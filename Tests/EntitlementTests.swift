import XCTest
@testable import Saku

/// Epic 11 foundation: the one entitlement gate (US8) and the wallet limit (US9).
@MainActor
final class EntitlementTests: XCTestCase {
    override func tearDown() { PlusStore.shared.reset() }

    private func wallet(_ id: String, _ type: Account.AccountType, archived: Bool = false) -> Account {
        Account(id: id, name: id, type: type, icon: nil, isArchived: archived, isDefault: false,
                openingBalance: 0, currentBalance: 0, creditLimit: nil, dueDate: nil)
    }

    func testStatusesAndEndDate() {
        let now = Date()
        XCTAssertFalse(Entitlement.free.isPlus())
        for status in [PlusStatus.trial, .active, .grace] {
            XCTAssertTrue(Entitlement(status: status).isPlus(at: now), "\(status) counts as Plus")
        }
        XCTAssertTrue(Entitlement(status: .active, until: now.addingTimeInterval(60)).isPlus(at: now))
        XCTAssertFalse(Entitlement(status: .active, until: now.addingTimeInterval(-60)).isPlus(at: now), "ended")
        XCTAssertFalse(Entitlement(status: .free, until: now.addingTimeInterval(60)).isPlus(at: now))
    }

    func testReadsTheServersColumns() {
        XCTAssertEqual(Entitlement(status: "active", until: "2099-01-01T00:00:00.123456+00:00").status, .active)
        XCTAssertNotNil(Entitlement(status: "trial", until: "2099-01-01T00:00:00.123456+00:00").until)
        XCTAssertEqual(Entitlement(status: nil, until: nil), .free, "a server without the columns reads as free")
        XCTAssertEqual(Entitlement(status: "nonsense", until: nil), .free)
    }

    /// The device keeps its copy so Shortcuts (no main actor) and offline use see the same answer (US4).
    func testDeviceCopyFollowsTheStore() {
        PlusStore.shared.apply(Entitlement(status: .active), isTester: true)
        XCTAssertTrue(PlusStore.shared.isPlus)
        XCTAssertTrue(PlusStore.cachedIsPlus)
        PlusStore.shared.reset()
        XCTAssertFalse(PlusStore.cachedIsPlus)
        XCTAssertFalse(PlusStore.shared.isTester)
    }

    /// US9: 5 money wallets and 1 investment wallet; archived ones do not count; Plus lifts the limit.
    func testWalletLimit() {
        let five = [wallet("a", .bank), wallet("b", .cash), wallet("c", .ewallet), wallet("d", .credit), wallet("e", .bank)]
        XCTAssertFalse(FreeLimits.isWalletLimited(.bank, in: Array(five.prefix(4)), isPlus: false))
        XCTAssertTrue(FreeLimits.isWalletLimited(.bank, in: five, isPlus: false), "TC 23: the 6th money wallet")
        XCTAssertTrue(FreeLimits.isWalletLimited(.credit, in: five, isPlus: false))
        XCTAssertFalse(FreeLimits.isWalletLimited(.investment, in: five, isPlus: false), "investment has its own slot")
        XCTAssertFalse(FreeLimits.isWalletLimited(.bank, in: five, isPlus: true))

        let archived = Array(five.prefix(4)) + [wallet("x", .bank, archived: true)]
        XCTAssertFalse(FreeLimits.isWalletLimited(.bank, in: archived, isPlus: false), "archived wallets are not counted")

        let withInvestment = [wallet("i", .investment)]
        XCTAssertTrue(FreeLimits.isWalletLimited(.investment, in: withInvestment, isPlus: false), "TC 24: the 2nd investment wallet")
        XCTAssertFalse(FreeLimits.isWalletLimited(.bank, in: withInvestment, isPlus: false))
    }

    func testServerWalletRefusalIsReadable() {
        struct Raw: Error, CustomStringConvertible { let description: String }
        XCTAssertTrue(FreeLimits.friendly(Raw(description: "wallet_limit_money")) is FreeLimits.LimitError)
        XCTAssertTrue(FreeLimits.friendly(Raw(description: "wallet_limit_investment")) is FreeLimits.LimitError)
    }
}

/// Phases and the banner (design "Plus B Status").
@MainActor
final class PlusPhaseTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func day(_ n: Double) -> Date { now.addingTimeInterval(n * 86_400 - 3_600) }

    func testPhases() {
        XCTAssertEqual(Entitlement.free.phase(at: now), .free)
        XCTAssertEqual(Entitlement(status: .trial, until: day(3)).phase(at: now), .trial)
        XCTAssertEqual(Entitlement(status: .active, until: day(300)).phase(at: now), .active)
        XCTAssertEqual(Entitlement(status: .grace, until: day(5)).phase(at: now), .grace)
        XCTAssertEqual(Entitlement(status: .active, until: day(-1)).phase(at: now), .ended, "a past end date is ended, not free")
        XCTAssertEqual(Entitlement(status: .active, until: nil).phase(at: now), .active)
    }

    func testDaysLeftCountsAStartedDay() {
        XCTAssertEqual(Entitlement(status: .trial, until: day(3)).daysLeft(at: now), 3)
        XCTAssertEqual(Entitlement(status: .trial, until: day(1)).daysLeft(at: now), 1)
        XCTAssertNil(Entitlement(status: .active).daysLeft(at: now))
    }

    func testBannerPriorityAndDays() {
        XCTAssertEqual(PlusBanner.pick(for: Entitlement(status: .grace, until: day(5)), now: now, dismissed: [])?.kind, .grace)
        XCTAssertEqual(PlusBanner.pick(for: Entitlement(status: .trial, until: day(2)), now: now, dismissed: [])?.kind, .trialEnding(days: 2))
        XCTAssertEqual(PlusBanner.pick(for: Entitlement(status: .trial, until: day(1)), now: now, dismissed: [])?.kind, .trialEnding(days: 1))
        XCTAssertNil(PlusBanner.pick(for: Entitlement(status: .trial, until: day(3)), now: now, dismissed: []), "day 4 and earlier: no banner")
        XCTAssertNil(PlusBanner.pick(for: Entitlement(status: .active, until: day(1)), now: now, dismissed: []), "a paid plan has no trial banner")
        XCTAssertNil(PlusBanner.pick(for: Entitlement.free, now: now, dismissed: []))
    }

    func testClosedBannerStaysClosedOnlyForTheSameSituation() {
        let trial2 = Entitlement(status: .trial, until: day(2))
        let key = PlusBanner.pick(for: trial2, now: now, dismissed: [])!.key
        XCTAssertNil(PlusBanner.pick(for: trial2, now: now, dismissed: [key]))
        let trial1 = Entitlement(status: .trial, until: day(1))
        XCTAssertNotNil(PlusBanner.pick(for: trial1, now: now, dismissed: [key]), "the next day is a new banner")
    }
}

final class PlusBarsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ days: Double) -> Date { now.addingTimeInterval(days * 86_400) }

    func testTrialHasSevenBarsLitByDaysLeft() {
        let bars = Entitlement(status: .trial, until: at(4)).bars(at: now)
        XCTAssertEqual(bars?.total, 7); XCTAssertEqual(bars?.filled, 4)
    }

    func testYearlyHasTwelveBarsOneAMonth() {
        let bars = Entitlement(status: .active, until: at(120), plan: .yearly).bars(at: now)
        XCTAssertEqual(bars?.total, 12); XCTAssertEqual(bars?.filled, 4)
        XCTAssertEqual(Entitlement(status: .active, until: at(365), plan: .yearly).bars(at: now)?.filled, 12)
    }

    func testMonthlyHasTenBarsOneEveryThreeDays() {
        let bars = Entitlement(status: .active, until: at(10), plan: .monthly).bars(at: now)
        XCTAssertEqual(bars?.total, 10); XCTAssertEqual(bars?.filled, 4)
        XCTAssertEqual(Entitlement(status: .active, until: at(30), plan: .monthly).bars(at: now)?.filled, 10)
    }

    func testGraceLightsOneAndFreeHasNone() {
        XCTAssertEqual(Entitlement(status: .active, until: at(-1)).bars(at: now)?.filled, 0, "ended is all dim")
        XCTAssertEqual(Entitlement(status: .grace, until: at(3)).bars(at: now)?.filled, 1)
        XCTAssertNil(Entitlement.free.bars(at: now))
    }
}
