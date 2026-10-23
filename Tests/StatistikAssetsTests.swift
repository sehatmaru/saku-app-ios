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

final class WealthHistoryTests: XCTestCase {
    private let cal = Calendar.current
    private func day(_ d: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: 12))! }
    private func wallet(_ id: String, _ type: Account.AccountType, _ balance: Double) -> Account {
        Account(id: id, name: id, type: type, icon: nil, isArchived: false, isDefault: false,
                openingBalance: 0, currentBalance: balance, creditLimit: nil, dueDate: nil)
    }
    private func txn(_ id: String, _ type: Transaction.TransactionType, _ amount: Double, from: String, to: String? = nil, day d: Int, delta: Double? = nil) -> Transaction {
        Transaction(id: id, accountId: from, counterpartyAccountId: to, categoryId: nil, amount: amount, type: type,
                    description: nil, note: nil, date: day(d), delta: delta)
    }

    func testWorksBackwardsFromTodaysBalancesAndEndsOnThem() {
        // bank 8 jt now, bibit 3 jt now. 10th: salary +10 jt; 12th: deposit 2 jt bank to bibit; 15th: bibit +1 jt value; 16th: lunch -100k
        let accounts = [wallet("bank", .bank, 8_000_000 - 100_000), wallet("bibit", .investment, 3_000_000)]
        let now = day(20)
        let h = WealthHistory(accounts: accounts, transactions: [
            txn("a", .income, 10_000_000, from: "bank", day: 10), txn("b", .transfer, 2_000_000, from: "bank", to: "bibit", day: 12),
            txn("c", .adjustment, 1_000_000, from: "bibit", day: 15, delta: 1_000_000), txn("d", .expense, 100_000, from: "bank", day: 16)], now: now)
        XCTAssertEqual(h.points.map(\.total), [10_000_000, 10_000_000, 11_000_000, 10_900_000, 10_900_000])
        XCTAssertEqual(h.points.map(\.invested), [0, 2_000_000, 3_000_000, 3_000_000, 3_000_000])
        XCTAssertEqual(h.points.last?.date, cal.startOfDay(for: now))
    }

    func testCardsAndArchivedWalletsAreLeftOut() {
        let card = Account(id: "card", name: "card", type: .credit, icon: nil, isArchived: false, isDefault: false,
                           openingBalance: 0, currentBalance: 5_000_000, creditLimit: 9_000_000, dueDate: nil)
        let h = WealthHistory(accounts: [wallet("bank", .bank, 1_000_000), card], transactions: [txn("a", .expense, 500_000, from: "card", day: 10)], now: day(11))
        XCTAssertEqual(h.points.map(\.total), [1_000_000, 1_000_000])
    }

    func testSeriesMapsTotalAndInvestmentsToTheTwoLines() {
        let h = WealthHistory(accounts: [wallet("bank", .bank, 700), wallet("bibit", .investment, 300)],
                              transactions: [txn("a", .income, 100, from: "bank", day: 10)], now: day(12))
        let s = h.series(range: .all, now: day(12))
        XCTAssertEqual(s.points.map(\.value), [1000, 1000])
        XCTAssertEqual(s.points.map(\.capital), [300, 300])
        XCTAssertTrue(s.hasLine)
    }
}
