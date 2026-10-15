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
