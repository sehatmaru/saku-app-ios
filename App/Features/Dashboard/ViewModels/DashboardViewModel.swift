import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var balance: Double = 0
    @Published var openingBalance: Double = 0
    @Published var totalIncome: Double = 0
    @Published var totalExpense: Double = 0
    @Published var netCashflow: Double = 0
    @Published var recentTransactions: [Transaction] = []
    @Published var monthlyCashflow: [(String, income: Double, expense: Double)] = []
    @Published var categorySpending: [(Category, amount: Double)] = []
    @Published var totalBudget: Double = 0
    @Published var totalSpent: Double = 0

    var totalRemaining: Double { totalBudget - totalSpent }

    // MARK: Financial Health Score

    @Published var healthScore: Int = 0
    @Published var healthScoreLabel: String = ""
    @Published var cashflowScore: Int = 0
    @Published var budgetScore: Int = 0
    @Published var diversityScore: Int = 0

    private let categories = Category.sample
    private let calendar = Calendar.current

    func loadDashboard() {
        let transactions = Transaction.sample
        let budgetList = Budget.sample
        let accountsList = Account.sample

        balance = accountsList.reduce(0) { $0 + $1.balance }

        let thisMonthTransactions = transactions.filter { isCurrentMonth($0.date) }
        totalIncome = thisMonthTransactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        totalExpense = thisMonthTransactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
        netCashflow = totalIncome - totalExpense

        openingBalance = balance - netCashflow

        recentTransactions = transactions.sorted { $0.date > $1.date }

        totalBudget = budgetList.reduce(0) { $0 + $1.amount }
        totalSpent = budgetList.reduce(0) { $0 + $1.spent }

        var categorySpendingMap: [String: Double] = [:]
        for tx in thisMonthTransactions where tx.type == .expense {
            guard let catId = tx.categoryId else { continue }
            categorySpendingMap[catId, default: 0] += tx.amount
        }

        categorySpending = categorySpendingMap
            .sorted { $0.value > $1.value }
            .compactMap { id, amount in
                guard let cat = categories.first(where: { $0.id == id }) else { return nil }
                return (cat, amount)
            }

        monthlyCashflow = computeMonthlyCashflow(transactions: transactions, months: 5)
        computeHealthScore()
    }

    private func computeHealthScore() {
        let savingsRate = totalIncome > 0 ? netCashflow / totalIncome : 0

        if savingsRate >= 0.3 { cashflowScore = 40 }
        else if savingsRate >= 0.2 { cashflowScore = 35 }
        else if savingsRate >= 0.1 { cashflowScore = 25 }
        else if savingsRate >= 0 { cashflowScore = 15 }
        else if savingsRate >= -0.1 { cashflowScore = 10 }
        else { cashflowScore = 0 }

        let budgetHealth = totalBudget > 0 ? totalRemaining / totalBudget : 0
        if budgetHealth >= 0.5 { budgetScore = 35 }
        else if budgetHealth >= 0.25 { budgetScore = 30 }
        else if budgetHealth >= 0 { budgetScore = 20 }
        else if budgetHealth >= -0.2 { budgetScore = 10 }
        else { budgetScore = 0 }

        let categoryCount = categorySpending.count
        if categoryCount >= 5 { diversityScore = 25 }
        else if categoryCount >= 3 { diversityScore = 20 }
        else if categoryCount >= 1 { diversityScore = 10 }
        else { diversityScore = 0 }

        healthScore = cashflowScore + budgetScore + diversityScore

        switch healthScore {
        case 80...100: healthScoreLabel = "Sehat"
        case 60..<80: healthScoreLabel = "Cukup"
        case 40..<60: healthScoreLabel = "Kurang"
        default: healthScoreLabel = "Perlu Perbaikan"
        }
    }

    private func isCurrentMonth(_ date: Date) -> Bool {
        let now = Date()
        return calendar.component(.month, from: date) == calendar.component(.month, from: now)
            && calendar.component(.year, from: date) == calendar.component(.year, from: now)
    }

    private func computeMonthlyCashflow(transactions: [Transaction], months: Int) -> [(String, income: Double, expense: Double)] {
        var result: [(String, income: Double, expense: Double)] = []
        let now = Date()
        for i in (0..<months).reversed() {
            guard let monthDate = calendar.date(byAdding: .month, value: -i, to: now) else { continue }
            let month = calendar.component(.month, from: monthDate)
            let year = calendar.component(.year, from: monthDate)

            let monthTxs = transactions.filter { tx in
                let txMonth = calendar.component(.month, from: tx.date)
                let txYear = calendar.component(.year, from: tx.date)
                return txMonth == month && txYear == year
            }

            let income = monthTxs.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
            let expense = monthTxs.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }

            let label = shortMonthLabel(month, year)
            result.append((label, income, expense))
        }
        return result
    }

    private func shortMonthLabel(_ month: Int, _ year: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        formatter.locale = Locale(identifier: "id_ID")
        guard let date = calendar.date(from: DateComponents(year: year, month: month)) else { return "" }
        return formatter.string(from: date)
    }
}
