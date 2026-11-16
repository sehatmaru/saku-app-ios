import Foundation

struct TransactionSection: Identifiable {
    let id: String
    let month: Date
    let label: String
    let transactions: [Transaction]
}

@MainActor
final class TransactionListViewModel: ObservableObject {
    @Published var allTransactions: [Transaction] = [] { didSet { runningCache = nil } }
    @Published var categories: [Category] = []
    @Published var accounts: [Account] = [] { didSet { runningCache = nil } }
    /// 0% card installments, for the "Cicilan berjalan" marker above the list.
    @Published var installments: [CardInstallment] = [] { didSet { runningCache = nil } }
    @Published var thisMonthIncome: Double = 0
    @Published var thisMonthExpense: Double = 0
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var hasLoadedOnce = false
    @Published var errorMessage: String?
    private var loadedUserId: String?

    var thisMonthBalance: Double { thisMonthIncome - thisMonthExpense }

    /// Cleared whenever the data it is built from changes, so a render never recomputes it.
    private var runningCache: (list: [RunningInstallment], byTransaction: [String: RunningInstallment])?

    private var running: (list: [RunningInstallment], byTransaction: [String: RunningInstallment]) {
        if let runningCache { return runningCache }
        var list: [RunningInstallment] = []
        if !installments.isEmpty {
            let end = PaydayCycle.current.period(containing: Date()).end.addingTimeInterval(-1)
            list = RunningInstallments.compute(installments: installments, transactions: allTransactions, accounts: accounts, periodEnd: end)
        }
        let value = (list, Dictionary(list.map { ($0.transactionId, $0) }, uniquingKeysWith: { first, _ in first }))
        runningCache = value
        return value
    }

    /// Installments still being billed at the end of the current payday period.
    var runningInstallments: [RunningInstallment] { running.list }
    /// The same installments by the id of their purchase, for the list rows.
    var runningByTransaction: [String: RunningInstallment] { running.byTransaction }

    private func refreshInstallments() async {
        let ids = accounts.filter(\.isCreditCard).map(\.id)
        guard !ids.isEmpty else { installments = []; return }
        if let fetched = try? await SupabaseRepository.shared.fetchInstallments(accountIds: ids) { installments = fetched }
    }

    /// `months == nil` settles the plan now. Returns whether it saved.
    func changeInstallment(id: String, months: Int?) async -> Bool {
        do {
            if let months { try await SupabaseRepository.shared.updateInstallmentMonths(id: id, months: months) }
            else { try await SupabaseRepository.shared.settleInstallment(id: id) }
        } catch { return false }
        await refreshInstallments()
        NotificationCenter.default.post(name: .dataDidChange, object: nil)
        return true
    }

    func loadTransactions(userId: String, forceRefresh: Bool = false) async {
        guard !isLoading, !isRefreshing else { return }

        if !forceRefresh, let cached = AppDataCache.shared.transactionState(for: userId) {
            errorMessage = nil
            allTransactions = cached.transactions
            categories = cached.categories
            accounts = cached.accounts
            calculateThisMonthSummary()
            loadedUserId = userId
            hasLoadedOnce = true
            await refreshInstallments()
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
            async let transactionsTask = SupabaseRepository.shared.fetchTransactions(userId: userId)
            async let categoriesTask = SupabaseRepository.shared.fetchCategories()
            async let accountsTask = SupabaseRepository.shared.fetchAccounts(userId: userId)
            let (fetchedTransactions, fetchedCategories, fetchedAccounts) = try await (
                transactionsTask,
                categoriesTask,
                accountsTask
            )
            allTransactions = fetchedTransactions
            categories = fetchedCategories
            accounts = fetchedAccounts
            calculateThisMonthSummary()
            AppDataCache.shared.setTransactionState(.init(transactions: allTransactions, categories: categories, accounts: accounts), for: userId)
            loadedUserId = userId
            hasLoadedOnce = true
            await refreshInstallments()
        } catch {
            if error is CancellationError { return }
            errorMessage = error.localizedDescription
            hasLoadedOnce = true
        }
    }

    /// "Bulan ini" runs from payday, the same period the Beranda summary uses.
    private func calculateThisMonthSummary() {
        let cycle = PaydayCycle.current
        let thisMonth = allTransactions.filter { cycle.contains($0.date) }
        thisMonthIncome = thisMonth.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        thisMonthExpense = thisMonth.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
    }

    func sections(for transactions: [Transaction]) -> [TransactionSection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: transactions) { tx -> Date in
            calendar.date(from: calendar.dateComponents([.year, .month], from: tx.date))!
        }

        let formatter = TransactionDates.formatter("MMMM yyyy")

        return grouped.map { month, items in
            let label = formatter.string(from: month)

            return TransactionSection(
                id: "\(calendar.component(.year, from: month))-\(calendar.component(.month, from: month))",
                month: month,
                label: label,
                transactions: items.newestFirst()
            )
        }
        .sorted { $0.month > $1.month }
    }
}
