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

    // MARK: - Ganti tanggal di tengah periode (PRD Ganti Tanggal Periode, TC1-TC10)

    private func periods(_ cycle: PaydayCycle, from start: Date, count: Int) -> [(Date, Date)] {
        var out: [(Date, Date)] = []
        var probe = start
        for _ in 0..<count {
            let p = cycle.period(containing: probe, calendar: calendar)
            out.append((p.start, p.end))
            probe = p.end
        }
        return out
    }

    private func change(day newDay: Int, from: Date, extendsFrom: Date? = nil, shifts: [Date] = []) -> PaydayCycle {
        PaydayCycle(day: newDay, schedule: [
            PaydayEntry(day: 30, from: day(1970, 1, 1)),
            PaydayEntry(day: newDay, from: from, extendsFrom: extendsFrom),
        ], shifts: shifts)
    }

    private func assertPeriods(_ cycle: PaydayCycle, _ expected: [(Date, Date)], file: StaticString = #filePath, line: UInt = #line) {
        let got = periods(cycle, from: day(2026, 10, 30), count: expected.count)
        XCTAssertEqual(got.map(\.0), expected.map(\.0), file: file, line: line)
        XCTAssertEqual(got.map(\.1), expected.map(\.1), file: file, line: line)
    }

    func testTC1StartOnTheNewDate() {
        assertPeriods(change(day: 25, from: day(2026, 11, 25)),
                      [(day(2026, 10, 30), day(2026, 11, 25)), (day(2026, 11, 25), day(2026, 12, 25)), (day(2026, 12, 25), day(2027, 1, 25))])
    }

    func testTC2AfterThisPeriod() {
        assertPeriods(change(day: 25, from: day(2026, 11, 30)),
                      [(day(2026, 10, 30), day(2026, 11, 30)), (day(2026, 11, 30), day(2026, 12, 25)), (day(2026, 12, 25), day(2027, 1, 25))])
    }

    func testTC3ExtendTheRunningPeriod() {
        assertPeriods(change(day: 20, from: day(2026, 12, 20), extendsFrom: day(2026, 10, 30)),
                      [(day(2026, 10, 30), day(2026, 12, 20)), (day(2026, 12, 20), day(2027, 1, 20))])
        // a day inside the stretch that the old boundary used to cut
        XCTAssertEqual(change(day: 20, from: day(2026, 12, 20), extendsFrom: day(2026, 10, 30))
            .period(containing: date(2026, 12, 5), calendar: calendar).start, day(2026, 10, 30))
    }

    func testTC4ShortPeriodFirst() {
        assertPeriods(change(day: 20, from: day(2026, 11, 30)),
                      [(day(2026, 10, 30), day(2026, 11, 30)), (day(2026, 11, 30), day(2026, 12, 20)), (day(2026, 12, 20), day(2027, 1, 20))])
    }

    func testTC5StartToday() {
        assertPeriods(change(day: 20, from: day(2026, 11, 24)),
                      [(day(2026, 10, 30), day(2026, 11, 24)), (day(2026, 11, 24), day(2026, 12, 20)), (day(2026, 12, 20), day(2027, 1, 20))])
    }

    func testTC8CancelGoesBackToTheOldPeriods() {
        let cycle = PaydayCycle(day: 30, schedule: [PaydayEntry(day: 30, from: day(1970, 1, 1))])
        assertPeriods(cycle, [(day(2026, 10, 30), day(2026, 11, 30)), (day(2026, 11, 30), day(2026, 12, 30))])
    }

    func testTC9MonthEndClipping() {
        // payday 31 from 28 Feb: the first period runs 28 Feb - 30 Mar, then the 31st of a 31-day month
        let cycle = PaydayCycle(day: 31, schedule: [
            PaydayEntry(day: 20, from: day(1970, 1, 1)),
            PaydayEntry(day: 31, from: day(2027, 2, 28)),
        ])
        let p = cycle.period(containing: date(2027, 3, 5), calendar: calendar)
        XCTAssertEqual(p.start, day(2027, 2, 28))
        XCTAssertEqual(p.end, day(2027, 3, 31))
    }

    func testTC10ShiftNeitherEmptiesNorOverlapsPeriods() {
        // early salary on 20 Nov moves the 30 Nov boundary; a payday change after it must leave a clean chain
        for cycle in [change(day: 25, from: day(2026, 11, 25), shifts: [day(2026, 11, 20)]),
                      change(day: 20, from: day(2026, 12, 20), extendsFrom: day(2026, 10, 30), shifts: [day(2026, 11, 20)]),
                      change(day: 20, from: day(2026, 11, 24), shifts: [day(2026, 11, 20)])] {
            let chain = periods(cycle, from: day(2026, 10, 30), count: 5)
            for (a, b) in zip(chain, chain.dropFirst()) {
                XCTAssertGreaterThan(a.1, a.0)
                XCTAssertEqual(a.1, b.0)
            }
        }
    }
}
