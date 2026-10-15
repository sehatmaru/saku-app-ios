import Foundation

/// Reference data for the export page, fetched once (Fitur 8, US1 & US2).
@MainActor
final class ExportViewModel: ObservableObject {
    @Published private(set) var isReady = false
    /// A fetch failed: the file would be incomplete, so the page says so instead of sharing it silently.
    @Published private(set) var loadFailed = false
    @Published private(set) var transactions: [Transaction] = []
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var categories: [Category] = []
    @Published private(set) var budgets: [Budget] = []

    func load(userId: String?) async {
        guard let userId, !isReady else { return }
        async let transactionsTask = SupabaseRepository.shared.fetchTransactions(userId: userId)
        async let accountsTask = SupabaseRepository.shared.fetchAccounts(userId: userId)
        async let categoriesTask = SupabaseRepository.shared.fetchCategories()
        async let budgetsTask = SupabaseRepository.shared.fetchBudgets(userId: userId)
        var failed = false
        do { transactions = try await transactionsTask } catch { failed = true }
        do { accounts = try await accountsTask } catch { failed = true }
        do { categories = try await categoriesTask } catch { failed = true }
        do {
            // fetchBudgets leaves `spent` at 0; the Budget page fills it the same way (TC 50).
            var fetched = try await budgetsTask
            for index in fetched.indices {
                let budget = fetched[index]
                do {
                    fetched[index].spent = try await SupabaseRepository.shared.fetchBudgetSpent(
                        categoryId: budget.categoryId, userId: userId,
                        startDate: budget.currentPeriodStart(), endDate: budget.currentPeriodEnd())
                } catch { failed = true }
            }
            budgets = fetched
        } catch { failed = true }
        loadFailed = failed
        isReady = !failed
    }

    func transactionsCsv(interval: DateInterval?, delimiter: CsvExport.Delimiter) -> String {
        CsvExport.transactions(transactions, accounts: accounts, categories: categories, interval: interval, delimiter: delimiter)
    }

    func walletsCsv(delimiter: CsvExport.Delimiter) -> String {
        CsvExport.wallets(accounts, delimiter: delimiter)
    }

    func budgetsCsv(delimiter: CsvExport.Delimiter) -> String {
        CsvExport.budgets(budgets, categories: categories, delimiter: delimiter)
    }

    /// Writes the file to the temporary folder for the share sheet. Nothing is sent to the server (US1).
    func write(_ csv: String, name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        guard let data = csv.data(using: .utf8) else { return nil }
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
