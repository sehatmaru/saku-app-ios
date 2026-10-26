import XCTest
@testable import Saku

final class EntitlementStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func later(_ days: Double) -> Date { now.addingTimeInterval(days * 86_400) }

    func testFreeTrialIsTrialUntilItsEnd() {
        let e = Entitlement.fromStore(productID: Entitlement.yearlyProductID, expiresAt: later(7), isFreeTrial: true,
                                      isRevoked: false, graceUntil: nil, now: now)
        XCTAssertEqual(e.status, .trial)
        XCTAssertEqual(e.plan, .yearly)
        XCTAssertTrue(e.isPlus(at: now))
    }

    func testPaidPeriodIsActive() {
        let e = Entitlement.fromStore(productID: Entitlement.monthlyProductID, expiresAt: later(20), isFreeTrial: false,
                                      isRevoked: false, graceUntil: nil, now: now)
        XCTAssertEqual(e.status, .active)
        XCTAssertEqual(e.plan, .monthly)
    }

    func testFailedRenewalKeepsPlusDuringGrace() {
        let e = Entitlement.fromStore(productID: Entitlement.monthlyProductID, expiresAt: later(-1), isFreeTrial: false,
                                      isRevoked: false, graceUntil: later(5), now: now)
        XCTAssertEqual(e.status, .grace)
        XCTAssertTrue(e.isPlus(at: now))
    }

    func testExpiredWithoutGraceIsFree() {
        let e = Entitlement.fromStore(productID: Entitlement.monthlyProductID, expiresAt: later(-1), isFreeTrial: false,
                                      isRevoked: false, graceUntil: later(-1), now: now)
        XCTAssertEqual(e.status, .free)
        XCTAssertFalse(e.isPlus(at: now))
    }

    func testRefundIsFreeEvenInsideThePeriod() {
        let e = Entitlement.fromStore(productID: Entitlement.yearlyProductID, expiresAt: later(100), isFreeTrial: false,
                                      isRevoked: true, graceUntil: nil, now: now)
        XCTAssertEqual(e.status, .free)
    }

    func testUnknownProductIsFree() {
        let e = Entitlement.fromStore(productID: "other", expiresAt: later(10), isFreeTrial: false,
                                      isRevoked: false, graceUntil: nil, now: now)
        XCTAssertEqual(e.status, .free)
    }
}

@MainActor
final class PlusTestSwitchTests: XCTestCase {
    private func profile(_ status: String) throws -> UserProfile {
        let id = "6a7d662a-c9b6-4445-a24b-2f3524da8fd3"
        let json = "{\"id\":\"\(id)\",\"auth_user_id\":\"\(id)\",\"default_currency_code\":\"IDR\",\"locale\":\"id\",\"timezone\":\"Asia/Jakarta\",\"plus_status\":\"\(status)\"}"
        return try JSONDecoder().decode(UserProfile.self, from: Data(json.utf8))
    }

    func testAStorePurchaseHoldsPlusUntilTheTestSwitchIsUsed() throws {
        let store = PlusStore.shared
        store.reset()
        store.storeUntil = Date().addingTimeInterval(86_400)
        store.apply(Entitlement(status: .trial, until: Date().addingTimeInterval(86_400)), isTester: false)
        store.apply(try profile("free"))
        XCTAssertTrue(store.isPlus, "the server has not heard of the purchase yet")
        store.useTestSwitch()
        store.apply(try profile("free"))
        XCTAssertFalse(store.isPlus)
        store.useAppStore()
        store.reset()
    }
}
