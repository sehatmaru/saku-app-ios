import XCTest
@testable import Saku

final class DateStampTests: XCTestCase {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Jakarta")!; return c }

    func testTodayBecomesExactlyNow() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 16, minute: 5, second: 9))!
        let draftTime = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 9, minute: 41))!
        XCTAssertEqual(draftTime.atCurrentTime(now: now, calendar: calendar), now)
    }

    func testDraftKeepsTheTimeItArrivedOnThePickedDay() {
        let arrival = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 9, minute: 41, second: 7))!
        let picked = calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 16, minute: 5))!
        let parts = calendar.dateComponents([.day, .hour, .minute, .second], from: picked.atTime(of: arrival, calendar: calendar))
        XCTAssertEqual([parts.day, parts.hour, parts.minute, parts.second], [11, 9, 41, 7])
    }

    func testAPastDayKeepsItsDayAndGetsTheCurrentTime() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 16, minute: 5, second: 9))!
        let picked = calendar.date(from: DateComponents(year: 2026, month: 10, day: 11))!
        let stamped = picked.atCurrentTime(now: now, calendar: calendar)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: stamped)
        XCTAssertEqual([parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second], [2026, 10, 11, 16, 5, 9])
    }
}
