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
