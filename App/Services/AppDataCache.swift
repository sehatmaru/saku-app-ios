import Foundation

@MainActor
final class AppDataCache {
    static let shared = AppDataCache()

    struct DashboardState {
        var balance: Double
        var creditDebt: Double = 0
        var openingBalance: Double
        var totalIncome: Double
        var totalExpense: Double
        var netCashflow: Double
        var recentTransactions: [Transaction]
        var monthlyCashflow: [(String, income: Double, expense: Double)]
        var categorySpending: [(Category, amount: Double)]
        var totalBudget: Double
        var totalSpent: Double
        var currentMonthTransactionCount: Int
        var accounts: [Account]
        var categories: [Category]
        var dailyExpenses: [Double]
        var budgets: [Budget]
        var health: FinancialHealth
        var cardDueTotal: Double = 0
        var upcomingBillsTotal: Double = 0
    }

    struct BudgetState {
        var budgets: [Budget]
        var categories: [Category]
        var allExpenseTransactions: [Transaction]
        var accounts: [Account]
    }

    struct TransactionState {
        var transactions: [Transaction]
        var categories: [Category]
        var accounts: [Account]
    }

    private var dashboardByUserId: [String: DashboardState] = [:]
    private var budgetsByUserId: [String: BudgetState] = [:]
    private var accountsByUserId: [String: [Account]] = [:]
    private var transactionsByUserId: [String: TransactionState] = [:]
    private var accountTransactionsByUserId: [String: [String: [Transaction]]] = [:]

    private init() {}

    func dashboardState(for userId: String) -> DashboardState? { dashboardByUserId[userId] }
    func setDashboardState(_ state: DashboardState, for userId: String) { dashboardByUserId[userId] = state }

    func budgetState(for userId: String) -> BudgetState? { budgetsByUserId[userId] }
    func setBudgetState(_ state: BudgetState, for userId: String) { budgetsByUserId[userId] = state }

    func accounts(for userId: String) -> [Account]? { accountsByUserId[userId] }
    func setAccounts(_ accounts: [Account], for userId: String) { accountsByUserId[userId] = accounts }

    func transactionState(for userId: String) -> TransactionState? { transactionsByUserId[userId] }
    func setTransactionState(_ state: TransactionState, for userId: String) { transactionsByUserId[userId] = state }

    func accountTransactions(for userId: String) -> [String: [Transaction]]? { accountTransactionsByUserId[userId] }
    func setAccountTransactions(_ transactions: [String: [Transaction]], for userId: String) {
        accountTransactionsByUserId[userId] = transactions
    }
}
