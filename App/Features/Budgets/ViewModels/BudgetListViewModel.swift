import Foundation

struct BudgetListItem: Identifiable {
    let id: String
    let category: Category
    let budget: Budget?
}

@MainActor
final class BudgetListViewModel: ObservableObject {
    @Published var budgets: [Budget] = []
    @Published var categories: [Category] = []
    @Published var totalBudget: Double = 0
    @Published var totalSpent: Double = 0
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var hasLoadedOnce = false
    @Published var errorMessage: String?
    @Published var allExpenseTransactions: [Transaction] = []
    @Published var accounts: [Account] = []
    /// Hidden categories (and their budgets) stay off the Budget page and Tambah budget.
    @Published var preferences: [CategoryPreference] = []

    private var loadedUserId: String?

    var totalRemaining: Double { totalBudget - totalSpent }

    var budgetItems: [BudgetListItem] {
        let setItems = expenseCategories
            .compactMap { category -> BudgetListItem? in
                guard let budget = budgets.first(where: { $0.categoryId == category.id }) else { return nil }
                return BudgetListItem(id: category.id, category: category, budget: budget)
            }
            .sorted { $0.budget!.progress > $1.budget!.progress }

        let unsetItems = expenseCategories
            .filter { category in !budgets.contains(where: { $0.categoryId == category.id }) }
            .map { BudgetListItem(id: $0.id, category: $0, budget: nil) }

        return setItems + unsetItems
    }

    private var expenseCategories: [Category] {
        // Penyesuaian Saldo is used by balance corrections on its own and never gets a budget.
        categories.filter { $0.type == .expense && !CategoryCatalog.isSystem($0) }.arranged(by: preferences).shown
    }

    /// Budgets of shown categories only.
    var visibleBudgets: [Budget] {
        let shown = Set(expenseCategories.map(\.id))
        return budgets.filter { shown.contains($0.categoryId) }
    }

    /// Shown expense categories without a budget, in the user's order (Tambah budget step 1).
    var availableCategories: [Category] {
        expenseCategories.filter { category in !budgets.contains { $0.categoryId == category.id } }
    }

    /// Average spent in the category over the last 3 full payday periods.
    func threeMonthAverage(categoryId: String) -> Double {
        let cycle = PaydayCycle.current
        let periods = (1...3).map { cycle.period(offset: -$0) }
        let total = allExpenseTransactions
            .filter { tx in tx.type == .expense && tx.categoryId == categoryId && periods.contains { $0.start <= tx.date && tx.date < $0.end } }
            .reduce(0) { $0 + $1.amount }
        return (total / 3).rounded()
    }

    func loadBudgets(userId: String, forceRefresh: Bool = false) async {
        guard !isLoading, !isRefreshing else { return }

        if !forceRefresh, hasLoadedOnce, loadedUserId == userId {
            return
        }

        if !forceRefresh, let cached = AppDataCache.shared.budgetState(for: userId) {
            errorMessage = nil
            loadedUserId = userId
            hasLoadedOnce = true
            budgets = cached.budgets
            categories = cached.categories
            allExpenseTransactions = cached.allExpenseTransactions
            accounts = cached.accounts
            preferences = (try? await SupabaseRepository.shared.fetchCategoryPreferences()) ?? preferences
            recalculate()
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
            async let budgetsTask = SupabaseRepository.shared.fetchBudgets(userId: userId)
            async let categoriesTask = SupabaseRepository.shared.fetchCategories()
            async let transactionsTask = SupabaseRepository.shared.fetchTransactions(userId: userId)
            async let accountsTask = SupabaseRepository.shared.fetchAccounts(userId: userId)
            async let preferencesTask = SupabaseRepository.shared.fetchCategoryPreferences()

            let (fetchedBudgets, fetchedCategories, fetchedTransactions, fetchedAccounts) = try await (
                budgetsTask,
                categoriesTask,
                transactionsTask,
                accountsTask
            )

            var budgetsWithSpent: [Budget] = []
            for var budget in fetchedBudgets {
                let spent = try? await SupabaseRepository.shared.fetchBudgetSpent(
                    categoryId: budget.categoryId,
                    userId: userId,
                    startDate: budget.currentPeriodStart(),
                    endDate: budget.currentPeriodEnd()
                )
                budget.spent = spent ?? 0
                budgetsWithSpent.append(budget)
            }

            preferences = (try? await preferencesTask) ?? preferences
            budgets = budgetsWithSpent
            categories = fetchedCategories
            allExpenseTransactions = fetchedTransactions
            accounts = fetchedAccounts
            recalculate()
            loadedUserId = userId
            hasLoadedOnce = true
            AppDataCache.shared.setBudgetState(.init(
                budgets: budgets,
                categories: categories,
                allExpenseTransactions: allExpenseTransactions,
                accounts: accounts
            ), for: userId)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
            hasLoadedOnce = true
        }
    }

    func addBudget(categoryId: String, name: String, amount: Double, periodUnit: String, periodInterval: Int, startDate: String, endDate: String?, userId: String) async -> Bool {
        do {
            let budget = try await SupabaseRepository.shared.createBudget(
                categoryId: categoryId, name: name, amount: amount,
                periodUnit: periodUnit, periodInterval: periodInterval,
                startDate: startDate, endDate: endDate, userId: userId
            )
            budgets.append(budget)
            recalculate()
            cacheCurrentState()
            NotificationCenter.default.post(name: .dataDidChange, object: nil)
            return true
        } catch is CancellationError {
            return false
        } catch {
            print("❌ addBudget failed: \(error)")
            return false
        }
    }

    func setBudget(categoryId: String, name: String, amount: Double, periodUnit: String, periodInterval: Int, startDate: String, endDate: String?, userId: String) async -> Bool {
        do {
            let budget = try await SupabaseRepository.shared.createBudget(
                categoryId: categoryId, name: name, amount: amount,
                periodUnit: periodUnit, periodInterval: periodInterval,
                startDate: startDate, endDate: endDate, userId: userId
            )
            budgets.append(budget)
            recalculate()
            cacheCurrentState()
            NotificationCenter.default.post(name: .dataDidChange, object: nil)
            return true
        } catch is CancellationError {
            return false
        } catch {
            print("❌ setBudget failed: \(error)")
            return false
        }
    }

    func updateBudget(id: String, name: String, amount: Double, periodUnit: String, periodInterval: Int, startDate: String, endDate: String?, isActive: Bool) async -> Bool {
        do {
            let updated = try await SupabaseRepository.shared.updateBudget(
                id: id, name: name, amount: amount,
                periodUnit: periodUnit, periodInterval: periodInterval,
                startDate: startDate, endDate: endDate, isActive: isActive
            )
            if let idx = budgets.firstIndex(where: { $0.id == updated.id }) {
                budgets[idx] = updated
            }
            recalculate()
            cacheCurrentState()
            NotificationCenter.default.post(name: .dataDidChange, object: nil)
            return true
        } catch is CancellationError {
            return false
        } catch {
            print("❌ updateBudget failed: \(error)")
            return false
        }
    }

    func removeBudget(id: String) async -> Bool {
        do {
            try await SupabaseRepository.shared.softDeleteBudget(id: id)
            budgets.removeAll { $0.id == id }
            recalculate()
            cacheCurrentState()
            NotificationCenter.default.post(name: .dataDidChange, object: nil)
            return true
        } catch is CancellationError {
            return false
        } catch {
            print("❌ removeBudget failed: \(error)")
            return false
        }
    }

    private func recalculate() {
        totalBudget = visibleBudgets.reduce(0) { $0 + $1.amount }
        totalSpent = visibleBudgets.reduce(0) { $0 + $1.spent }
    }

    private func cacheCurrentState() {
        guard let userId = loadedUserId else { return }
        AppDataCache.shared.setBudgetState(.init(
            budgets: budgets,
            categories: categories,
            allExpenseTransactions: allExpenseTransactions,
            accounts: accounts
        ), for: userId)
    }
}
