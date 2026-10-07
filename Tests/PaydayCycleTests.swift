import XCTest
@testable import Saku

final class PaydayCycleTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { calendar.startOfDay(for: date(y, m, d)) }

    func testPaydayFirstIsTheCalendarMonth() {
        let p = PaydayCycle(day: 1).period(containing: date(2026, 9, 29), calendar: calendar)
        XCTAssertEqual(p.start, day(2026, 9, 1))
        XCTAssertEqual(p.end, day(2026, 10, 1))
        XCTAssertEqual(PaydayCycle(day: 1).label(for: date(2026, 9, 29), calendar: calendar), "September")
    }

    func testBeforeAndOnPayday() {
        let cycle = PaydayCycle(day: 25)
        let before = cycle.period(containing: date(2026, 9, 24), calendar: calendar)
        XCTAssertEqual(before.start, day(2026, 8, 25))
        XCTAssertEqual(before.end, day(2026, 9, 25))
        let on = cycle.period(containing: date(2026, 9, 25, hour: 0), calendar: calendar)
        XCTAssertEqual(on.start, day(2026, 9, 25))
        XCTAssertEqual(cycle.label(for: date(2026, 9, 29), calendar: calendar), "25 Sep – 24 Okt")
    }

    func testPaydayPastMonthEndClamps() {
        let cycle = PaydayCycle(day: 31)
        let p = cycle.period(containing: date(2027, 3, 5), calendar: calendar)
        XCTAssertEqual(p.start, day(2027, 2, 28))
        XCTAssertEqual(p.end, day(2027, 3, 31))
    }

    func testDaysAndContains() {
        let cycle = PaydayCycle(day: 25)
        let d = cycle.days(on: date(2026, 9, 29), calendar: calendar)
        XCTAssertEqual(d.total, 30)
        XCTAssertEqual(d.left, 25) // 30 Sep … 24 Okt
        XCTAssertTrue(cycle.contains(date(2026, 10, 24, hour: 23), periodOf: date(2026, 9, 29), calendar: calendar))
        XCTAssertFalse(cycle.contains(date(2026, 10, 25, hour: 0), periodOf: date(2026, 9, 29), calendar: calendar))
        XCTAssertEqual(cycle.period(offset: -1, from: date(2026, 9, 29), calendar: calendar).start, day(2026, 8, 25))
    }

    func testArrangedCategories() {
        func cat(_ id: String, _ name: String) -> Saku.Category {
            Saku.Category(id: id, name: name, icon: nil, color: nil, type: .expense, systemKey: nil)
        }
        let cats = [cat("a", "Makan"), cat("b", "Bensin"), cat("c", "Kopi")]
        let prefs = [CategoryPreference(categoryId: "c", isHidden: false, sortOrder: 0),
                     CategoryPreference(categoryId: "a", isHidden: true, sortOrder: nil)]
        let result = cats.arranged(by: prefs)
        XCTAssertEqual(result.shown.map { $0.id }, ["c", "b"])
        XCTAssertEqual(result.hidden.map { $0.id }, ["a"])
    }

    /// Old payday 25, new payday 1 from 25 Nov: the running period finishes under 25 and the next is a short stub.
    func testScheduledChangeKeepsRunningAndPastPeriods() {
        let cycle = PaydayCycle(day: 25, schedule: [
            PaydayEntry(day: 25, from: day(1970, 1, 1)),
            PaydayEntry(day: 1, from: day(2026, 11, 25)),
        ])
        let running = cycle.period(containing: date(2026, 10, 30), calendar: calendar)
        XCTAssertEqual(running.start, day(2026, 10, 25))
        XCTAssertEqual(running.end, day(2026, 11, 25))
        let stub = cycle.period(containing: date(2026, 11, 27), calendar: calendar)
        XCTAssertEqual(stub.start, day(2026, 11, 25))
        XCTAssertEqual(stub.end, day(2026, 12, 1))
        XCTAssertEqual(cycle.period(containing: date(2026, 12, 1), calendar: calendar).start, day(2026, 12, 1))
        XCTAssertEqual(cycle.period(offset: -1, from: date(2026, 11, 27), calendar: calendar), running)
    }
}
