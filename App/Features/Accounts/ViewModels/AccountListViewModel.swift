import Foundation

@MainActor
final class AccountListViewModel: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var totalBalance: Double = 0
    /// Active investment wallets only; not part of `totalBalance` (cash).
    @Published var assetsTotal: Double = 0
    @Published var totalCreditDebt: Double = 0
    /// Subscriptions on active wallets, active or paused.
    @Published var subscriptions: [CardSubscription] = []
    /// 0% installments on the credit cards.
    @Published var installments: [CardInstallment] = []
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var hasLoadedOnce = false
    @Published var errorMessage: String?
    private var loadedUserId: String?

    func loadAccounts(userId: String, forceRefresh: Bool = false) async {
        if forceRefresh {
            isRefreshing = false
            isLoading = false
        }
        guard !isLoading, !isRefreshing else { return }

        if !forceRefresh, let cached = AppDataCache.shared.accounts(for: userId) {
            errorMessage = nil
            loadedUserId = userId
            accounts = cached
            recalculateBalance()
            hasLoadedOnce = true
            // Cheap and not cached, so a fresh page still gets them.
            await loadSubscriptionsAndInstallments()
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
            accounts = fetchedAccounts

            await loadSubscriptionsAndInstallments()

            recalculateBalance()
            AppDataCache.shared.setAccounts(accounts, for: userId)
            AppDataCache.shared.setAccountTransactions(groupTransactionsByAccount(transactions), for: userId)
            loadedUserId = userId
            hasLoadedOnce = true
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
            hasLoadedOnce = true
        }
    }

    func addAccount(name: String, type: Account.AccountType, openingBalance: Double, icon: String?, userId: String, creditLimit: Double? = nil, dueDate: String? = nil, statementDay: Int? = nil, color: String? = nil, cardNetwork: String? = nil, openingUnbilledUntil: String? = nil, makeDefault: Bool = false) async -> Bool {
        if accounts.contains(where: { $0.name == name && $0.type == type && $0.isActive }) {
            print("⚠️ Nama '\(name)' sudah digunakan untuk kategori \(type.rawValue)")
            return false
        }
        do {
            // An investment wallet is never the main wallet: the main one is where spending lands.
            let isDefault = accounts.filter { !$0.isInvestment }.isEmpty && type != .investment
            let account = try await SupabaseRepository.shared.createAccount(name: name, type: type, openingBalance: openingBalance, icon: icon, userId: userId, isDefault: isDefault, creditLimit: creditLimit, dueDate: dueDate, statementDay: statementDay, color: color, cardNetwork: cardNetwork, openingUnbilledUntil: openingUnbilledUntil)
            accounts.append(account)
            if makeDefault && !isDefault {
                await setDefaultAccount(id: account.id, userId: userId)
            }
            recalculateBalance()
            AppDataCache.shared.setAccounts(accounts, for: userId)
            loadedUserId = userId
            NotificationCenter.default.post(name: .dataDidChange, object: nil)
            return true
        } catch is CancellationError {
            return false
        } catch {
            if "\(error)".contains("23505") {
                print("⚠️ Nama akun sudah digunakan")
            } else {
                print("❌ addAccount failed: \(error)")
            }
            return false
        }
    }

    /// "Perbarui nilai": the new worth of an investment wallet. The difference is logged as an adjustment
    /// (not income or expense) and the starting balance, which the capital is counted from, stays as it was.
    func updateInvestmentValue(account: Account, newValue: Double, date: Date, note: String) async -> Bool {
        guard account.isInvestment, newValue >= 0 else { return false }
        do {
            let delta = newValue - account.balance
            if abs(delta) > 0.001 {
                let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
                try await SupabaseRepository.shared.createAdjustmentLog(
                    accountId: account.id, amount: delta, note: text.isEmpty ? "Perbarui nilai" : text, date: date)
            }
            let updated = try await SupabaseRepository.shared.setCurrentBalance(id: account.id, to: newValue)
            if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                var next = updated
                next.currentBalance = newValue
                accounts[index] = next
            }
            recalculateBalance()
            if let loadedUserId { AppDataCache.shared.setAccounts(accounts, for: loadedUserId) }
            NotificationCenter.default.post(name: .dataDidChange, object: nil)
            return true
        } catch {
            print("❌ updateInvestmentValue failed: \(error)")
            return false
        }
    }

    func rebalanceAccount(id: String, name: String, type: Account.AccountType, icon: String?, isArchived: Bool, newBalance: Double, oldBalance: Double, userId: String, creditLimit: Double? = nil, dueDate: String? = nil, statementDay: Int? = nil, color: String? = nil, cardNetwork: String? = nil, billedDelta: Double = 0, runningDelta: Double = 0) async -> Bool {
        // An investment can be worth 0 but never less.
        if type == .investment && newBalance < 0 { return false }
        do {
            // A card has two bills: a change to the printed one is dated on the last cut-off, so it lands
            // in this statement; a change to the running one is dated now and waits for the next cut-off.
            if type == .credit, abs(billedDelta) > 0.001 || abs(runningDelta) > 0.001 {
                let cutoff = statementDay.map { CreditStatement.lastCutoffNoon(statementDay: $0) } ?? Date()
                for (delta, date, label) in [(billedDelta, cutoff, "tagihan terbit"), (runningDelta, Date(), "tagihan berjalan")] where abs(delta) > 0.001 {
                    let note = "Penyesuaian \(label): \(delta > 0 ? "+" : "-")Rp \(String(Int(abs(delta))).formattedWithThousandSeparator)"
                    do {
                        try await SupabaseRepository.shared.createAdjustmentLog(accountId: id, amount: delta, note: note, date: date)
                    } catch {
                        print("⚠️ adjustment log failed (balance already updated): \(error)")
                    }
                }
            } else if abs(newBalance - oldBalance) > 0.001 {
                let delta = newBalance - oldBalance
                let note = "Penyesuaian Saldo: Rp \(String(Int(oldBalance)).formattedWithThousandSeparator) → Rp \(String(Int(newBalance)).formattedWithThousandSeparator) (perubahan \(delta > 0 ? "+" : "")\(String(Int(delta)).formattedWithThousandSeparator))"
                do {
                    try await SupabaseRepository.shared.createAdjustmentLog(accountId: id, amount: delta, note: note, date: Date())
                } catch {
                    print("⚠️ adjustment log failed (balance already updated): \(error)")
                }
            }

            let updated = try await SupabaseRepository.shared.updateAccount(id: id, name: name, type: type, openingBalance: type == .investment ? (accounts.first { $0.id == id }?.openingBalance ?? newBalance) : newBalance, currentBalance: newBalance, icon: icon, isArchived: isArchived, isDefault: nil, creditLimit: creditLimit, dueDate: dueDate, statementDay: statementDay, color: color, cardNetwork: cardNetwork, clearOpeningUnbilled: abs(billedDelta) > 0.001)
            if let index = accounts.firstIndex(where: { $0.id == id }) {
                var updatedAccount = updated
                if abs(newBalance - oldBalance) > 0.001 {
                    updatedAccount.currentBalance = newBalance
                }
                accounts[index] = updatedAccount
            }
            recalculateBalance()
            if let loadedUserId {
                AppDataCache.shared.setAccounts(accounts, for: loadedUserId)
            }
            NotificationCenter.default.post(name: .dataDidChange, object: nil)
            return true
        } catch is CancellationError {
            return false
        } catch {
            print("❌ rebalanceAccount failed: \(error)")
            return false
        }
    }

    func setDefaultAccount(id: String, userId: String) async {
        for account in accounts where account.isDefault {
            _ = try? await SupabaseRepository.shared.updateAccount(id: account.id, name: account.name, type: account.type, openingBalance: account.openingBalance, currentBalance: account.currentBalance, icon: account.icon, isArchived: account.isArchived, isDefault: false, creditLimit: account.creditLimit, dueDate: account.dueDate)
        }
        if let account = accounts.first(where: { $0.id == id }) {
            _ = try? await SupabaseRepository.shared.updateAccount(id: id, name: account.name, type: account.type, openingBalance: account.openingBalance, currentBalance: account.currentBalance, icon: account.icon, isArchived: account.isArchived, isDefault: true, creditLimit: account.creditLimit, dueDate: account.dueDate)
        }
        if let loadedUserId {
            await loadAccounts(userId: loadedUserId, forceRefresh: true)
        }
    }

    func removeAccount(id: String) async -> Bool {
        do {
            try await SupabaseRepository.shared.softDeleteAccount(id: id)
            accounts.removeAll { $0.id == id }
            recalculateBalance()
            if let loadedUserId {
                AppDataCache.shared.setAccounts(accounts, for: loadedUserId)
            }
            NotificationCenter.default.post(name: .dataDidChange, object: nil)
            return true
        } catch is CancellationError {
            return false
        } catch {
            print("❌ removeAccount failed: \(error)")
            return false
        }
    }

    func toggleAccountArchive(id: String) async -> Bool {
        guard let account = accounts.first(where: { $0.id == id }) else { return false }
        do {
            try await SupabaseRepository.shared.toggleArchiveAccount(id: id, archived: !account.isArchived)
            if let index = accounts.firstIndex(where: { $0.id == id }) {
                // Keep every other field (statement day, colour, network, …) as it was.
                accounts[index].isArchived.toggle()
            }
            recalculateBalance()
            if let loadedUserId {
                AppDataCache.shared.setAccounts(accounts, for: loadedUserId)
            }
            NotificationCenter.default.post(name: .dataDidChange, object: nil)
            return true
        } catch is CancellationError {
            return false
        } catch {
            print("❌ toggleAccountArchive failed: \(error)")
            return false
        }
    }

    /// Subscriptions on every active wallet and the cards' installments; also sums each
    /// wallet's monthly subscription total.
    private func loadSubscriptionsAndInstallments() async {
        let activeIds = accounts.filter(\.isActive).map(\.id)
        guard !activeIds.isEmpty else {
            subscriptions = []
            installments = []
            return
        }
        let cardIds = accounts.filter { $0.isActive && $0.isCreditCard }.map(\.id)
        async let subsTask = SupabaseRepository.shared.fetchSubscriptions(accountIds: activeIds)
        async let plansTask = SupabaseRepository.shared.fetchInstallments(accountIds: cardIds)
        subscriptions = (try? await subsTask) ?? subscriptions
        installments = (try? await plansTask) ?? installments

        let active = subscriptions.filter(\.isActive)
        let monthly = Dictionary(active.map { ($0.accountId, $0.monthlyAmount) }, uniquingKeysWith: +)
        accounts = accounts.map { account in
            var account = account
            account.subscriptionsTotal = monthly[account.id]
            return account
        }
        recalculateBalance()
    }

    /// The card's current billing cycle, from its transactions and installments.
    func statement(for card: Account, transactions: [Transaction]) -> CreditStatement? {
        CreditStatement(card: card, transactions: transactions, installments: installments)
    }

    private func recalculateBalance() {
        let wealth = WealthSummary(accounts: accounts)
        totalBalance = wealth.cash
        assetsTotal = wealth.assets
        totalCreditDebt = accounts.filter { $0.isActive && $0.isCreditCard }.reduce(0) { $0 + $1.balance }
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
            grouped[key] = grouped[key]?.newestFirst()
        }

        return grouped
    }
}
