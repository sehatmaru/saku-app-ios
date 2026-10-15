import Foundation

/// Reference data for the export page, fetched once (Fitur 8, US1 & US2).
@MainActor
final class ExportViewModel: ObservableObject {
    @Published private(set) var isReady = false
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
        if let fetched = try? await transactionsTask { transactions = fetched }
        if let fetched = try? await accountsTask { accounts = fetched }
        if let fetched = try? await categoriesTask { categories = fetched }
        if let fetched = try? await budgetsTask { budgets = fetched }
        isReady = true
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
