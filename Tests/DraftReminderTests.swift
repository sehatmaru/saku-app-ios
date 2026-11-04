import XCTest
@testable import Saku

final class DraftReminderTests: XCTestCase {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Jakarta")!; return c }
    private func date(_ d: Int, _ h: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h))! }

    func testTwoRemindersFiveHoursAndOneDayAfterTheOldestDraft() {
        let times = DraftReminder.fireDates(oldest: date(4, 8), now: date(4, 8), calendar: cal)
        XCTAssertEqual(times.map(\.hours), [5, 24])
        XCTAssertEqual(times[0].date, date(4, 13))
        XCTAssertEqual(times[1].date, date(5, 8))
    }

    func testPassedReminderIsDropped() {
        let times = DraftReminder.fireDates(oldest: date(4, 8), now: date(4, 14), calendar: cal)
        XCTAssertEqual(times.map(\.hours), [24])
    }

    func testQuietHoursMoveToSevenInTheMorning() {
        // 23:00 + 5 h = 04:00 -> 07:00 the same day; 18:00 + 5 h = 23:00 -> 07:00 next day
        XCTAssertEqual(DraftReminder.fireDates(oldest: date(4, 23), now: date(4, 23), calendar: cal)[0].date, date(5, 7))
        XCTAssertEqual(DraftReminder.fireDates(oldest: date(4, 18), now: date(4, 18), calendar: cal)[0].date, date(5, 7))
    }
}
