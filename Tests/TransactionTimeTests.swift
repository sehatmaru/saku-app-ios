import XCTest
@testable import Saku

/// SAKU-770: the transaction lists show the hour a transaction was recorded,
/// and keep the "no time recorded" convention for midnight.
final class TransactionTimeTests: XCTestCase {
    private func time(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
    }

    func testTimeIsShownWhenRecorded() {
        XCTAssertEqual(TransactionDates.timeOfDay(time(14, 4)), "14.04")
        XCTAssertEqual(TransactionDates.timeOfDay(time(8, 5)), "08.05", "hours and minutes are padded")
    }

    func testMidnightMeansNoTimeWasRecorded() {
        XCTAssertNil(TransactionDates.timeOfDay(time(0, 0)))
    }

    /// 00.30 is a real time, only exactly midnight means "not recorded".
    func testMinutePastMidnightCountsAsATime() {
        XCTAssertEqual(TransactionDates.timeOfDay(time(0, 30)), "00.30")
    }

    func testLongDateKeepsTheSameWording() {
        XCTAssertTrue(TransactionDates.long(time(14, 4)).hasSuffix("· 14.04"))
        XCTAssertFalse(TransactionDates.long(time(0, 0)).contains("· 00.00"))
    }
}
