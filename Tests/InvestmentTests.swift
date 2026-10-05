import XCTest
@testable import Saku

final class InvestmentTests: XCTestCase {
    private func wallet(_ id: String, _ type: Account.AccountType, balance: Double, opening: Double? = nil, archived: Bool = false) -> Account {
        Account(id: id, name: id, type: type, icon: nil, isArchived: archived, isDefault: false,
                openingBalance: opening ?? balance, currentBalance: balance, creditLimit: nil, dueDate: nil)
    }

    private func txn(_ type: Transaction.TransactionType, _ amount: Double, from: String, to: String? = nil, day: Int = 1) -> Transaction {
        Transaction(id: "\(type.rawValue)-\(from)-\(day)", accountId: from, counterpartyAccountId: to, categoryId: nil, amount: amount,
                    type: type, description: nil, note: nil,
                    date: Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12))!, delta: nil)
    }

    // TC13: BCA 1.500.000, Bibit 520.000, no card.
    func testWealthKeepsCashAndAssetsApart() {
        let w = WealthSummary(accounts: [wallet("bca", .bank, balance: 1_500_000), wallet("bibit", .investment, balance: 520_000)])
        XCTAssertEqual(w.cash, 1_500_000)
        XCTAssertEqual(w.assets, 520_000)
        XCTAssertEqual(w.total, 2_020_000)
    }

    // TC2: depositing 500.000 moves cash into assets; wealth is unchanged.
    func testDepositDoesNotChangeWealth() {
        let before = WealthSummary(accounts: [wallet("bca", .bank, balance: 2_000_000), wallet("bibit", .investment, balance: 0)])
        let after = WealthSummary(accounts: [wallet("bca", .bank, balance: 1_500_000), wallet("bibit", .investment, balance: 500_000)])
        XCTAssertEqual(before.total, 2_000_000)
        XCTAssertEqual(after.total, 2_000_000)
        XCTAssertEqual(after.cash, 1_500_000)
    }

    func testArchivedInvestmentLeavesTheTotals() {
        let w = WealthSummary(accounts: [wallet("bca", .bank, balance: 1_500_000), wallet("bibit", .investment, balance: 520_000, archived: true)])
        XCTAssertEqual(w.assets, 0)
        XCTAssertEqual(w.total, 1_500_000)
    }

    func testCardsStayOutOfBothTotals() {
        let card = Account(id: "card", name: "card", type: .credit, icon: nil, isArchived: false, isDefault: false,
                           openingBalance: 3_000_000, currentBalance: 3_000_000, creditLimit: 10_000_000, dueDate: "5")
        let w = WealthSummary(accounts: [wallet("bca", .bank, balance: 1_000_000), card])
        XCTAssertEqual(w.total, 1_000_000)
    }

    // TC7: capital 500.000, value updated to 520.000.
    func testGainAndPercentAfterAValueUpdate() {
        let bibit = wallet("bibit", .investment, balance: 520_000, opening: 0)
        let s = InvestmentSummary(account: bibit, transactions: [txn(.transfer, 500_000, from: "bca", to: "bibit"),
                                                                 txn(.adjustment, 20_000, from: "bibit", day: 3)])
        XCTAssertEqual(s.capital, 500_000)
        XCTAssertEqual(s.gain, 20_000)
        XCTAssertEqual(try XCTUnwrap(s.percent), 0.04, accuracy: 0.0001)
        XCTAssertNotNil(s.lastUpdated)
    }

    // TC5: withdrawing 200.000 lowers the capital too.
    func testWithdrawalLowersCapital() {
        let bibit = wallet("bibit", .investment, balance: 320_000, opening: 0)
        let s = InvestmentSummary(account: bibit, transactions: [txn(.transfer, 500_000, from: "bca", to: "bibit"),
                                                                 txn(.adjustment, 20_000, from: "bibit", day: 2),
                                                                 txn(.transfer, 200_000, from: "bibit", to: "bca", day: 3)])
        XCTAssertEqual(s.capital, 300_000)
        XCTAssertEqual(s.gain, 20_000)
    }

    // TC8: worth nothing is allowed, and it is a 100% loss.
    func testValueZeroIsAFullLoss() {
        let bibit = wallet("bibit", .investment, balance: 0, opening: 0)
        let s = InvestmentSummary(account: bibit, transactions: [txn(.transfer, 500_000, from: "bca", to: "bibit")])
        XCTAssertEqual(s.gain, -500_000)
        XCTAssertEqual(try XCTUnwrap(s.percent), -1, accuracy: 0.0001)
    }

    func testNoPercentWhileNothingWasPutIn() {
        let s = InvestmentSummary(account: wallet("bibit", .investment, balance: 0, opening: 0), transactions: [])
        XCTAssertNil(s.percent)
        XCTAssertNil(s.lastUpdated)
    }

    // The starting value counts as capital.
    func testOpeningValueIsCapital() {
        let s = InvestmentSummary(account: wallet("bibit", .investment, balance: 1_100_000, opening: 1_000_000), transactions: [])
        XCTAssertEqual(s.capital, 1_000_000)
        XCTAssertEqual(s.gain, 100_000)
    }

    // TC15: deleting the deposit leaves value and capital consistent (the transfer just isn't there).
    func testCapitalIgnoresADeletedDeposit() {
        let bibit = wallet("bibit", .investment, balance: 0, opening: 0)
        XCTAssertEqual(InvestmentSummary(account: bibit, transactions: []).capital, 0)
    }

    // TC10 / TC12
    func testInvestmentIsNeverASpendingSource() {
        let list = [wallet("bca", .bank, balance: 1), wallet("bibit", .investment, balance: 1), wallet("old", .cash, balance: 1, archived: true)]
        XCTAssertEqual(WalletRules.spendingSources(list).map(\.id), ["bca"])
    }

    // TC11
    func testTransferRules() {
        let bca = wallet("bca", .bank, balance: 1), bibit = wallet("bibit", .investment, balance: 1), emas = wallet("emas", .investment, balance: 1)
        let card = Account(id: "card", name: "card", type: .credit, icon: nil, isArchived: false, isDefault: false,
                           openingBalance: 0, currentBalance: 0, creditLimit: 1, dueDate: "5")
        XCTAssertTrue(WalletRules.canTransfer(from: bca, to: bibit))     // deposit
        XCTAssertTrue(WalletRules.canTransfer(from: bibit, to: bca))     // withdrawal
        XCTAssertFalse(WalletRules.canTransfer(from: bibit, to: emas))
        XCTAssertFalse(WalletRules.canTransfer(from: bca, to: card))
        XCTAssertFalse(WalletRules.canTransfer(from: bca, to: bca))
        XCTAssertEqual(WalletRules.transferTargets(from: bibit, in: [bca, bibit, emas, card]).map(\.id), ["bca"])
    }

    // TC4: the history label comes from which side is the investment wallet.
    func testDepositAndWithdrawalAreTransfersTouchingAnInvestmentWallet() {
        let list = [wallet("bca", .bank, balance: 1), wallet("bibit", .investment, balance: 1)]
        let deposit = txn(.transfer, 1, from: "bca", to: "bibit"), withdrawal = txn(.transfer, 1, from: "bibit", to: "bca")
        XCTAssertTrue(WalletRules.isDeposit(deposit, accounts: list))
        XCTAssertFalse(WalletRules.isWithdrawal(deposit, accounts: list))
        XCTAssertTrue(WalletRules.isWithdrawal(withdrawal, accounts: list))
        XCTAssertFalse(WalletRules.isDeposit(txn(.transfer, 1, from: "bca", to: "bca"), accounts: list))
    }
}

extension InvestmentTests {
    private func day(_ m: Int, _ d: Int) -> Date { Calendar.current.date(from: DateComponents(year: 2026, month: m, day: d, hour: 12))! }

    /// The design's example: Agustus 400k then -10k; September +200k, -100k deposit/withdraw and +30k update.
    func testHistoryGroupsByMonthWithClosingValueCapitalAndChange() {
        let bibit = Account(id: "bibit", name: "Bibit", type: .investment, icon: nil, isArchived: false, isDefault: false,
                            openingBalance: 400_000, currentBalance: 520_000, creditLimit: nil, dueDate: nil,
                            openedAt: "2026-08-03T05:00:00+00:00")
        let bca = Account(id: "bca", name: "BCA", type: .bank, icon: nil, isArchived: false, isDefault: false,
                          openingBalance: 0, currentBalance: 0, creditLimit: nil, dueDate: nil)
        func adj(_ id: String, _ delta: Double, _ on: Date) -> Transaction {
            Transaction(id: id, accountId: "bibit", counterpartyAccountId: nil, categoryId: nil, amount: abs(delta), type: .adjustment,
                        description: "Perbarui nilai", note: nil, date: on, delta: delta)
        }
        func move(_ id: String, _ from: String, _ to: String, _ amount: Double, _ on: Date) -> Transaction {
            Transaction(id: id, accountId: from, counterpartyAccountId: to, categoryId: nil, amount: amount, type: .transfer,
                        description: nil, note: nil, date: on, delta: nil)
        }
        let txns = [adj("a1", -10_000, day(8, 20)), move("d1", "bca", "bibit", 200_000, day(9, 1)),
                    move("w1", "bibit", "bca", 100_000, day(9, 12)), adj("a2", 30_000, day(9, 26))]
        let months = InvestmentHistory.months(account: bibit, transactions: txns, accounts: [bibit, bca])

        XCTAssertEqual(months.count, 2)
        let sep = months[0], aug = months[1]
        XCTAssertEqual(aug.endValue, 390_000)
        XCTAssertEqual(aug.capital, 400_000)
        XCTAssertEqual(aug.change, -10_000)
        XCTAssertEqual(sep.endValue, 520_000)
        XCTAssertEqual(sep.capital, 500_000)
        XCTAssertEqual(sep.change, 30_000)
        XCTAssertEqual(sep.rows.map(\.kind), [.value, .withdrawal, .deposit])
        XCTAssertEqual(sep.rows.first?.from, 490_000)
        XCTAssertEqual(sep.rows.first?.to, 520_000)
        XCTAssertEqual(aug.rows.last?.kind, .opening)
    }

    func testPercentText() {
        XCTAssertEqual(InvestmentSummary.percentText(0.04, signed: true), "+4%")
        XCTAssertEqual(InvestmentSummary.percentText(-0.06, signed: true), "−6%")
        XCTAssertEqual(InvestmentSummary.percentText(-1), "100%")
    }
}
