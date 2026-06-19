import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var balance: Double = 0
    @Published var totalIncome: Double = 0
    @Published var totalExpense: Double = 0
    @Published var netCashflow: Double = 0
    @Published var recentTransactions: [Transaction] = []
    @Published var budgets: [Budget] = []
    @Published var topCategories: [(Category, Double)] = []
    @Published var monthlyTrend: [(String, Double)] = []
    @Published var insight: String = ""
    @Published var accounts: [Account] = []

    private let categories = Category.sample

    func loadDashboard() {
        let transactions = Transaction.sample
        let budgetList = Budget.sample
        let accountsList = Account.sample

        accounts = accountsList
        balance = accountsList.reduce(0) { $0 + $1.balance }
        totalIncome = transactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        totalExpense = transactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
        netCashflow = totalIncome - totalExpense
        recentTransactions = transactions.sorted { $0.date > $1.date }
        budgets = budgetList

        var categorySpending: [String: Double] = [:]
        for tx in transactions where tx.type == .expense {
            guard let catId = tx.categoryId else { continue }
            categorySpending[catId, default: 0] += tx.amount
        }

        topCategories = categorySpending
            .sorted { $0.value > $1.value }
            .compactMap { id, amount in
                guard let cat = categories.first(where: { $0.id == id }) else { return nil }
                return (cat, amount)
            }

        monthlyTrend = [
            ("Jan", 3_500_000), ("Feb", 4_200_000), ("Mar", 3_800_000),
            ("Apr", 4_100_000), ("Mei", 3_900_000), ("Jun", totalExpense)
        ]

        if let top = topCategories.first {
            insight = "Kategori terbesar adalah \(top.0.name) sebesar \(top.1.formattedAsCurrency())"
        }
        if totalExpense > totalIncome {
            insight += " Pengeluaran melebihi pemasukan."
        }
    }
}
