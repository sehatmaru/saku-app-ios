import XCTest
@testable import Saku

final class BillReminderStoreTests: XCTestCase {
    private var suite: UserDefaults!
    private var store: BillReminderStore!
    private let statement = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        suite = UserDefaults(suiteName: "BillReminderStoreTests")!
        suite.removePersistentDomain(forName: "BillReminderStoreTests")
        store = BillReminderStore(defaults: suite)
    }

    func testSnoozeHoldsUntilItsTimeThenExpires() {
        let now = Date()
        XCTAssertFalse(store.isSnoozed(card: "a", statementDate: statement, now: now))
        store.snooze(card: "a", statementDate: statement, until: now.addingTimeInterval(3600))
        XCTAssertTrue(store.isSnoozed(card: "a", statementDate: statement, now: now))
        XCTAssertFalse(store.isSnoozed(card: "a", statementDate: statement, now: now.addingTimeInterval(7200)))
    }

    func testSnoozeIsPerCardAndPerStatement() {
        let now = Date()
        store.snooze(card: "a", statementDate: statement, until: now.addingTimeInterval(3600))
        XCTAssertFalse(store.isSnoozed(card: "b", statementDate: statement, now: now))
        XCTAssertFalse(store.isSnoozed(card: "a", statementDate: statement.addingTimeInterval(86_400 * 30), now: now))
    }

    func testClearWakesTheReminder() {
        let now = Date()
        store.snooze(card: "a", statementDate: statement, until: now.addingTimeInterval(3600))
        store.clear(card: "a", statementDate: statement)
        XCTAssertFalse(store.isSnoozed(card: "a", statementDate: statement, now: now))
    }

    func testTomorrowMorningIsNineTheNextDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 21))!
        let wake = BillReminderStore.tomorrowMorning(from: evening, calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.month, .day, .hour], from: wake),
                       DateComponents(month: 10, day: 1, hour: 9))
    }
}
