import XCTest
@testable import Saku

final class StatistikAssetsTests: XCTestCase {
    private func wallet(_ id: String, _ type: Account.AccountType, _ balance: Double, archived: Bool = false) -> Account {
        Account(id: id, name: id, type: type, icon: nil, isArchived: archived, isDefault: false,
                openingBalance: balance, currentBalance: balance, creditLimit: type == .credit ? 5_000_000 : nil, dueDate: nil)
    }

    func testTotalSplitsByTypeBiggestFirstAndKeepsCardsAndArchivedOut() throws {
        let a = try XCTUnwrap(PeriodStatistics.assets(accounts: [
            wallet("bca", .bank, 6_000_000), wallet("gopay", .ewallet, 1_000_000), wallet("bibit", .investment, 3_000_000),
            wallet("jago", .bank, 2_000_000), wallet("card", .credit, 4_000_000), wallet("old", .cash, 9_000_000, archived: true)]))
        XCTAssertEqual(a.total, 12_000_000)
        XCTAssertEqual(a.cash, 9_000_000)
        XCTAssertEqual(a.invested, 3_000_000)
        XCTAssertEqual(a.rows.map(\.type), [.bank, .investment, .ewallet])
        XCTAssertEqual(a.rows.map(\.count), [2, 1, 1])
        XCTAssertEqual(a.rows.map(\.share), [8.0 / 12, 3.0 / 12, 1.0 / 12])
    }

    func testNothingPositiveMeansNoCard() {
        XCTAssertNil(PeriodStatistics.assets(accounts: []))
        XCTAssertNil(PeriodStatistics.assets(accounts: [wallet("bca", .bank, 0), wallet("card", .credit, 1_000_000)]))
    }

    func testSpendingCalendarMarksDaysToComeAndTheBusiestDay() {
        let cal = Calendar.current
        let start = cal.date(from: DateComponents(year: 2026, month: 10, day: 5))!   // a Monday
        let c = PeriodStatistics.spendingCalendar(daily: [0, 50_000, 120_000], totalDays: 5, startOfPeriod: start)
        XCTAssertEqual(c.leadingBlanks, 0)
        XCTAssertEqual(c.days.map(\.day), [5, 6, 7, 8, 9])
        XCTAssertEqual(c.days.map(\.amount), [0, 50_000, 120_000, nil, nil])
        XCTAssertEqual(c.total, 170_000)
        XCTAssertEqual(c.peakAmount, 120_000)
        XCTAssertEqual(c.zeroDays, 1)
        XCTAssertEqual(c.days[3].level, 0)
    }
}
