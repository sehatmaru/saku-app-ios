import XCTest
@testable import Saku

/// Enhancement 3 - Upgrade akun tamu: when Beranda asks a guest to save their account (TC 305).
final class GuestUpgradeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func days(_ n: Double) -> Date { now.addingTimeInterval(-n * 86_400) }

    private func shows(isGuest: Bool = true, transactions: Int = 0, signedUp: Date?, dismissed: Int = 0, hiddenUntil: Date? = nil) -> Bool {
        GuestCardPolicy.shows(isGuest: isGuest, transactionCount: transactions, signedUpAt: signedUp,
                              dismissCount: dismissed, hiddenUntil: hiddenUntil, now: now)
    }

    func testNotShownOnDayOneWithFourTransactions() {
        XCTAssertFalse(shows(transactions: 4, signedUp: days(1)))
    }

    func testShownWithFiveTransactionsOrAfterThreeDays() {
        XCTAssertTrue(shows(transactions: 5, signedUp: days(0.1)))
        XCTAssertTrue(shows(transactions: 0, signedUp: days(3)))
        XCTAssertFalse(shows(transactions: 0, signedUp: days(2.9)))
    }

    func testClosingPausesForThreeDays() {
        let until = now.addingTimeInterval(3 * 86_400)
        XCTAssertFalse(shows(transactions: 9, signedUp: days(9), dismissed: 1, hiddenUntil: until))
        XCTAssertTrue(shows(transactions: 9, signedUp: days(9), dismissed: 1, hiddenUntil: now.addingTimeInterval(-1)))
    }

    func testThirdCloseEndsItForGood() {
        XCTAssertFalse(shows(transactions: 9, signedUp: days(30), dismissed: 3))
        XCTAssertTrue(shows(transactions: 9, signedUp: days(30), dismissed: 2))
    }

    func testNeverForARealAccount() {
        XCTAssertFalse(shows(isGuest: false, transactions: 50, signedUp: days(30)))
    }
}
