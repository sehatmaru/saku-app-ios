import Foundation

@MainActor
final class AccountListViewModel: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var totalBalance: Double = 0
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var hasLoadedOnce = false
    @Published var errorMessage: String?
    private var loadedUserId: String?

    func loadAccounts(userId: String, forceRefresh: Bool = false) async {
        guard !isLoading, !isRefreshing else { return }

        if !forceRefresh, let cached = AppDataCache.shared.accounts(for: userId) {
            errorMessage = nil
            loadedUserId = userId
            accounts = cached
            recalculateBalance()
            hasLoadedOnce = true
            return
        }

        if forceRefresh, hasLoadedOnce {
            isRefreshing = true
        } else {
            isLoading = true
        }
        defer {
            isLoading = false
            isRefreshing = false
        }

        do {
            errorMessage = nil
            async let accountsTask = SupabaseRepository.shared.fetchAccounts(userId: userId)
            async let transactionsTask = SupabaseRepository.shared.fetchTransactions(userId: userId)
            let (fetchedAccounts, transactions) = try await (accountsTask, transactionsTask)
            accounts = BalanceCalculator.applyBalances(to: fetchedAccounts, from: transactions)
            recalculateBalance()
            AppDataCache.shared.setAccounts(accounts, for: userId)
            AppDataCache.shared.setAccountTransactions(groupTransactionsByAccount(transactions), for: userId)
            loadedUserId = userId
            hasLoadedOnce = true
        } catch {
            errorMessage = error.localizedDescription
            hasLoadedOnce = true
        }
    }

    func addAccount(name: String, type: Account.AccountType, openingBalance: Double, icon: String?, userId: String) async {
        do {
            let account = try await SupabaseRepository.shared.createAccount(name: name, type: type, openingBalance: openingBalance, icon: icon, userId: userId)
            accounts.append(account)
            recalculateBalance()
            AppDataCache.shared.setAccounts(accounts, for: userId)
            loadedUserId = userId
            NotificationCenter.default.post(name: .dataDidChange, object: nil)
        } catch {
            // silently fail
        }
    }

    func updateAccount(id: String, name: String, type: Account.AccountType, openingBalance: Double, icon: String?, isArchived: Bool) async {
        do {
            let updated = try await SupabaseRepository.shared.updateAccount(id: id, name: name, type: type, openingBalance: openingBalance, icon: icon, isArchived: isArchived)
            if let index = accounts.firstIndex(where: { $0.id == id }) {
                accounts[index] = updated
            }
            recalculateBalance()
            if let loadedUserId {
                AppDataCache.shared.setAccounts(accounts, for: loadedUserId)
            }
            NotificationCenter.default.post(name: .dataDidChange, object: nil)
        } catch {
            // silently fail
        }
    }

    func removeAccount(id: String) async {
        do {
            try await SupabaseRepository.shared.softDeleteAccount(id: id)
            accounts.removeAll { $0.id == id }
            recalculateBalance()
            if let loadedUserId {
                AppDataCache.shared.setAccounts(accounts, for: loadedUserId)
            }
            NotificationCenter.default.post(name: .dataDidChange, object: nil)
        } catch {
            // silently fail
        }
    }

    func toggleAccountArchive(id: String) async {
        guard let account = accounts.first(where: { $0.id == id }) else { return }
        do {
            try await SupabaseRepository.shared.toggleArchiveAccount(id: id, archived: !account.isArchived)
            if let index = accounts.firstIndex(where: { $0.id == id }) {
                let updated = Account(
                    id: account.id,
                    name: account.name,
                    type: account.type,
                    icon: account.icon,
                    isArchived: !account.isArchived,
                    openingBalance: account.openingBalance
                )
                accounts[index] = updated
            }
            recalculateBalance()
            if let loadedUserId {
                AppDataCache.shared.setAccounts(accounts, for: loadedUserId)
            }
            NotificationCenter.default.post(name: .dataDidChange, object: nil)
        } catch {
            // silently fail
        }
    }

    private func recalculateBalance() {
        totalBalance = BalanceCalculator.totalBalance(for: accounts)
    }

    private func groupTransactionsByAccount(_ transactions: [Transaction]) -> [String: [Transaction]] {
        var grouped: [String: [Transaction]] = [:]

        for transaction in transactions {
            grouped[transaction.accountId, default: []].append(transaction)
            if let counterpartyAccountId = transaction.counterpartyAccountId {
                grouped[counterpartyAccountId, default: []].append(transaction)
            }
        }

        for key in grouped.keys {
            grouped[key] = grouped[key]?.sorted { $0.date > $1.date }
        }

        return grouped
    }
}
