import Foundation

struct TransactionSection: Identifiable {
    let id: String
    let month: Date
    let label: String
    let transactions: [Transaction]
}

@MainActor
final class TransactionListViewModel: ObservableObject {
    @Published var allTransactions: [Transaction] = []
    @Published var categories: [Category] = []
    @Published var accounts: [Account] = []
    @Published var thisMonthIncome: Double = 0
    @Published var thisMonthExpense: Double = 0
    @Published var isLoading = false

    var thisMonthBalance: Double { thisMonthIncome - thisMonthExpense }

    func loadTransactions(userId: String) async {
        isLoading = true
        do {
            async let transactionsTask = SupabaseRepository.shared.fetchTransactions(userId: userId)
            async let categoriesTask = SupabaseRepository.shared.fetchCategories()
            async let accountsTask = SupabaseRepository.shared.fetchAccounts(userId: userId)
            allTransactions = try await transactionsTask
            categories = try await categoriesTask
            accounts = try await accountsTask
            calculateThisMonthSummary()
        } catch {
            allTransactions = []
            categories = []
            accounts = []
        }
        isLoading = false
    }

    private func calculateThisMonthSummary() {
        let calendar = Calendar.current
        let now = Date()
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
              let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return }

        let thisMonth = allTransactions.filter { $0.date >= monthStart && $0.date < nextMonth }
        thisMonthIncome = thisMonth.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        thisMonthExpense = thisMonth.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
    }

    func sections(for transactions: [Transaction]) -> [TransactionSection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: transactions) { tx -> Date in
            calendar.date(from: calendar.dateComponents([.year, .month], from: tx.date))!
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "id_ID")

        let now = Date()
        let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth)!

        return grouped.map { month, items in
            let label: String
            if month == currentMonth {
                formatter.dateFormat = "MMMM yyyy"
                label = "Bulan Ini · \(formatter.string(from: month))"
            } else if month == previousMonth {
                formatter.dateFormat = "MMMM yyyy"
                label = "Bulan Lalu · \(formatter.string(from: month))"
            } else {
                formatter.dateFormat = "MMMM yyyy"
                label = formatter.string(from: month)
            }

            return TransactionSection(
                id: "\(calendar.component(.year, from: month))-\(calendar.component(.month, from: month))",
                month: month,
                label: label,
                transactions: items.sorted { $0.date > $1.date }
            )
        }
        .sorted { $0.month > $1.month }
    }
}
