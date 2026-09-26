import Foundation

struct BudgetListItem: Identifiable {
    let id: String
    let category: Category
    let budget: Budget?
}

enum BudgetAddResult {
    case success
    case duplicate
    case failure
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
        categories.filter { $0.type == .expense }
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

    func addBudget(name: String, icon: String?, userId: String, amount: Double) async -> BudgetAddResult {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .failure }
        if categories.contains(where: { $0.name.lowercased() == trimmed.lowercased() }) {
            print("⚠️ Budget '\(trimmed)' sudah ada")
            return .duplicate
        }
        do {
            let category = try await SupabaseRepository.shared.createCategory(name: trimmed, type: .expense, icon: icon, color: "#FF6B6B", userId: userId)
            categories.append(category)
            categories.sort { $0.name < $1.name }

            do {
                let startDate = ISO8601DateFormatter().string(from: Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!)
                let budget = try await SupabaseRepository.shared.createBudget(
                    categoryId: category.id, name: category.name, amount: amount,
                    periodUnit: "month", periodInterval: 1,
                    startDate: startDate, endDate: nil, userId: userId
                )
                budgets.append(budget)
            } catch {
                categories.removeAll { $0.id == category.id }
                try? await SupabaseRepository.shared.softDeleteCategory(id: category.id)
                throw error
            }

            recalculate()
            cacheCurrentState()
            NotificationCenter.default.post(name: .dataDidChange, object: nil)
            return .success
        } catch is CancellationError {
            return .failure
        } catch {
            print("❌ addBudget failed: \(error)")
            return .failure
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
        totalBudget = budgets.reduce(0) { $0 + $1.amount }
        totalSpent = budgets.reduce(0) { $0 + $1.spent }
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
