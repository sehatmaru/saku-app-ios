import Foundation

@MainActor
final class BudgetListViewModel: ObservableObject {
    @Published var budgets: [Budget] = []
    @Published var totalBudget: Double = 0
    @Published var totalSpent: Double = 0

    func loadBudgets() {
        let list = Budget.sample
        budgets = list
        totalBudget = list.reduce(0) { $0 + $1.amount }
        totalSpent = list.reduce(0) { $0 + $1.spent }
    }
}
