import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel = DashboardViewModel()
    @State private var showAddSheet = false

    var body: some View {
        TabView {
            NavigationStack { mainContent }
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

            AccountListView()
                .tabItem {
                    Label("Dompet", systemImage: "wallet.pass.fill")
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
        .sheet(isPresented: $showAddSheet) {
            AddTransactionView()
        }
    }

    private var mainContent: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    balanceSection
                    insightCard
                    budgetSection
                    recentTransactionsSection
                }
                .padding()
            }
            .background(Color.appGroupedBackground)
            .navigationTitle("SakuQ")
        }
    }

    private var balanceSection: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "leaf.fill")
                    .font(.jakarta(12))
                    .foregroundColor(.appPrimary)
                Text("Total Saldo")
                    .font(.jakarta(12))
                    .foregroundColor(.appTextSecondary)
                Spacer()
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xl)

            Text(viewModel.balance.formattedAsCurrency())
                .font(.jakarta(34, weight: .bold))
                .foregroundColor(.appText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.sm)

            Divider()
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.lg)

            HStack(spacing: 0) {
                statItem(title: "Pemasukan", amount: viewModel.totalIncome, color: .appIncome)
                Divider().frame(height: 28)
                statItem(title: "Pengeluaran", amount: viewModel.totalExpense, color: .appExpense)
                Divider().frame(height: 28)
                statItem(title: "Cashflow", amount: viewModel.netCashflow, color: viewModel.netCashflow >= 0 ? .appIncome : .appExpense)
            }
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.lg)

            Button {
                showAddSheet = true
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "plus")
                        .font(.jakarta(15, weight: .semibold))
                    Text("Tambah Transaksi")
                        .font(.jakarta(15, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.appPrimary)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.lg)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.appCardBackground)
        )
        .overlay(alignment: .topTrailing) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 48))
                .foregroundColor(.appPrimary.opacity(0.08))
                .offset(x: -12, y: -4)
        }
    }

    private func statItem(title: String, amount: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.jakarta(11))
                .foregroundColor(.appTextSecondary)
            Text(amount.formattedAsCurrency())
                .font(.jakarta(13, weight: .semibold))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }

    private var insightCard: some View {
        HStack {
            Image(systemName: "lightbulb.fill")
                .foregroundColor(.appWarning)
            Text(viewModel.insight)
                .font(.jakarta(12))
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
                .font(.jakarta(17, weight: .semibold))

            ForEach(viewModel.budgets.prefix(3)) { budget in
                BudgetProgressRow(budget: budget)
            }

            if viewModel.budgets.isEmpty {
                Text("Belum ada budget")
                    .font(.jakarta(15))
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
                .font(.jakarta(17, weight: .semibold))

            ForEach(viewModel.recentTransactions.prefix(5)) { transaction in
                TransactionRow(transaction: transaction)
            }

            if viewModel.recentTransactions.isEmpty {
                Text("Belum ada transaksi")
                    .font(.jakarta(15))
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
                    .font(.jakarta(15))
                Spacer()
                Text("\(budget.spent.formattedAsCurrency()) / \(budget.amount.formattedAsCurrency())")
                    .font(.jakarta(12))
                    .foregroundColor(.appTextSecondary)
            }

            ProgressView(value: budget.progress)
                .tint(budget.progress >= 1.0 ? .appError : budget.progress >= 0.8 ? .appWarning : .appPrimary)

            if budget.remaining > 0 {
                Text("Sisa \(budget.remaining.formattedAsCurrency())")
                    .font(.jakarta(11))
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
                        .font(.jakarta(12))
                        .foregroundColor(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.note ?? (transaction.type == .income ? "Pemasukan" : "Pengeluaran"))
                    .font(.jakarta(15, weight: .medium))
                Text(transaction.date.formatted(date: .numeric, time: .omitted))
                    .font(.jakarta(12))
                    .foregroundColor(.appTextSecondary)
            }

            Spacer()

            Text(transaction.amount.formattedAsCurrency())
                .font(.jakarta(15, weight: .semibold))
                .foregroundColor(transaction.type == .income ? .appIncome : .appExpense)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    DashboardView()
        .environmentObject(AuthViewModel())
}
