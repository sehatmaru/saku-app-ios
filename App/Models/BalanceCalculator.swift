import Foundation

enum BalanceCalculator {
    static func applyBalances(to accounts: [Account], from transactions: [Transaction]) -> [Account] {
        let balancesByAccountId = balancesByAccountId(for: accounts, from: transactions)

        return accounts.map { account in
            var updated = account
            updated.currentBalance = balancesByAccountId[account.id] ?? account.openingBalance
            return updated
        }
    }

    static func totalBalance(for accounts: [Account]) -> Double {
        accounts.filter { $0.isActive }.reduce(0) { $0 + $1.balance }
    }

    private static func balancesByAccountId(for accounts: [Account], from transactions: [Transaction]) -> [String: Double] {
        var balances = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.openingBalance) })

        for transaction in transactions {
            switch transaction.type {
            case .income:
                balances[transaction.accountId, default: 0] += transaction.amount
            case .expense:
                balances[transaction.accountId, default: 0] -= transaction.amount
            case .transfer:
                balances[transaction.accountId, default: 0] -= transaction.amount
                if let counterpartyAccountId = transaction.counterpartyAccountId {
                    balances[counterpartyAccountId, default: 0] += transaction.amount
                }
            }
        }

        return balances
    }
}
