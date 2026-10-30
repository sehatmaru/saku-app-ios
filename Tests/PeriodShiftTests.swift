import XCTest
@testable import Saku

/// Enhancement "Gaji masuk lebih awal" (SAKU-869, US2): an early salary moves the period boundary for that month only.
final class PeriodShiftTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }
    private func range(_ p: DateInterval) -> String {
        let f = DateFormatter(); f.calendar = calendar; f.timeZone = calendar.timeZone; f.dateFormat = "yyyy-MM-dd"
        return "\(f.string(from: p.start)) to \(f.string(from: p.end))"
    }
    /// Payday 25, salary arrived on 20 Okt 2026.
    private var shifted: PaydayCycle { PaydayCycle(day: 25, shifts: [day(2026, 10, 20)]) }

    func testRunningPeriodEndsTheDayBeforeTheEarlySalary() {
        XCTAssertEqual(range(shifted.period(containing: day(2026, 10, 10), calendar: calendar)), "2026-09-25 to 2026-10-20")
        XCTAssertEqual(range(shifted.period(containing: day(2026, 10, 19), calendar: calendar)), "2026-09-25 to 2026-10-20")
    }

    func testNewPeriodStartsOnTheSalaryDateAndRunsToTheNextNormalBoundary() {
        XCTAssertEqual(range(shifted.period(containing: day(2026, 10, 20), calendar: calendar)), "2026-10-20 to 2026-11-25")
        XCTAssertEqual(range(shifted.period(containing: day(2026, 10, 30), calendar: calendar)), "2026-10-20 to 2026-11-25")
        XCTAssertEqual(range(shifted.period(containing: day(2026, 11, 24), calendar: calendar)), "2026-10-20 to 2026-11-25")
    }

    func testBoundaryAfterTheShiftIsNormalAgain() {
        XCTAssertEqual(range(shifted.period(containing: day(2026, 11, 25), calendar: calendar)), "2026-11-25 to 2026-12-25")
    }

    func testPastPeriodsAndTheProfilePaydayAreUntouched() {
        XCTAssertEqual(range(shifted.period(containing: day(2026, 9, 10), calendar: calendar)), "2026-08-25 to 2026-09-25")
        XCTAssertEqual(shifted.day, 25)
    }

    func testWithoutShiftsNothingChanges() {
        let plain = PaydayCycle(day: 25)
        XCTAssertEqual(range(plain.period(containing: day(2026, 10, 22), calendar: calendar)), "2026-09-25 to 2026-10-25")
        XCTAssertEqual(range(plain.period(containing: day(2026, 10, 26), calendar: calendar)), "2026-10-25 to 2026-11-25")
    }

    func testOffsetWalksThroughTheShiftedPeriods() {
        let now = day(2026, 10, 22)
        XCTAssertEqual(range(shifted.period(offset: 0, from: now, calendar: calendar)), "2026-10-20 to 2026-11-25")
        XCTAssertEqual(range(shifted.period(offset: -1, from: now, calendar: calendar)), "2026-09-25 to 2026-10-20")
        XCTAssertEqual(range(shifted.period(offset: 1, from: now, calendar: calendar)), "2026-11-25 to 2026-12-25")
    }

    func testTwoShiftsInOneMonthUseTheEarlierOne() {
        let cycle = PaydayCycle(day: 25, shifts: [day(2026, 10, 22), day(2026, 10, 20)])
        XCTAssertEqual(range(cycle.period(containing: day(2026, 10, 21), calendar: calendar)), "2026-10-20 to 2026-11-25")
    }

    func testSalaryOnTheFirstDayOfThePeriodIsNotEarly() {
        let cycle = PaydayCycle(day: 25, shifts: [day(2026, 9, 25)])
        XCTAssertEqual(range(cycle.period(containing: day(2026, 10, 10), calendar: calendar)), "2026-09-25 to 2026-10-25")
    }

    func testLabelShowsTheShiftedPeriod() {
        XCTAssertEqual(shifted.label(for: day(2026, 10, 22), calendar: calendar).replacingOccurrences(of: "Oct", with: "Okt"), "20 Okt – 24 Nov")
    }
}
