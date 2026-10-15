import XCTest
@testable import Saku

/// Card: statement prints on the 20th, due on the 5th, Jakarta time.
final class RunningInstallmentsTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private let card = Account(id: "card", name: "BCA Visa", type: .credit, icon: nil, isArchived: false, isDefault: false,
                               openingBalance: 0, currentBalance: 6_000_000, creditLimit: 10_000_000, dueDate: "5", statementDay: 20)

    private func purchase(on day: Date, amount: Double = 6_000_000) -> Transaction {
        Transaction(id: "tv", accountId: "card", counterpartyAccountId: nil, categoryId: nil, amount: amount, type: .expense,
                    description: "TV", note: nil, date: day, delta: nil)
    }

    private func run(_ purchase: Transaction, months: Int = 6, periodEnd: Date) -> [RunningInstallment] {
        RunningInstallments.compute(installments: [CardInstallment(id: "i", accountId: "card", transactionId: "tv", months: months)],
                                    transactions: [purchase], accounts: [card], periodEnd: periodEnd, calendar: calendar)
    }

    func testNewPurchaseShowsInItsPeriodWithWhenBillingStarts() {
        let items = run(purchase(on: date(2026, 10, 10)), periodEnd: date(2026, 10, 14))
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].monthly, 1_000_000)
        XCTAssertEqual(items[0].remainingParts, items[0].months - items[0].billedParts)
    }

    func testStillRunningInALaterPeriod() {
        let items = run(purchase(on: date(2026, 8, 10)), periodEnd: date(2026, 10, 31))
        XCTAssertEqual(items.count, 1)
        XCTAssertGreaterThan(items[0].billedParts, 0)
        XCTAssertNil(items[0].firstBillingDate)
    }

    func testSettledInstallmentDisappears() {
        XCTAssertTrue(run(purchase(on: date(2026, 1, 10)), months: 3, periodEnd: date(2026, 10, 31)).isEmpty)
    }

    func testPurchaseAfterThePeriodIsNotThereYet() {
        XCTAssertTrue(run(purchase(on: date(2026, 11, 2)), periodEnd: date(2026, 10, 31)).isEmpty)
    }

    func testTwoInstallmentsAreSorted() {
        let older = purchase(on: date(2026, 9, 1))
        let newer = Transaction(id: "hp", accountId: "card", counterpartyAccountId: nil, categoryId: nil, amount: 3_000_000, type: .expense,
                                description: "HP", note: nil, date: date(2026, 10, 12), delta: nil)
        let items = RunningInstallments.compute(
            installments: [CardInstallment(id: "i", accountId: "card", transactionId: "tv", months: 6),
                           CardInstallment(id: "j", accountId: "card", transactionId: "hp", months: 3)],
            transactions: [older, newer], accounts: [card], periodEnd: date(2026, 10, 14), calendar: calendar)
        XCTAssertEqual(items.map(\.id), ["j", "i"])
        XCTAssertEqual(items.reduce(0) { $0 + $1.monthly }, 2_000_000)
    }
}
