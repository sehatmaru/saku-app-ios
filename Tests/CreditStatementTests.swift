import XCTest
@testable import Saku

/// Card: statement prints on the 20th, due on the 5th, Jakarta time.
final class CreditStatementTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private func card(balance: Double, statementDay: Int? = 20, dueDay: Int = 5) -> Account {
        Account(id: "card", name: "BCA Visa", type: .credit, icon: nil, isArchived: false, isDefault: false,
                openingBalance: 0, currentBalance: balance, creditLimit: 10_000_000, dueDate: String(dueDay),
                statementDay: statementDay)
    }

    private func txn(_ id: String, _ type: Transaction.TransactionType, _ amount: Double, _ on: Date,
                     from: String = "card", to: String? = nil) -> Transaction {
        Transaction(id: id, accountId: from, counterpartyAccountId: to, categoryId: nil, amount: amount,
                    type: type, description: nil, note: nil, date: on, delta: nil)
    }

    private func statement(_ card: Account, _ txns: [Transaction], installments: [CardInstallment] = [],
                           today: Date) -> CreditStatement {
        CreditStatement(card: card, transactions: txns, installments: installments, today: today, calendar: calendar)!
    }

    func testChargesSplitAtTheCutoff() {
        let txns = [txn("a", .expense, 1_000_000, date(2026, 9, 10)),
                    txn("b", .expense, 300_000, date(2026, 9, 25))]
        let s = statement(card(balance: 1_300_000), txns, today: date(2026, 9, 29))

        XCTAssertEqual(s.statementDate, calendar.startOfDay(for: date(2026, 9, 20)))
        XCTAssertEqual(s.dueDate, calendar.startOfDay(for: date(2026, 10, 5)))
        XCTAssertEqual(s.statementAmount, 1_000_000)
        XCTAssertEqual(s.remaining, 1_000_000)
        XCTAssertEqual(s.unbilled, 300_000)
        XCTAssertEqual(s.status, .unpaid)
        XCTAssertEqual(s.minimumDue, 100_000)
        XCTAssertEqual(s.interestIfMinimum, 900_000 * 0.0175, accuracy: 0.01)
    }

    func testChargeOnTheCutoffDayIsBilled() {
        let txns = [txn("a", .expense, 500_000, date(2026, 9, 20, hour: 23))]
        let s = statement(card(balance: 500_000), txns, today: date(2026, 9, 21))
        XCTAssertEqual(s.statementAmount, 500_000)
        XCTAssertEqual(s.unbilled, 0)
    }

    func testPaymentFromBankMakesItPartialThenPaid() {
        let charges = [txn("a", .expense, 1_000_000, date(2026, 9, 10))]
        let partPay = txn("p", .transfer, 400_000, date(2026, 9, 27), from: "bank", to: "card")
        let partial = statement(card(balance: 600_000), charges + [partPay], today: date(2026, 9, 29))
        XCTAssertEqual(partial.status, .partial)
        XCTAssertEqual(partial.remaining, 600_000)
        XCTAssertEqual(partial.statementAmount, 1_000_000)
        XCTAssertEqual(partial.minimumDue, 0)

        let rest = txn("q", .transfer, 600_000, date(2026, 9, 28), from: "bank", to: "card")
        let paid = statement(card(balance: 0), charges + [partPay, rest], today: date(2026, 9, 29))
        XCTAssertEqual(paid.status, .paid)
        XCTAssertEqual(paid.remaining, 0)
    }

    func testUnpaidAfterDueDateIsOverdue() {
        let s = statement(card(balance: 1_000_000), [txn("a", .expense, 1_000_000, date(2026, 9, 10))],
                          today: date(2026, 10, 6))
        XCTAssertEqual(s.status, .overdue)
    }

    func testDaysOverdueCountsFromTheDueDate() {
        let charge = [txn("a", .expense, 1_000_000, date(2026, 9, 10))]
        XCTAssertEqual(statement(card(balance: 1_000_000), charge, today: date(2026, 10, 5)).daysOverdue, 0)
        XCTAssertEqual(statement(card(balance: 1_000_000), charge, today: date(2026, 10, 6)).daysOverdue, 1)
        XCTAssertEqual(statement(card(balance: 1_000_000), charge, today: date(2026, 10, 15)).daysOverdue, 10)
    }

    /// A bill paid from outside Saku (card payment) clears the overdue statement like a transfer would.
    func testCardPaymentSettlesTheStatement() {
        let charge = txn("a", .expense, 1_000_000, date(2026, 9, 10))
        let payment = txn("p", .cardPayment, 1_000_000, date(2026, 10, 5))
        let s = statement(card(balance: 0), [charge, payment], today: date(2026, 10, 6))
        XCTAssertEqual(s.status, .paid)
        XCTAssertEqual(s.daysOverdue, 0)
        XCTAssertEqual(s.paid, 1_000_000)

        let partial = txn("q", .cardPayment, 400_000, date(2026, 10, 5))
        let rest = statement(card(balance: 600_000), [charge, partial], today: date(2026, 10, 6))
        XCTAssertEqual(rest.status, .overdue)
        XCTAssertEqual(rest.remaining, 600_000)
        XCTAssertEqual(rest.paid, 400_000)
    }

    func testInstallmentBillsOnePartPerStatement() {
        // Rp6 jt over 6 months bought 25 Aug: first part on the 20 Sep statement.
        let purchase = txn("tv", .expense, 6_000_000, date(2026, 8, 25))
        let plan = CardInstallment(id: "i", accountId: "card", transactionId: "tv", months: 6)
        let s = statement(card(balance: 6_000_000), [purchase], installments: [plan], today: date(2026, 9, 29))
        XCTAssertEqual(s.statementAmount, 1_000_000)
        XCTAssertEqual(s.unbilled, 5_000_000)
        XCTAssertEqual(CreditStatement.billedParts(of: plan, purchaseDate: purchase.date, card: card(balance: 0),
                                                    today: date(2026, 9, 29), calendar: calendar), 1)
    }

    func testBestDayIsTheDayAfterCutoff() {
        let later = statement(card(balance: 0), [], today: date(2026, 9, 29))
        XCTAssertEqual(later.bestPurchaseDate, calendar.startOfDay(for: date(2026, 10, 21)))
        XCTAssertEqual(later.bestPurchaseDueDate, calendar.startOfDay(for: date(2026, 12, 5)))

        let today = statement(card(balance: 0), [], today: date(2026, 9, 21))
        XCTAssertEqual(today.bestPurchaseDate, calendar.startOfDay(for: date(2026, 9, 21)))
        XCTAssertEqual(today.bestPurchaseDueDate, calendar.startOfDay(for: date(2026, 11, 5)))
    }

    func testCutoffOnThe31stClampsToShortMonths() {
        let s = statement(card(balance: 0, statementDay: 31, dueDay: 15), [], today: date(2027, 3, 5))
        XCTAssertEqual(s.statementDate, calendar.startOfDay(for: date(2027, 2, 28)))
        XCTAssertEqual(s.dueDate, calendar.startOfDay(for: date(2027, 3, 15)))
        XCTAssertEqual(s.nextStatementDate, calendar.startOfDay(for: date(2027, 3, 31)))
    }

    /// A card added on 2 Oct with a starting bill of 1 jt that the bank hasn't printed yet.
    private func newCard(unbilledUntil: String?) -> Account {
        Account(id: "card", name: "Baru", type: .credit, icon: nil, isArchived: false, isDefault: false,
                openingBalance: 1_000_000, currentBalance: 1_000_000, creditLimit: 10_000_000, dueDate: "5",
                statementDay: 20, openingUnbilledUntil: unbilledUntil)
    }

    func testStartingBillNotPrintedYetIsNotDue() {
        let s = statement(newCard(unbilledUntil: "2026-10-20"), [], today: date(2026, 10, 2))
        XCTAssertEqual(s.statementAmount, 0)
        XCTAssertEqual(s.status, .none)
        XCTAssertEqual(s.unbilled, 1_000_000)
    }

    func testStartingBillJoinsTheStatementAfterThatCutoff() {
        let s = statement(newCard(unbilledUntil: "2026-10-20"), [], today: date(2026, 10, 21))
        XCTAssertEqual(s.statementAmount, 1_000_000)
        XCTAssertEqual(s.status, .unpaid)
    }

    func testStartingBillPrintedIsDueRightAway() {
        let s = statement(newCard(unbilledUntil: nil), [], today: date(2026, 10, 2))
        XCTAssertEqual(s.statementAmount, 1_000_000)
        XCTAssertEqual(s.status, .unpaid)
    }

    func testNextCutoffString() {
        XCTAssertEqual(CreditStatement.nextCutoffString(statementDay: 20, today: date(2026, 10, 2), calendar: calendar), "2026-10-20")
        XCTAssertEqual(CreditStatement.nextCutoffString(statementDay: 1, today: date(2026, 10, 2), calendar: calendar), "2026-11-01")
    }

    func testNotACreditCard() {
        let bank = Account(id: "bank", name: "BCA", type: .bank, icon: nil, isArchived: false, isDefault: false,
                           openingBalance: 0, creditLimit: nil, dueDate: nil)
        XCTAssertNil(CreditStatement(card: bank, transactions: [], installments: []))
    }
}
