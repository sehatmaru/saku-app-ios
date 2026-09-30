import Foundation
import SwiftUI

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var balance: Double = 0
    @Published var creditDebt: Double = 0
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
    /// Expense total per day of the current month, day 1 through today.
    @Published var dailyExpenses: [Double] = []
    /// Budgets with `spent` filled for the current period.
    @Published var budgets: [Budget] = []
    @Published var upcomingSubscriptions: [CardSubscription] = []
    @Published var totalMonthlySubscriptions: Double = 0
    /// Card statements still owed now, across all active cards.
    @Published var cardDueTotal: Double = 0
    /// Cards whose last statement is past due and still owed, the longest overdue first.
    @Published var overdueBills: [OverdueCardBill] = []
    /// Subscriptions charged to cash, bank or e-wallet from today to month end.
    @Published var upcomingBillsTotal: Double = 0
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var hasLoadedOnce = false
    private var loadedUserId: String?

    var totalRemaining: Double { totalBudget - totalSpent }

    /// Balance minus what already has to leave it this month: printed card bills and
    /// subscriptions paid from a wallet.
    var safeToSpend: Double { balance - cardDueTotal - upcomingBillsTotal }

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

    var previousMonthNetCashflow: Double {
        previousMonthIncome - previousMonthExpense
    }

    var netCashflowChange: Double {
        netCashflow - previousMonthNetCashflow
    }

    var incomeChange: Double {
        totalIncome - previousMonthIncome
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

    @Published var errorMessage: String?

    @Published var health = FinancialHealth.empty

    private let calendar = Calendar.current

    func loadDashboard(userId: String, forceRefresh: Bool = false) async {
        guard !isLoading, !isRefreshing else { return }

        if !forceRefresh, let cached = AppDataCache.shared.dashboardState(for: userId) {
            errorMessage = nil
            balance = cached.balance
            creditDebt = cached.creditDebt
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
            dailyExpenses = cached.dailyExpenses
            budgets = cached.budgets
            health = cached.health
            cardDueTotal = cached.cardDueTotal
            overdueBills = cached.overdueBills
            upcomingBillsTotal = cached.upcomingBillsTotal
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
            errorMessage = nil
            async let accountsTask = SupabaseRepository.shared.fetchAccounts(userId: userId)
            async let transactionsTask = SupabaseRepository.shared.fetchTransactions(userId: userId)
            async let categoriesTask = SupabaseRepository.shared.fetchCategories()
            async let budgetsTask = SupabaseRepository.shared.fetchBudgets(userId: userId)

            let (fetchedAccounts, transactions, fetchedCategories, budgets) = try await (accountsTask, transactionsTask, categoriesTask, budgetsTask)
            accounts = fetchedAccounts
            categories = fetchedCategories

            // Subscriptions can sit on any active wallet.
            let activeAccounts = fetchedAccounts.filter(\.isActive)
            let cards = activeAccounts.filter(\.isCreditCard)
            async let subsTask = SupabaseRepository.shared.fetchSubscriptions(accountIds: activeAccounts.map(\.id))
            async let plansTask = SupabaseRepository.shared.fetchInstallments(accountIds: cards.map(\.id))
            let subs = activeAccounts.isEmpty ? [] : ((try? await subsTask) ?? [])
            let installments = (try? await plansTask) ?? []
            let activeSubs = subs.filter { $0.isActive && $0.nextBillingDate != nil }
            upcomingSubscriptions = activeSubs
                .sorted { ($0.nextBillingDate ?? "") < ($1.nextBillingDate ?? "") }
                .prefix(5)
                .map { $0 }
            totalMonthlySubscriptions = activeSubs.reduce(0) { $0 + $1.monthlyAmount }

            let statements = cards.compactMap { CreditStatement(card: $0, transactions: transactions, installments: installments) }
            cardDueTotal = statements.reduce(0) { $0 + $1.remaining + $1.currentPeriod }
            overdueBills = zip(cards, statements)
                .filter { $0.1.status == .overdue }
                .map { OverdueCardBill(card: $0.0, statement: $0.1) }
                .sorted { $0.statement.daysOverdue > $1.statement.daysOverdue }
            let cardIds = Set(cards.map(\.id))
            let monthEnd = calendar.dateInterval(of: .month, for: Date())?.end ?? Date()
            let todayStart = calendar.startOfDay(for: Date())
            upcomingBillsTotal = activeSubs
                .filter { !cardIds.contains($0.accountId) }
                .filter { sub in sub.nextBillingDateAsDate.map { $0 >= todayStart && $0 < monthEnd } ?? false }
                .reduce(0) { $0 + $1.amount }
            await NotificationManager.shared.resyncCardDue(cards: cards, statements: statements)

            // Archived wallets leave the totals, same as on Dompet.
            balance = activeAccounts.filter { !$0.isCreditCard }.reduce(0) { $0 + $1.balance }
            creditDebt = cards.reduce(0) { $0 + $1.balance }

            let thisMonthTransactions = transactions.filter { isCurrentMonth($0.date) }
            currentMonthTransactionCount = thisMonthTransactions.count
            totalIncome = thisMonthTransactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
            totalExpense = thisMonthTransactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
            netCashflow = totalIncome - totalExpense

            openingBalance = balance - netCashflow

            recentTransactions = Array(transactions.prefix(10))

            totalBudget = budgets.reduce(0) { $0 + $1.amount }

            var budgetsWithSpent: [Budget] = []
            for var budget in budgets {
                budget.spent = (try? await SupabaseRepository.shared.fetchBudgetSpent(
                    categoryId: budget.categoryId,
                    userId: userId,
                    startDate: budget.currentPeriodStart(),
                    endDate: budget.currentPeriodEnd()
                )) ?? 0
                budgetsWithSpent.append(budget)
            }
            self.budgets = budgetsWithSpent
            totalSpent = budgetsWithSpent.reduce(0) { $0 + $1.spent }

            // One bar per day of the current period so far, from payday.
            let periodStart = PaydayCycle.current.period(containing: Date(), calendar: calendar).start
            let cal = calendar
            let dayIndex = { (date: Date) in
                cal.dateComponents([.day], from: periodStart, to: cal.startOfDay(for: date)).day ?? 0
            }
            let today = dayIndex(Date()) + 1
            var perDay = Array(repeating: 0.0, count: today)
            for tx in thisMonthTransactions where tx.type == .expense {
                let index = dayIndex(tx.date)
                if index >= 0, index < today { perDay[index] += tx.amount }
            }
            dailyExpenses = perDay

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
            health = computeHealth(transactions: transactions)
            AppDataCache.shared.setDashboardState(.init(
                balance: balance,
                creditDebt: creditDebt,
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
                dailyExpenses: dailyExpenses,
                budgets: self.budgets,
                health: health,
                cardDueTotal: cardDueTotal,
                upcomingBillsTotal: upcomingBillsTotal,
                overdueBills: overdueBills
            ), for: userId)
            loadedUserId = userId
            hasLoadedOnce = true
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
            hasLoadedOnce = true
        }
    }

    /// Scores the last three months (including this one) and today's balances.
    private func computeHealth(transactions: [Transaction]) -> FinancialHealth {
        let now = Date()
        let recent = monthlyCashflow.suffix(3)
        let cards = accounts.filter { $0.isActive && $0.isCreditCard }
        let dayCount = Double(calendar.range(of: .day, in: .month, for: now)?.count ?? 30)
        let startOfToday = calendar.startOfDay(for: now)
        let since = calendar.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfToday
        let activeDays = Set(transactions.filter { $0.date >= since && $0.type != .adjustment }
            .map { calendar.startOfDay(for: $0.date) }).count
        return FinancialHealth(.init(
            monthlyIncome: recent.map(\.income),
            monthlyExpense: recent.map(\.expense),
            liquidBalance: balance,
            creditDebt: max(cards.reduce(0) { $0 + $1.balance }, 0),
            creditLimit: cards.reduce(0) { $0 + ($1.creditLimit ?? 0) },
            hasCreditCard: !cards.isEmpty,
            budgetTotal: totalBudget,
            budgetSpent: totalSpent,
            monthProgress: Double(calendar.component(.day, from: now)) / dayCount,
            activeDays: activeDays,
            topExpenseCategory: categorySpending.first?.0.name,
            hasTransactions: transactions.contains { $0.type == .income || $0.type == .expense },
            overdueBills: overdueBills.map {
                .init(cardName: $0.card.name, amount: $0.statement.remaining, daysLate: $0.statement.daysOverdue)
            }
        ))
    }

    /// "Bulan ini" runs from payday (the calendar month when payday is the 1st).
    private func isCurrentMonth(_ date: Date) -> Bool {
        PaydayCycle.current.contains(date, calendar: calendar)
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


/// A card whose last statement is past due and still owed.
struct OverdueCardBill: Identifiable {
    let card: Account
    let statement: CreditStatement
    var id: String { card.id }
}
