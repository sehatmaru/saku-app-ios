import XCTest
@testable import Saku

/// Enhancement 1 - Statistik Periode: the numbers behind the page.
@MainActor
final class PeriodStatisticsTests: XCTestCase {
    override func setUp() {
        UserDefaults.standard.set("id", forKey: "appLanguage")
    }

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return c
    }()
    private let cycle = PaydayCycle(day: 25)

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }

    private let categories = [
        Saku.Category(id: "makan", name: "Makan", icon: nil, color: nil, type: .expense, systemKey: nil),
        Saku.Category(id: "trans", name: "Transport", icon: nil, color: nil, type: .expense, systemKey: nil),
        Saku.Category(id: "gaji", name: "Gaji", icon: nil, color: nil, type: .income, systemKey: nil),
    ]
    private let accounts = [
        Account(id: "bca", name: "BCA", type: .bank, icon: nil, isArchived: false, isDefault: true, openingBalance: 0, creditLimit: nil, dueDate: nil),
        Account(id: "gopay", name: "GoPay", type: .ewallet, icon: nil, isArchived: false, isDefault: false, openingBalance: 0, creditLimit: nil, dueDate: nil),
    ]

    private var counter = 0
    private func txn(_ type: Transaction.TransactionType, _ amount: Double, _ category: String?, _ on: Date, account: String = "bca", name: String? = nil) -> Transaction {
        counter += 1
        return Transaction(id: "t\(counter)", accountId: account, counterpartyAccountId: nil, categoryId: category, amount: amount, type: type,
                           description: name, note: nil, date: on, delta: nil)
    }

    /// Aug 25 - Sep 24 (earlier) and Sep 25 - Oct 24 (shown). Today is Oct 21: 27 of 30 days have passed.
    private func fixture() -> (transactions: [Transaction], interval: DateInterval, now: Date) {
        let interval = DateInterval(start: date(2026, 9, 25), end: date(2026, 10, 25))
        let txns = [
            txn(.income, 12_000_000, "gaji", date(2026, 8, 25)), txn(.expense, 1_000_000, "makan", date(2026, 9, 1)),
            txn(.expense, 400_000, "trans", date(2026, 9, 2)),
            txn(.income, 12_000_000, "gaji", date(2026, 9, 25)),
            txn(.expense, 500_000, "makan", date(2026, 9, 25), name: "Makan siang"),       // Fri
            txn(.expense, 1_500_000, "makan", date(2026, 10, 2), account: "gopay", name: "Belanja"), // Fri, biggest
            txn(.expense, 300_000, "trans", date(2026, 10, 5)),
            txn(.expense, 200_000, "makan", date(2026, 10, 6)),
        ]
        return (txns, interval, date(2026, 10, 21))
    }

    private func make(_ f: (transactions: [Transaction], interval: DateInterval, now: Date), budgets: [ReportModel.BudgetLine] = []) -> PeriodStatistics.Result {
        PeriodStatistics.make(transactions: f.transactions, categories: categories, accounts: accounts, budgetLines: budgets,
                              cycle: cycle, interval: f.interval, now: f.now, calendar: calendar)
    }

    // US1
    func testSummaryFigures() {
        let r = make(fixture())
        XCTAssertEqual(r.summary.income, 12_000_000)
        XCTAssertEqual(r.summary.expense, 2_500_000)
        XCTAssertEqual(r.summary.net, 9_500_000)
        XCTAssertEqual(try XCTUnwrap(r.summary.savingsRate), 9_500_000 / 12_000_000, accuracy: 0.0001)
        XCTAssertEqual(r.summary.transactions, 5)
        XCTAssertEqual(r.elapsedDays, 27)
        XCTAssertEqual(r.summary.perDay, 2_500_000 / 27, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(r.summary.perTransaction), 625_000, accuracy: 0.01)
        XCTAssertEqual(r.summary.remaining.count, 27)
        XCTAssertEqual(r.summary.remaining.last, 9_500_000)
    }

    func testProjectionIsPaceTimesPeriodLengthOnceThereIsHistory() throws {
        let r = make(fixture())
        XCTAssertEqual(try XCTUnwrap(r.summary.projection), 2_500_000 / 27 * 30, accuracy: 0.01)
        XCTAssertEqual(r.summary.projectionNote, .fromAverage(r.summary.perDay))
    }

    // TC 7
    func testNegativeNet() {
        var f = fixture()
        f.transactions.append(txn(.expense, 20_000_000, "makan", date(2026, 10, 10)))
        XCTAssertLessThan(make(f).summary.net, 0)
    }

    // US10 / K10
    func testFirstPeriodHasNoProjectionAndNoComparison() {
        var f = fixture()
        f.transactions = f.transactions.filter { $0.date >= f.interval.start }
        let r = make(f)
        XCTAssertTrue(r.isFirstPeriod)
        XCTAssertNil(r.summary.projection)
        XCTAssertEqual(r.summary.projectionNote, .needsHistory)
        XCTAssertNil(r.highlights.comparison)
        XCTAssertEqual(r.trend.points.count, 1)
        XCTAssertNil(r.trend.expenseChange)
    }

    // TC 2
    func testPeriodWithoutTransactionsIsEmpty() {
        let f = fixture()
        let empty = DateInterval(start: date(2026, 10, 25), end: date(2026, 11, 25))
        let r = PeriodStatistics.make(transactions: f.transactions, categories: categories, accounts: accounts, budgetLines: [],
                                      cycle: cycle, interval: empty, now: date(2026, 10, 26), calendar: calendar)
        XCTAssertTrue(r.isEmpty)
    }

    func testFinishedPeriodCountsAllDaysAndHasNoProjection() {
        let f = fixture()
        let past = DateInterval(start: date(2026, 8, 25), end: date(2026, 9, 25))
        let r = PeriodStatistics.make(transactions: f.transactions, categories: categories, accounts: accounts, budgetLines: [],
                                      cycle: cycle, interval: past, now: f.now, calendar: calendar)
        XCTAssertFalse(r.isCurrent)
        XCTAssertEqual(r.elapsedDays, 31)
        XCTAssertNil(r.summary.projection)
        XCTAssertEqual(r.summary.projectionNote, .finished)
    }

    // US2
    func testCalendarHeat() throws {
        let r = make(fixture())
        XCTAssertEqual(r.calendar.leadingBlanks, 4, "25 Sep 2026 is a Friday and Monday comes first")
        XCTAssertEqual(r.calendar.days.count, 30)
        XCTAssertEqual(r.calendar.total, 2_500_000)
        XCTAssertEqual(r.calendar.peakAmount, 1_500_000)
        XCTAssertEqual(r.calendar.peakDate, calendar.startOfDay(for: date(2026, 10, 2)))
        XCTAssertEqual(r.calendar.zeroDays, 27 - 4, "27 days passed, spending on 4 of them")
        // spending days: 200k, 300k, 500k, 1,5jt -> quartiles 200k / 300k / 500k
        XCTAssertEqual(r.calendar.days[0].level, 3, "500k")
        XCTAssertEqual(r.calendar.days[7].level, 4, "the peak day")
        XCTAssertEqual(r.calendar.days[10].level, 2, "300k")
        XCTAssertEqual(r.calendar.days[11].level, 1, "200k")
        XCTAssertEqual(r.calendar.days[1].level, 0, "a day without spending")
        XCTAssertNil(r.calendar.days[29].amount, "days to come have no amount")
    }

    /// One huge day must not flatten the others into the palest shade (reported on a real account: 4jt against 100-300k).
    func testAnOutlierDoesNotMakeEveryOtherDayLookTheSame() {
        var f = fixture()
        f.transactions = [txn(.income, 12_000_000, "gaji", date(2026, 9, 25))]
        let amounts: [Double] = [100_000, 150_000, 200_000, 250_000, 300_000, 120_000, 180_000, 4_000_000]
        for (offset, amount) in amounts.enumerated() {
            f.transactions.append(txn(.expense, amount, "makan", date(2026, 9, 26 + offset)))
        }
        let levels = Set(make(f).calendar.days.compactMap { $0.amount }.enumerated().filter { $0.element > 0 }.map { make(f).calendar.days[$0.offset].level })
        XCTAssertEqual(levels, [1, 2, 3, 4])
        XCTAssertEqual(make(f).calendar.days[8].level, 4, "the 4jt day is the darkest")
    }

    func testEqualSpendingDaysShareTheMiddleShade() {
        var f = fixture()
        f.transactions = [txn(.income, 1_000_000, "gaji", date(2026, 9, 25)), txn(.expense, 100_000, "makan", date(2026, 9, 26)),
                          txn(.expense, 100_000, "makan", date(2026, 9, 27))]
        XCTAssertEqual(make(f).calendar.days.filter { ($0.amount ?? 0) > 0 }.map(\.level), [3, 3])
    }

    // US3, TC 4
    func testTrendCoversTheAvailablePeriodsAndMarksTheRunningOne() throws {
        let r = make(fixture())
        XCTAssertEqual(r.trend.points.count, 2, "only two periods hold records")
        XCTAssertTrue(r.trend.points.last?.isCurrent == true)
        XCTAssertEqual(r.trend.points[0].expense, 1_400_000)
        // the running period plots its projection
        XCTAssertEqual(r.trend.points[1].expense, try XCTUnwrap(r.summary.projection), accuracy: 0.01)
        XCTAssertNotNil(r.trend.expenseChange)
        XCTAssertEqual(r.trend.averageIncome, 12_000_000)
    }

    // US4
    func testExpenseSlicesSharesAndChange() throws {
        let r = make(fixture())
        XCTAssertEqual(r.expenseSlices.map(\.name), ["Makan", "Transport"])
        XCTAssertEqual(r.expenseSlices[0].amount, 2_200_000)
        XCTAssertEqual(r.expenseSlices.reduce(0) { $0 + $1.share }, 1, accuracy: 0.0001)
        // Makan: 2,2jt now against 1jt in the same stretch of the period before
        XCTAssertEqual(try XCTUnwrap(r.expenseSlices[0].change), 1.2, accuracy: 0.0001)
    }

    func testMoreThanFourCategoriesBecomeLainnya() {
        var f = fixture()
        let many = (1...6).map { Saku.Category(id: "c\($0)", name: "K\($0)", icon: nil, color: nil, type: .expense, systemKey: nil) }
        f.transactions += many.enumerated().map { txn(.expense, Double(($0.offset + 1) * 100_000), $0.element.id, date(2026, 10, 3)) }
        let r = PeriodStatistics.make(transactions: f.transactions, categories: categories + many, accounts: accounts, budgetLines: [],
                                      cycle: cycle, interval: f.interval, now: f.now, calendar: calendar)
        XCTAssertEqual(r.expenseSlices.count, 5)
        XCTAssertEqual(r.expenseSlices.last?.name, "Lainnya")
        XCTAssertEqual(r.expenseSlices.reduce(0) { $0 + $1.share }, 1, accuracy: 0.0001)
    }

    // US5
    func testIncomeSlices() {
        let r = make(fixture())
        XCTAssertEqual(r.incomeSlices.map(\.name), ["Gaji"])
        XCTAssertEqual(r.incomeSlices[0].share, 1)
    }

    // US6, TC 3
    func testWalletsAndTheMostUsedOne() throws {
        let r = make(fixture())
        XCTAssertEqual(r.wallets.map(\.name), ["GoPay", "BCA"], "sorted by expense")
        XCTAssertEqual(r.wallets[0].expense, 1_500_000)
        XCTAssertEqual(r.wallets[1].income, 12_000_000)
        let top = try XCTUnwrap(r.mostUsedWallet)
        XCTAssertEqual(top.name, "BCA")
        XCTAssertEqual(top.count, 4)
        XCTAssertEqual(make((transactions: [], interval: fixture().interval, now: fixture().now)).wallets.count, 0, "no wallets used: no error")
    }

    // US7
    func testWeekdayAveragesAndStreak() throws {
        let r = make(fixture())
        // Fridays in the 27 elapsed days: Sep 25, Oct 2, Oct 9, Oct 16 -> (500k + 1,5jt) / 4
        XCTAssertEqual(r.time.weekdays[4].average, 500_000, accuracy: 0.01)
        XCTAssertEqual(r.time.peak, 4)
        XCTAssertEqual(r.time.topDays.map(\.amount), [1_500_000, 500_000, 300_000])
        XCTAssertEqual(r.time.longestZeroStreak, 15, "Oct 7 to Oct 21")
    }

    // US8, TC 3
    func testBudgetsAreRankedByUsageAndTheRemainderIsTotalled() {
        let lines = [ReportModel.BudgetLine(name: "Makan", spent: 3_150_000, amount: 3_000_000, isProvisional: false),
                     ReportModel.BudgetLine(name: "Transport", spent: 400_000, amount: 1_000_000, isProvisional: false),
                     ReportModel.BudgetLine(name: "Hiburan", spent: 900_000, amount: 1_000_000, isProvisional: false),
                     ReportModel.BudgetLine(name: "Belanja", spent: 100_000, amount: 2_000_000, isProvisional: false)]
        let r = make(fixture(), budgets: lines)
        XCTAssertEqual(r.budgets.map(\.name), ["Makan", "Hiburan", "Transport"])
        XCTAssertEqual(r.budgetRemaining, 7_000_000 - 4_550_000)
        XCTAssertTrue(r.hasBudget)
        XCTAssertFalse(make(fixture()).hasBudget)
    }

    // US9
    func testHighlights() throws {
        let r = make(fixture())
        XCTAssertEqual(r.highlights.biggest.map(\.amount), [1_500_000, 500_000, 300_000, 200_000])
        XCTAssertEqual(r.highlights.biggest[0].name, "Belanja")
        XCTAssertEqual(r.highlights.biggest[1].name, "Makan siang")
        XCTAssertEqual(r.highlights.biggest[2].name, "Transport", "no name: the category")
        XCTAssertEqual(r.highlights.frequent?.name, "Makan")
        XCTAssertEqual(r.highlights.frequent?.count, 3)
        let comparison = try XCTUnwrap(r.highlights.comparison)
        XCTAssertEqual(comparison.now, 2_500_000)
        XCTAssertEqual(comparison.previous, 1_400_000)
        XCTAssertEqual(try XCTUnwrap(comparison.change), 2_500_000 / 1_400_000 - 1, accuracy: 0.0001)
    }

    // TC 5
    func testAnotherPaydayMovesThePeriod() {
        let f = fixture()
        let tenth = PaydayCycle(day: 10)
        let period = tenth.period(containing: f.now, calendar: calendar)
        let r = PeriodStatistics.make(transactions: f.transactions, categories: categories, accounts: accounts, budgetLines: [],
                                      cycle: tenth, interval: period, now: f.now, calendar: calendar)
        XCTAssertEqual(r.interval.start, calendar.startOfDay(for: date(2026, 10, 10)))
        XCTAssertTrue(r.isEmpty, "no spending since Oct 10")
    }

    // TC 8
    func testNetMatchesTheFlowOnBeranda() {
        let f = fixture()
        let rows = f.transactions.filter { $0.date >= f.interval.start && $0.date < f.interval.end }
        let income = rows.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        let expense = rows.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(make(f).summary.net, income - expense)
    }
}
