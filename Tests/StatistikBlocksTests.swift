import XCTest
@testable import Saku

final class StatistikBlocksTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }

    func testComparableCutsTheEarlierPeriodToTheSameNumberOfDays() {
        let main = DateInterval(start: date(2026, 11, 1), end: date(2026, 12, 1))
        let last = DateInterval(start: date(2026, 10, 1), end: date(2026, 11, 1))
        // day 17 of November: October is cut to its first 17 days
        let cut = StatistikBlocks.comparable(last, to: main, now: date(2026, 11, 17), calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.day], from: cut.start, to: cut.end).day, 17)
        // a finished period keeps the whole comparison
        let whole = StatistikBlocks.comparable(last, to: last, now: date(2026, 11, 17), calendar: calendar)
        XCTAssertEqual(whole, last)
    }

    func testCumulativeAndElapsed() {
        XCTAssertEqual(StatistikBlocks.cumulative([1, 2, 3]), [1, 3, 6])
        XCTAssertEqual(StatistikBlocks.cumulative([1, 2, 3], through: 2), [1, 3])
        let range = DateInterval(start: date(2026, 11, 1), end: date(2026, 12, 1))
        XCTAssertEqual(StatistikBlocks.elapsedDays(range, now: date(2026, 11, 17), calendar: calendar), 17)
        XCTAssertEqual(StatistikBlocks.elapsedDays(range, now: date(2027, 1, 1), calendar: calendar), 30)
    }

    func testChangeNeedsSomethingToDivideBy() {
        XCTAssertNil(StatistikBlocks.change(10, 0))
        XCTAssertEqual(StatistikBlocks.change(118, 100)!, 0.18, accuracy: 0.0001)
    }

    func testWeekdayAveragesStartOnMonday() {
        // 2026-11-02 is a Monday
        let averages = StatistikBlocks.weekdayAverages([100, 0, 0, 0, 0, 0, 0, 300], start: date(2026, 11, 2), calendar: calendar)
        XCTAssertEqual(averages[0], 200, accuracy: 0.001)
        XCTAssertEqual(averages[1], 0, accuracy: 0.001)
    }
}
