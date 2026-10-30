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
    /// Budgets as they were in past periods, for the PDF report's budget table (Fitur 8 US3).
    @Published private(set) var historyBudgets: [BudgetHistoryBudget] = []
    @Published private(set) var amountChanges: [BudgetAmountChange] = []

    func load(userId: String?) async {
        guard let userId, !isReady else { return }
        async let transactionsTask = SupabaseRepository.shared.fetchTransactions(userId: userId)
        async let accountsTask = SupabaseRepository.shared.fetchAccounts(userId: userId)
        async let categoriesTask = SupabaseRepository.shared.fetchCategories()
        async let budgetsTask = SupabaseRepository.shared.fetchBudgets(userId: userId)
        async let historyTask = SupabaseRepository.shared.fetchBudgetsForHistory()
        async let changesTask = SupabaseRepository.shared.fetchBudgetAmountChanges()
        var failed = false
        do { transactions = try await transactionsTask } catch { failed = true }
        do { accounts = try await accountsTask } catch { failed = true }
        do { categories = try await categoriesTask } catch { failed = true }
        do {
            // fetchBudgets leaves `spent` at 0; it is computed here from the transactions fetched above (BUG-31).
            var fetched = try await budgetsTask
            for index in fetched.indices {
                fetched[index].spent = fetched[index].spentInCurrentPeriod(transactions: transactions)
            }
            budgets = fetched
        } catch { failed = true }
        do { historyBudgets = try await historyTask } catch { failed = true }
        do { amountChanges = try await changesTask } catch { failed = true }
        loadFailed = failed
        isReady = !failed
    }

    /// The report of one payday period: flow, categories, wallets and the budgets as they were then.
    func reportModel(interval: DateInterval, cycle: PaydayCycle, userName: String, isPrivate: Bool,
                     isPreview: Bool = false) -> ReportModel {
        let expenseIds = Set(categories.filter { $0.type == .expense }.map(\.id))
        let period = BudgetHistory.period(interval, budgets: historyBudgets, changes: amountChanges, transactions: transactions,
                                          shownCategoryIds: expenseIds)
        return ReportModel.make(interval: interval, cycle: cycle, userName: userName, transactions: transactions,
                                accounts: accounts, categories: categories, period: period, isPrivate: isPrivate,
                                isPreview: isPreview)
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

    /// Packs the CSVs in one ZIP in the temporary folder. The system zips a folder read "for uploading"; nothing leaves the device.
    func zip(_ files: [(name: String, csv: String)], name: String) -> URL? {
        let fileManager = FileManager.default
        let folder = fileManager.temporaryDirectory.appendingPathComponent("saku-ekspor-\(UUID().uuidString)", isDirectory: true)
        let output = fileManager.temporaryDirectory.appendingPathComponent(name)
        defer { try? fileManager.removeItem(at: folder) }
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            for file in files {
                guard let data = file.csv.data(using: .utf8) else { return nil }
                try data.write(to: folder.appendingPathComponent(file.name), options: .atomic)
            }
            var coordinationError: NSError?
            var result: URL?
            NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { zipped in
                try? fileManager.removeItem(at: output)
                if (try? fileManager.copyItem(at: zipped, to: output)) != nil { result = output }
            }
            return coordinationError == nil ? result : nil
        } catch {
            return nil
        }
    }
}
