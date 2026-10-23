import XCTest
@testable import Saku

final class InvestmentSeriesTests: XCTestCase {
    private let cal = Calendar.current
    private func day(_ m: Int, _ d: Int, year: Int = 2026) -> Date { cal.date(from: DateComponents(year: year, month: m, day: d, hour: 12))! }
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12))!

    private func bibit(opening: Double = 0) -> Account {
        Account(id: "bibit", name: "Bibit", type: .investment, icon: nil, isArchived: false, isDefault: false,
                openingBalance: opening, currentBalance: 0, creditLimit: nil, dueDate: nil)
    }
    private func deposit(_ amount: Double, _ date: Date) -> Transaction {
        Transaction(id: "d\(date.timeIntervalSince1970)", accountId: "bca", counterpartyAccountId: "bibit", categoryId: nil, amount: amount,
                    type: .transfer, description: nil, note: nil, date: date, delta: nil)
    }
    private func withdraw(_ amount: Double, _ date: Date) -> Transaction {
        Transaction(id: "w\(date.timeIntervalSince1970)", accountId: "bibit", counterpartyAccountId: "bca", categoryId: nil, amount: amount,
                    type: .transfer, description: nil, note: nil, date: date, delta: nil)
    }
    private func update(_ delta: Double, _ date: Date) -> Transaction {
        Transaction(id: "u\(date.timeIntervalSince1970)", accountId: "bibit", counterpartyAccountId: nil, categoryId: nil, amount: abs(delta),
                    type: .adjustment, description: nil, note: nil, date: date, delta: delta)
    }

    func testPointsFollowValueAndCapital() {
        let s = InvestmentSeries(account: bibit(), transactions: [deposit(500_000, day(9, 1)), update(20_000, day(9, 10)), withdraw(200_000, day(9, 20))],
                                 range: .all, now: now)
        XCTAssertEqual(s.points.map(\.value), [500_000, 520_000, 320_000])
        XCTAssertEqual(s.points.map(\.capital), [500_000, 500_000, 300_000])
        XCTAssertTrue(s.hasLine)
    }

    func testOneChangeIsNotEnoughForALine() {
        let s = InvestmentSeries(account: bibit(), transactions: [deposit(500_000, day(9, 1))], range: .all, now: now)
        XCTAssertEqual(s.points.count, 1)
        XCTAssertFalse(s.hasLine)
    }

    func testNoChangesMeansNoPoints() {
        let s = InvestmentSeries(account: bibit(), transactions: [], range: .all, now: now)
        XCTAssertTrue(s.points.isEmpty)
        XCTAssertFalse(s.hasLine)
    }

    func testRangeStartsFromTheStateBeforeIt() {
        // 3 months before 20 Oct is 20 Jul: the June deposit is out, and the line starts with its state
        let txns = [deposit(500_000, day(6, 1)), update(50_000, day(9, 1))]
        let s = InvestmentSeries(account: bibit(), transactions: txns, range: .months3, now: now)
        XCTAssertEqual(s.points.count, 2)
        XCTAssertFalse(s.points[0].isChange)
        XCTAssertEqual(s.points[0].value, 500_000)
        XCTAssertEqual(s.points[1].value, 550_000)
        XCTAssertTrue(s.hasLine)
    }

    func testChangesOutsideTheRangeAreLeftOut() {
        let s = InvestmentSeries(account: bibit(), transactions: [deposit(500_000, day(1, 5))], range: .months3, now: now)
        XCTAssertTrue(s.points.isEmpty)
    }

    func testBoundsHaveRoomEvenWhenFlat() {
        let s = InvestmentSeries(points: [.init(date: now, value: 100, capital: 100, isChange: true), .init(date: now, value: 100, capital: 100, isChange: true)])
        XCTAssertLessThan(s.valueBounds.lowerBound, 100)
        XCTAssertGreaterThan(s.valueBounds.upperBound, 100)
    }

    private func wallet(_ id: String, _ balance: Double, archived: Bool = false, type: Account.AccountType = .investment) -> Account {
        Account(id: id, name: id, type: type, icon: nil, isArchived: archived, isDefault: false,
                openingBalance: balance, currentBalance: balance, creditLimit: nil, dueDate: nil)
    }

    func testAllocationNeedsTwoActiveInvestmentWallets() {
        XCTAssertNil(InvestmentAllocation(accounts: [wallet("a", 100)]))
        XCTAssertNil(InvestmentAllocation(accounts: [wallet("a", 100), wallet("b", 50, archived: true)]))
        XCTAssertNil(InvestmentAllocation(accounts: [wallet("a", 100), wallet("bca", 50, type: .bank)]))
        XCTAssertNil(InvestmentAllocation(accounts: [wallet("a", 0), wallet("b", 0)]))
    }

    func testAllocationSharesAddUpAndBiggestComesFirst() throws {
        let allocation = try XCTUnwrap(InvestmentAllocation(accounts: [wallet("small", 25), wallet("big", 75), wallet("gone", 500, archived: true)]))
        XCTAssertEqual(allocation.slices.map(\.id), ["big", "small"])
        XCTAssertEqual(allocation.slices.map(\.fraction), [0.75, 0.25])
        XCTAssertEqual(allocation.total, 100)
    }
}

final class InvestmentReminderTests: XCTestCase {
    private let cal = Calendar.current
    private func at(_ m: Int, _ d: Int, _ h: Int = 12) -> Date { cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: h))! }

    func testOffNeverFires() {
        XCTAssertNil(InvestmentReminder.off.nextFire(lastUpdated: at(10, 1), now: at(10, 2)))
    }

    func testWeeklyFiresAtNineOneWeekAfterTheUpdate() {
        let fire = InvestmentReminder.weekly.nextFire(lastUpdated: at(10, 1), now: at(10, 2))
        XCTAssertEqual(fire, at(10, 8, 9))
    }

    func testMonthlyFollowsTheCalendarMonth() {
        XCTAssertEqual(InvestmentReminder.monthly.nextFire(lastUpdated: at(9, 30), now: at(10, 1)), at(10, 30, 9))
    }

    func testBiweeklyIsFourteenDays() {
        XCTAssertEqual(InvestmentReminder.biweekly.nextFire(lastUpdated: at(10, 1), now: at(10, 2)), at(10, 15, 9))
    }

    func testAStaleValueFiresAtTheComingNine() {
        // last updated long ago: tomorrow 09:00 when today's 09:00 has passed, today's when it has not
        XCTAssertEqual(InvestmentReminder.weekly.nextFire(lastUpdated: at(1, 1), now: at(10, 20, 12)), at(10, 21, 9))
        XCTAssertEqual(InvestmentReminder.weekly.nextFire(lastUpdated: at(1, 1), now: at(10, 20, 7)), at(10, 20, 9))
    }

    func testNeverUpdatedCountsFromNow() {
        XCTAssertEqual(InvestmentReminder.weekly.nextFire(lastUpdated: nil, now: at(10, 1)), at(10, 8, 9))
    }

    func testStoreKeepsOneSettingPerWalletAndClears() {
        let defaults = UserDefaults(suiteName: "InvestmentReminderTests")!
        defaults.removePersistentDomain(forName: "InvestmentReminderTests")
        let store = InvestmentReminderStore(defaults: defaults)
        XCTAssertEqual(store.interval(for: "a"), .off)
        store.set(.weekly, for: "a"); store.set(.monthly, for: "b")
        XCTAssertEqual(store.interval(for: "a"), .weekly)
        XCTAssertEqual(store.interval(for: "b"), .monthly)
        store.set(.off, for: "a")
        XCTAssertEqual(store.interval(for: "a"), .off)
        store.wasOffered = true
        store.clearAll()
        XCTAssertEqual(store.interval(for: "b"), .off)
        XCTAssertFalse(store.wasOffered)
    }
}
