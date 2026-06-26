import Foundation

struct BudgetListItem: Identifiable {
    let id: String
    let category: Category
    let budget: Budget?
}

@MainActor
final class BudgetListViewModel: ObservableObject {
    @Published var budgets: [Budget] = []
    @Published var totalBudget: Double = 0
    @Published var totalSpent: Double = 0

    var totalRemaining: Double { totalBudget - totalSpent }

    var budgetItems: [BudgetListItem] {
        let setItems = Category.expenseCategories
            .compactMap { category -> BudgetListItem? in
                guard let budget = budgets.first(where: { $0.categoryId == category.id }) else { return nil }
                return BudgetListItem(id: category.id, category: category, budget: budget)
            }
            .sorted { $0.budget!.progress > $1.budget!.progress }

        let unsetItems = Category.expenseCategories
            .filter { category in !budgets.contains(where: { $0.categoryId == category.id }) }
            .map { BudgetListItem(id: $0.id, category: $0, budget: nil) }

        return setItems + unsetItems
    }

    func loadBudgets() {
        budgets = Budget.sample
        recalculate()
    }

    func addBudget(_ budget: Budget) {
        budgets.append(budget)
        recalculate()
    }

    func updateBudget(_ budget: Budget) {
        if let idx = budgets.firstIndex(where: { $0.id == budget.id }) {
            budgets[idx] = budget
            recalculate()
        }
    }

    func removeBudget(categoryId: String) {
        budgets.removeAll { $0.categoryId == categoryId }
        recalculate()
    }

    private func recalculate() {
        totalBudget = budgets.reduce(0) { $0 + $1.amount }
        totalSpent = budgets.reduce(0) { $0 + $1.spent }
    }
}
