import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel = DashboardViewModel()

    var body: some View {
        TabView {
            mainContent
                .tabItem {
                    Label("Beranda", systemImage: "house.fill")
                }

            TransactionListView()
                .tabItem {
                    Label("Transaksi", systemImage: "arrow.left.arrow.right")
                }

            BudgetListView()
                .tabItem {
                    Label("Budget", systemImage: "chart.pie.fill")
                }

            ProfileView()
                .environmentObject(authViewModel)
                .tabItem {
                    Label("Akun", systemImage: "person.fill")
                }
        }
        .tint(.appPrimary)
        .onAppear {
            viewModel.loadDashboard()
        }
    }

    private var mainContent: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    balanceSection
                    cashflowRow
                    insightCard
                    budgetSection
                    recentTransactionsSection
                }
                .padding()
            }
            .background(Color.appGroupedBackground)
            .navigationTitle("SakuQ")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Keluar") {
                        authViewModel.logout()
                    }
                    .foregroundColor(.appError)
                }
            }
        }
    }

    private var balanceSection: some View {
        VStack(spacing: Spacing.sm) {
            Text("Total Saldo")
                .font(.subheadline)
                .foregroundColor(.appTextSecondary)

            Text(viewModel.balance.formattedAsCurrency())
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.appText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var cashflowRow: some View {
        HStack(spacing: Spacing.md) {
            cashflowItem(title: "Pemasukan", amount: viewModel.totalIncome, color: .appIncome)
            Divider().frame(height: 40)
            cashflowItem(title: "Pengeluaran", amount: viewModel.totalExpense, color: .appExpense)
            Divider().frame(height: 40)
            cashflowItem(title: "Cashflow", amount: viewModel.netCashflow, color: viewModel.netCashflow >= 0 ? .appIncome : .appExpense)
        }
        .padding()
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func cashflowItem(title: String, amount: Double, color: Color) -> some View {
        VStack(spacing: Spacing.xs) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.appTextSecondary)
            Text(amount.formattedAsCurrency())
                .font(.caption.weight(.semibold))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }

    private var insightCard: some View {
        HStack {
            Image(systemName: "lightbulb.fill")
                .foregroundColor(.appWarning)
            Text(viewModel.insight)
                .font(.caption)
                .foregroundColor(.appTextSecondary)
            Spacer()
        }
        .padding()
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var budgetSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Budget Bulan Ini")
                .font(.headline)

            ForEach(viewModel.budgets.prefix(3)) { budget in
                BudgetProgressRow(budget: budget)
            }

            if viewModel.budgets.isEmpty {
                Text("Belum ada budget")
                    .font(.subheadline)
                    .foregroundColor(.appTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xl)
            }
        }
        .padding()
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Transaksi Terbaru")
                .font(.headline)

            ForEach(viewModel.recentTransactions.prefix(5)) { transaction in
                TransactionRow(transaction: transaction)
            }

            if viewModel.recentTransactions.isEmpty {
                Text("Belum ada transaksi")
                    .font(.subheadline)
                    .foregroundColor(.appTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xl)
            }
        }
        .padding()
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

}

struct BudgetProgressRow: View {
    let budget: Budget

    var body: some View {
        VStack(spacing: Spacing.xs) {
            HStack {
                Text(Category.sample.first(where: { $0.id == budget.categoryId })?.name ?? "Kategori")
                    .font(.subheadline)
                Spacer()
                Text("\(budget.spent.formattedAsCurrency()) / \(budget.amount.formattedAsCurrency())")
                    .font(.caption)
                    .foregroundColor(.appTextSecondary)
            }

            ProgressView(value: budget.progress)
                .tint(budget.progress >= 1.0 ? .appError : budget.progress >= 0.8 ? .appWarning : .appPrimary)

            if budget.remaining > 0 {
                Text("Sisa \(budget.remaining.formattedAsCurrency())")
                    .font(.caption2)
                    .foregroundColor(.appTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

struct TransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack(spacing: Spacing.md) {
            Circle()
                .fill(transaction.type == .income ? Color.appIncome : Color.appExpense)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: transaction.type == .income ? "arrow.down" : "arrow.up")
                        .font(.caption)
                        .foregroundColor(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.note ?? (transaction.type == .income ? "Pemasukan" : "Pengeluaran"))
                    .font(.subheadline.weight(.medium))
                Text(transaction.date.formatted(date: .numeric, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.appTextSecondary)
            }

            Spacer()

            Text(transaction.amount.formattedAsCurrency())
                .font(.subheadline.weight(.semibold))
                .foregroundColor(transaction.type == .income ? .appIncome : .appExpense)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    DashboardView()
        .environmentObject(AuthViewModel())
}
