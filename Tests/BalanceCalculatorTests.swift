import XCTest
@testable import Saku

final class BalanceCalculatorTests: XCTestCase {
    func testAppliesIncomeExpenseAndTransferBalances() {
        let cash = Account(
            id: "cash",
            name: "Cash",
            type: .cash,
            icon: nil,
            isArchived: false,
            isDefault: false,
            openingBalance: 100_000,
            creditLimit: nil,
            dueDate: nil
        )
        let bank = Account(
            id: "bank",
            name: "Bank",
            type: .bank,
            icon: nil,
            isArchived: false,
            isDefault: false,
            openingBalance: 250_000,
            creditLimit: nil,
            dueDate: nil
        )

        let transactions = [
            Transaction(
                id: "income-1",
                accountId: "cash",
                counterpartyAccountId: nil,
                categoryId: nil,
                amount: 50_000,
                type: .income,
                description: nil,
                note: nil,
                date: Date(),
                delta: nil
            ),
            Transaction(
                id: "expense-1",
                accountId: "cash",
                counterpartyAccountId: nil,
                categoryId: nil,
                amount: 20_000,
                type: .expense,
                description: nil,
                note: nil,
                date: Date(),
                delta: nil
            ),
            Transaction(
                id: "transfer-1",
                accountId: "cash",
                counterpartyAccountId: "bank",
                categoryId: nil,
                amount: 30_000,
                type: .transfer,
                description: nil,
                note: nil,
                date: Date(),
                delta: nil
            )
        ]

        let updated = BalanceCalculator.applyBalances(to: [cash, bank], from: transactions)

        XCTAssertEqual(updated.first(where: { $0.id == "cash" })?.balance, 100_000)
        XCTAssertEqual(updated.first(where: { $0.id == "bank" })?.balance, 280_000)
        XCTAssertEqual(BalanceCalculator.totalBalance(for: updated), 380_000)
    }
}
