import Foundation

struct TransactionSection: Identifiable {
    let id: String
    let month: Date
    let label: String
    let transactions: [Transaction]
}

@MainActor
final class TransactionListViewModel: ObservableObject {
    @Published var allTransactions: [Transaction] = []
    @Published var categories: [Category] = []
    @Published var accounts: [Account] = []
    @Published var thisMonthIncome: Double = 0
    @Published var thisMonthExpense: Double = 0
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var hasLoadedOnce = false
    @Published var errorMessage: String?
    private var loadedUserId: String?

    var thisMonthBalance: Double { thisMonthIncome - thisMonthExpense }

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
        } catch {
            if error is CancellationError { return }
            errorMessage = error.localizedDescription
            hasLoadedOnce = true
        }
    }

    private func calculateThisMonthSummary() {
        let calendar = Calendar.current
        let now = Date()
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
              let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return }

        let thisMonth = allTransactions.filter { $0.date >= monthStart && $0.date < nextMonth }
        thisMonthIncome = thisMonth.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        thisMonthExpense = thisMonth.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
    }

    func sections(for transactions: [Transaction]) -> [TransactionSection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: transactions) { tx -> Date in
            calendar.date(from: calendar.dateComponents([.year, .month], from: tx.date))!
        }

        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.dateFormat = "MMMM yyyy"

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
