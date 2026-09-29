import XCTest
@testable import SakuQ

/// `updateTransaction` reverses the old effects and applies the new ones, so these
/// effects must be exact for every type and for credit cards.
final class TransactionBalanceEffectsTests: XCTestCase {
    private func txn(_ type: Transaction.TransactionType, _ amount: Double, from: String = "bank", to: String? = nil) -> Transaction {
        Transaction(id: "t", accountId: from, counterpartyAccountId: to, categoryId: nil, amount: amount,
                    type: type, description: nil, note: nil, date: Date(), delta: nil)
    }

    func testEffectsPerType() {
        let credit = ["bank": false, "card": true, "cash": false]
        XCTAssertEqual(effects(txn(.expense, 50), credit), ["bank": -50])
        XCTAssertEqual(effects(txn(.income, 50), credit), ["bank": 50])
        // A card tracks debt: spending raises it, paying it back lowers it.
        XCTAssertEqual(effects(txn(.expense, 50, from: "card"), credit), ["card": 50])
        XCTAssertEqual(effects(txn(.income, 50, from: "card"), credit), ["card": -50])
        XCTAssertEqual(effects(txn(.transfer, 50, to: "cash"), credit), ["bank": -50, "cash": 50])
        // Paying the card from the bank lowers both; cash out of the card raises its debt.
        XCTAssertEqual(effects(txn(.transfer, 50, to: "card"), credit), ["bank": -50, "card": -50])
        XCTAssertEqual(effects(txn(.transfer, 50, from: "card", to: "cash"), credit), ["card": 50, "cash": 50])
        XCTAssertEqual(effects(txn(.adjustment, 50), credit), [:])
    }

    /// Moving an expense to another wallet refunds the old wallet and charges the new one.
    func testWalletChangeNetsOutPerAccount() {
        let credit = ["bank": false, "cash": false]
        var net: [String: Double] = [:]
        for (sign, t) in [(-1.0, txn(.expense, 50, from: "bank")), (1.0, txn(.expense, 80, from: "cash"))] {
            for (id, effect) in SupabaseRepository.balanceEffects(of: t, isCredit: credit) { net[id, default: 0] += sign * effect }
        }
        XCTAssertEqual(net, ["bank": 50, "cash": -80])
    }

    private func effects(_ t: Transaction, _ credit: [String: Bool]) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: SupabaseRepository.balanceEffects(of: t, isCredit: credit))
    }
}
