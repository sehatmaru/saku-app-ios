import Foundation
import SwiftUI

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
    @Published var currentMonthTransactionCount = 0
    @Published var accounts: [Account] = []
    @Published var categories: [Category] = []
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var hasLoadedOnce = false
    private var loadedUserId: String?

    var totalRemaining: Double { totalBudget - totalSpent }

    var averageDailySpending: Double {
        let now = Date()
        let days = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        return totalExpense / Double(days)
    }

    var savingsRate: Double {
        totalIncome > 0 ? netCashflow / totalIncome : 0
    }

    var previousMonthIncome: Double {
        monthlyCashflow.dropLast().last?.income ?? 0
    }

    var previousMonthExpense: Double {
        monthlyCashflow.dropLast().last?.expense ?? 0
    }

    var expenseChange: Double {
        totalExpense - previousMonthExpense
    }

    var expenseChangePct: Double {
        previousMonthExpense > 0 ? (expenseChange / previousMonthExpense) * 100 : 0
    }

    var topCategoryName: String {
        categorySpending.first?.0.name ?? "-"
    }

    var topCategoryPct: Double {
        let total = categorySpending.map(\.amount).reduce(0, +)
        guard total > 0, let top = categorySpending.first else { return 0 }
        return top.amount / total * 100
    }

    var financialTips: [TipItem] {
        var tips: [TipItem] = []

        let savingsRate = totalIncome > 0 ? netCashflow / totalIncome : 0

        if savingsRate < -0.1 {
            tips.append(TipItem(
                icon: "exclamationmark.triangle.fill",
                message: "Pengeluaran jauh melebihi pemasukan. Segera evaluasi kebiasaan belanja Anda.",
                type: .warning
            ))
        } else if savingsRate < 0 {
            tips.append(TipItem(
                icon: "arrow.up.forward",
                message: "Pengeluaran sedikit melebihi pemasukan. Coba catat pengeluaran harian untuk menemukan pos yang bisa dikurangi.",
                type: .warning
            ))
        } else if savingsRate < 0.1 {
            tips.append(TipItem(
                icon: "chart.line.uptrend.xyaxis",
                message: "Coba tingkatkan tabungan hingga minimal 10% dari pemasukan untuk kondisi finansial yang lebih sehat.",
                type: .info
            ))
        } else if savingsRate >= 0.3 {
            tips.append(TipItem(
                icon: "star.fill",
                message: "Anda berhasil menabung lebih dari 30% pemasukan. Pertahankan kebiasaan baik ini!",
                type: .success
            ))
        }

        let remainingRatio = totalBudget > 0 ? totalRemaining / totalBudget : 0
        if remainingRatio < -0.2 {
            tips.append(TipItem(
                icon: "exclamationmark.triangle.fill",
                message: "Anggaran telah terlampaui jauh. Tinjau kembali alokasi budget bulan depan.",
                type: .warning
            ))
        } else if remainingRatio < 0 {
            tips.append(TipItem(
                icon: "clock.fill",
                message: "Anggaran bulan ini sudah habis. Hindari pengeluaran tambahan yang tidak perlu.",
                type: .warning
            ))
        } else if remainingRatio < 0.25 && totalBudget > 0 {
            tips.append(TipItem(
                icon: "clock.fill",
                message: "Sisa budget bulan ini tinggal sedikit. Coba hemat pengeluaran yang tidak terlalu penting.",
                type: .info
            ))
        } else if remainingRatio >= 0.5 && totalBudget > 0 {
            tips.append(TipItem(
                icon: "hand.thumbsup.fill",
                message: "Pengelolaan budget sangat baik! Anda masih memiliki sisa lebih dari 50%.",
                type: .success
            ))
        }

        if let topCategory = categorySpending.first {
            let totalSpending = categorySpending.map(\.amount).reduce(0, +)
            if totalSpending > 0 {
                let topRatio = topCategory.amount / totalSpending
                if topRatio > 0.5 {
                    tips.append(TipItem(
                        icon: "chart.pie.fill",
                        message: "Pengeluaran didominasi oleh \(topCategory.0.name) (\(Int(topRatio * 100))%). Coba diversifikasi pola pengeluaran Anda.",
                        type: .info
                    ))
                }
            }
        }

        if tips.isEmpty {
            tips.append(TipItem(
                icon: "sparkles",
                message: "Kondisi finansial Anda cukup stabil. Pantau terus pengeluaran untuk hasil terbaik.",
                type: .success
            ))
        }

        return tips
    }

    @Published var healthScore: Int = 0
    @Published var healthScoreLabel: String = ""
    @Published var cashflowScore: Int = 0
    @Published var budgetScore: Int = 0
    @Published var diversityScore: Int = 0

    private let calendar = Calendar.current

    func loadDashboard(userId: String, forceRefresh: Bool = false) async {
        guard !isLoading, !isRefreshing else { return }

        if !forceRefresh, let cached = AppDataCache.shared.dashboardState(for: userId) {
            balance = cached.balance
            openingBalance = cached.openingBalance
            totalIncome = cached.totalIncome
            totalExpense = cached.totalExpense
            netCashflow = cached.netCashflow
            recentTransactions = cached.recentTransactions
            monthlyCashflow = cached.monthlyCashflow
            categorySpending = cached.categorySpending
            totalBudget = cached.totalBudget
            totalSpent = cached.totalSpent
            currentMonthTransactionCount = cached.currentMonthTransactionCount
            accounts = cached.accounts
            categories = cached.categories
            healthScore = cached.healthScore
            healthScoreLabel = cached.healthScoreLabel
            cashflowScore = cached.cashflowScore
            budgetScore = cached.budgetScore
            diversityScore = cached.diversityScore
            loadedUserId = userId
            hasLoadedOnce = true
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
            async let accountsTask = SupabaseRepository.shared.fetchAccounts(userId: userId)
            async let transactionsTask = SupabaseRepository.shared.fetchTransactions(userId: userId)
            async let categoriesTask = SupabaseRepository.shared.fetchCategories()
            async let budgetsTask = SupabaseRepository.shared.fetchBudgets(userId: userId)

            let (fetchedAccounts, transactions, fetchedCategories, budgets) = try await (accountsTask, transactionsTask, categoriesTask, budgetsTask)
            accounts = BalanceCalculator.applyBalances(to: fetchedAccounts, from: transactions)
            categories = fetchedCategories

            balance = accounts.reduce(0) { $0 + $1.balance }

            let thisMonthTransactions = transactions.filter { isCurrentMonth($0.date) }
            currentMonthTransactionCount = thisMonthTransactions.count
            totalIncome = thisMonthTransactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
            totalExpense = thisMonthTransactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
            netCashflow = totalIncome - totalExpense

            openingBalance = balance - netCashflow

            recentTransactions = Array(transactions.prefix(10))

            totalBudget = budgets.reduce(0) { $0 + $1.amount }
            totalSpent = budgets.reduce(0) { $0 + $1.spent }

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
            AppDataCache.shared.setDashboardState(.init(
                balance: balance,
                openingBalance: openingBalance,
                totalIncome: totalIncome,
                totalExpense: totalExpense,
                netCashflow: netCashflow,
                recentTransactions: recentTransactions,
                monthlyCashflow: monthlyCashflow,
                categorySpending: categorySpending,
                totalBudget: totalBudget,
                totalSpent: totalSpent,
                currentMonthTransactionCount: currentMonthTransactionCount,
                accounts: accounts,
                categories: categories,
                healthScore: healthScore,
                healthScoreLabel: healthScoreLabel,
                cashflowScore: cashflowScore,
                budgetScore: budgetScore,
                diversityScore: diversityScore
            ), for: userId)
            loadedUserId = userId
            hasLoadedOnce = true
        } catch {
            // Keep the last rendered data when refresh fails.
            hasLoadedOnce = true
        }
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

struct TipItem: Identifiable {
    let id = UUID()
    let icon: String
    let message: String
    let type: TipType

    enum TipType {
        case success
        case info
        case warning

        var color: Color {
            switch self {
            case .success: Color(red: 0.18, green: 0.75, blue: 0.44)
            case .info: Color(red: 0.20, green: 0.60, blue: 0.95)
            case .warning: Color(red: 0.95, green: 0.60, blue: 0.12)
            }
        }

        var bgColor: Color {
            color.opacity(0.1)
        }
    }
}
