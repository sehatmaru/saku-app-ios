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

    func loadBudgets(userId: String) async {
        isLoading = true
        do {
            async let budgetsTask = SupabaseRepository.shared.fetchBudgets(userId: userId)
            async let categoriesTask = SupabaseRepository.shared.fetchCategories()
            budgets = try await budgetsTask
            categories = try await categoriesTask

            var budgetsWithSpent: [Budget] = []
            for var budget in budgets {
                let spent = try? await SupabaseRepository.shared.fetchBudgetSpent(
                    categoryId: budget.categoryId,
                    userId: userId,
                    startDate: budget.startDate,
                    endDate: budget.endDate
                )
                budget.spent = spent ?? 0
                budgetsWithSpent.append(budget)
            }
            budgets = budgetsWithSpent
            recalculate()
        } catch {
            budgets = []
            categories = []
        }
        isLoading = false
    }

    func addBudget(categoryId: String, name: String, amount: Double, periodUnit: String, periodInterval: Int, startDate: String, endDate: String?, userId: String) async {
        do {
            let budget = try await SupabaseRepository.shared.createBudget(
                categoryId: categoryId, name: name, amount: amount,
                periodUnit: periodUnit, periodInterval: periodInterval,
                startDate: startDate, endDate: endDate, userId: userId
            )
            budgets.append(budget)
            recalculate()
        } catch {
            // silently fail
        }
    }

    func updateBudget(id: String, name: String, amount: Double, periodUnit: String, periodInterval: Int, startDate: String, endDate: String?, isActive: Bool) async {
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
        } catch {
            // silently fail
        }
    }

    func removeBudget(id: String) async {
        do {
            try await SupabaseRepository.shared.softDeleteBudget(id: id)
            budgets.removeAll { $0.id == id }
            recalculate()
        } catch {
            // silently fail
        }
    }

    private func recalculate() {
        totalBudget = budgets.reduce(0) { $0 + $1.amount }
        totalSpent = budgets.reduce(0) { $0 + $1.spent }
    }
}
