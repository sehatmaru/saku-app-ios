import Combine
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
    private var cancellables = Set<AnyCancellable>()
    /// Purchases behind running installments that are older than the months loaded.
    private var extraPurchases: [Transaction] = [] { didSet { runningCache = nil } }

    init() {
        // The transactions live in the shared store; this keeps `allTransactions` and the month summary in step with it.
        TransactionStore.shared.$transactions
            .sink { [weak self] list in
                guard let self else { return }
                self.allTransactions = list
                self.calculateThisMonthSummary()
                if !self.installments.isEmpty { Task { await self.loadMissingPurchases() } }
            }
            .store(in: &cancellables)
    }

    var thisMonthBalance: Double { thisMonthIncome - thisMonthExpense }

    /// Cleared whenever the data it is built from changes, so a render never recomputes it.
    private var runningCache: (list: [RunningInstallment], byTransaction: [String: RunningInstallment])?

    private var running: (list: [RunningInstallment], byTransaction: [String: RunningInstallment]) {
        if let runningCache { return runningCache }
        var list: [RunningInstallment] = []
        if !installments.isEmpty {
            let end = PaydayCycle.current.period(containing: Date()).end.addingTimeInterval(-1)
            list = RunningInstallments.compute(installments: installments, transactions: allTransactions + extraPurchases, accounts: accounts, periodEnd: end)
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
        await loadMissingPurchases()
    }

    /// An installment can be older than the months loaded; its purchase is read on its own so the plan still shows.
    private func loadMissingPurchases() async {
        let have = Set(allTransactions.map(\.id))
        let missing = installments.map(\.transactionId).filter { !have.contains($0) }
        guard Set(missing) != Set(extraPurchases.map(\.id)) else { return }
        extraPurchases = missing.isEmpty ? [] : ((try? await SupabaseRepository.shared.fetchTransactions(ids: missing)) ?? [])
    }

    /// A write elsewhere: wallets, categories and installments again. The transactions reload through the store.
    func refreshSupportData(userId: String) async {
        async let cats = SupabaseRepository.shared.fetchCategories()
        async let accts = SupabaseRepository.shared.fetchAccounts(userId: userId)
        if let c = try? await cats { categories = c }
        if let a = try? await accts { accounts = a }
        AppDataCache.shared.setTransactionState(.init(categories: categories, accounts: accounts), for: userId)
        await refreshInstallments()
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
        let store = TransactionStore.shared

        if !forceRefresh, store.userId == userId, store.hasLoaded, let cached = AppDataCache.shared.transactionState(for: userId) {
            errorMessage = nil
            categories = cached.categories
            accounts = cached.accounts
            allTransactions = store.transactions
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
            async let categoriesTask = SupabaseRepository.shared.fetchCategories()
            async let accountsTask = SupabaseRepository.shared.fetchAccounts(userId: userId)
            if forceRefresh, store.userId == userId, store.hasLoaded {
                await store.reload()
            } else {
                try await store.load(userId: userId)
            }
            let (fetchedCategories, fetchedAccounts) = try await (categoriesTask, accountsTask)
            allTransactions = store.transactions
            categories = fetchedCategories
            accounts = fetchedAccounts
            calculateThisMonthSummary()
            AppDataCache.shared.setTransactionState(.init(categories: categories, accounts: accounts), for: userId)
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
