import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel = DashboardViewModel()
    @AppStorage("isBalanceVisible") private var isBalanceVisibleStorage = true
    @State private var isBalanceVisible = true
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
            isBalanceVisible = isBalanceVisibleStorage
        }
        .sheet(isPresented: $showAddSheet) {
            AddTransactionView()
        }
    }

    private var mainContent: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    summaryCard
                    analyticsCard
                    budgetCard
                    transactionCard
                }
                .padding()
            }
            .background(Color.appGroupedBackground)
            .navigationTitle("SakuQ")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.smooth) {
                            isBalanceVisible.toggle()
                        }
                        isBalanceVisibleStorage = isBalanceVisible
                    } label: {
                        Image(systemName: isBalanceVisible ? "eye.fill" : "eye.slash.fill")
                            .font(.jakarta(16))
                            .foregroundColor(.appTextSecondary)
                    }
                }
            }
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "leaf.fill")
                    .font(.jakarta(12))
                    .foregroundColor(.appPrimary)
                Text("Saldo Bulan Ini")
                    .font(.jakarta(12))
                    .foregroundColor(.appTextSecondary)
                Spacer()
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xl)

            HStack {
                Text(isBalanceVisible ? viewModel.openingBalance.formattedAsCurrency() : "Rp********")
                    .font(.jakarta(34, weight: .bold))
                    .foregroundColor(.appText)
                    .contentTransition(.numericText())
                Spacer()
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.sm)

            Text("Saldo awal bulan ini")
                .font(.jakarta(11))
                .foregroundColor(.appTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.xl)
                .padding(.top, 2)

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
            Text(isBalanceVisible ? amount.formattedAsCurrency() : "Rp***")
                .font(.jakarta(13, weight: .semibold))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Analytics Card

    private var analyticsCard: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.jakarta(12))
                    .foregroundColor(.appPrimary)
                Text("Analitik")
                    .font(.jakarta(12))
                    .foregroundColor(.appTextSecondary)
                Spacer()
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xl)

            healthScoreSpotlight
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.lg)

            Divider()
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.lg)

            cashflowChart
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.lg)

            if !viewModel.categorySpending.isEmpty {
                Divider()
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.lg)

                spendingChart
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.lg)
            }

            Divider()
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.lg)

            NavigationLink {
                AnalyticsView(viewModel: viewModel)
            } label: {
                HStack(spacing: Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(Color.appPrimary.opacity(0.1))
                            .frame(width: 32, height: 32)
                        Image(systemName: "chart.bar.doc.horizontal")
                            .font(.jakarta(13))
                            .foregroundColor(.appPrimary)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Lihat Selengkapnya")
                            .font(.jakarta(13, weight: .medium))
                            .foregroundColor(.appText)
                        Text("Analisis keuangan lebih detail")
                            .font(.jakarta(10))
                            .foregroundColor(.appTextSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.jakarta(10))
                        .foregroundColor(.appTextSecondary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.appCardBackground)
        )
        .overlay(alignment: .topTrailing) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 48))
                .foregroundColor(.appPrimary.opacity(0.08))
                .offset(x: -12, y: -4)
        }
    }

    // MARK: Charts

    private var cashflowChart: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Cashflow 5 Bulan Terakhir")
                .font(.jakarta(13, weight: .semibold))
                .foregroundColor(.appText)

            let maxAmount = max(
                viewModel.monthlyCashflow.map(\.income).max() ?? 1,
                viewModel.monthlyCashflow.map(\.expense).max() ?? 1
            )
            let barWidth: CGFloat = 10

            HStack(alignment: .bottom, spacing: Spacing.lg) {
                ForEach(viewModel.monthlyCashflow.indices, id: \.self) { idx in
                    let item = viewModel.monthlyCashflow[idx]
                    VStack(spacing: 4) {
                        ZStack(alignment: .bottom) {
                            Color.appGroupedBackground
                                .frame(width: barWidth * 2 + 2, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 4))

                            HStack(alignment: .bottom, spacing: 2) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.appIncome)
                                    .frame(width: barWidth, height: max(2, item.income / maxAmount * 60))
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.appExpense)
                                    .frame(width: barWidth, height: max(2, item.expense / maxAmount * 60))
                            }
                        }

                        Text(item.0)
                            .font(.jakarta(9))
                            .foregroundColor(.appTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 80)

            HStack(spacing: Spacing.md) {
                HStack(spacing: 4) {
                    Circle().fill(Color.appIncome).frame(width: 8, height: 8)
                    Text("Pemasukan")
                        .font(.jakarta(9))
                        .foregroundColor(.appTextSecondary)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.appExpense).frame(width: 8, height: 8)
                    Text("Pengeluaran")
                        .font(.jakarta(9))
                        .foregroundColor(.appTextSecondary)
                }
            }
        }
        .padding(.bottom, Spacing.sm)
    }

    private var spendingChart: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Pengeluaran Bulan Ini")
                .font(.jakarta(13, weight: .semibold))
                .foregroundColor(.appText)

            let total = viewModel.categorySpending.map(\.amount).reduce(0, +)

            ForEach(viewModel.categorySpending.prefix(4), id: \.0.id) { cat, amount in
                HStack(spacing: Spacing.sm) {
                    Image(systemName: cat.icon)
                        .font(.jakarta(11))
                        .foregroundColor(.appPrimary)
                        .frame(width: 20)

                    VStack(spacing: 2) {
                        HStack {
                            Text(cat.name)
                                .font(.jakarta(11))
                                .foregroundColor(.appText)
                            Spacer()
                            Text(amount.formattedAsCurrency())
                                .font(.jakarta(10))
                                .foregroundColor(.appTextSecondary)
                        }
                        ProgressView(value: total > 0 ? amount / total : 0)
                            .tint(.appExpense)
                    }
                }
            }
        }
    }

    // MARK: Health Score

    private var healthScoreSpotlight: some View {
        let color = healthScoreColor(viewModel.healthScore)
        return VStack(spacing: 0) {
            VStack(spacing: Spacing.sm) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Skor Kesehatan Finansial")
                            .font(.jakarta(12))
                            .foregroundColor(.appTextSecondary)
                        Text(viewModel.healthScoreLabel)
                            .font(.jakarta(18, weight: .bold))
                            .foregroundColor(color)
                    }

                    Spacer()

                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(viewModel.healthScore)")
                            .font(.jakarta(40, weight: .bold))
                            .foregroundColor(color)
                        Text("/100")
                            .font(.jakarta(12))
                            .foregroundColor(.appTextSecondary)
                            .padding(.leading, 2)
                    }
                }

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color.opacity(0.12))
                        .frame(height: 18)

                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(
                            colors: [color.opacity(0.7), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: max(0, CGFloat(viewModel.healthScore) / 100) * 280, height: 18)

                    HStack {
                        Spacer()
                        if viewModel.healthScore > 0 {
                            Image(systemName: "figure.walk")
                                .font(.jakarta(10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.trailing, 8)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Spacing.lg)
            .padding(.horizontal, Spacing.xl)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(color.opacity(0.05))

                    RoundedRectangle(cornerRadius: 20)
                        .stroke(color.opacity(0.1), lineWidth: 1)

                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 80))
                        .foregroundColor(color.opacity(0.04))
                        .offset(x: 80, y: -20)
                }
            )

            HStack(spacing: 0) {
                breakdownItem(
                    label: "Arus Kas",
                    score: viewModel.cashflowScore,
                    maxScore: 40
                )
                Divider().frame(height: 32)
                breakdownItem(
                    label: "Budget",
                    score: viewModel.budgetScore,
                    maxScore: 35
                )
                Divider().frame(height: 32)
                breakdownItem(
                    label: "Diversifikasi",
                    score: viewModel.diversityScore,
                    maxScore: 25
                )
            }
            .padding(.vertical, Spacing.md)
            .padding(.horizontal, Spacing.lg)
            .background(Color.appCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .offset(y: -10)
            .padding(.horizontal, Spacing.md)
        }
        .padding(.bottom, Spacing.sm)
    }

    private func breakdownItem(label: String, score: Int, maxScore: Int) -> some View {
        let pct = Double(score) / Double(maxScore)
        let color = healthScoreColor(score * 100 / max(maxScore, 1))
        return VStack(spacing: 4) {
            Text("\(score)/\(maxScore)")
                .font(.jakarta(14, weight: .bold))
                .foregroundColor(.appText)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.12))
                    .frame(height: 6)

                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: max(0, CGFloat(pct)) * 48, height: 6)
            }
            .frame(width: 48)

            Text(label)
                .font(.jakarta(9))
                .foregroundColor(.appTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func healthScoreColor(_ score: Int) -> Color {
        switch score {
        case 80...100: return Color(red: 0.18, green: 0.75, blue: 0.44)
        case 60..<80: return Color(red: 0.20, green: 0.60, blue: 0.95)
        case 40..<60: return Color(red: 0.95, green: 0.60, blue: 0.12)
        default: return Color(red: 0.90, green: 0.30, blue: 0.26)
        }
    }

    // MARK: - Budget Card

    private var budgetCard: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "chart.pie.fill")
                    .font(.jakarta(12))
                    .foregroundColor(.appPrimary)
                Text("Sisa Budget Bulan Ini")
                    .font(.jakarta(12))
                    .foregroundColor(.appTextSecondary)
                Spacer()
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xl)

            HStack(alignment: .top, spacing: Spacing.sm) {
                Text(isBalanceVisible
                     ? (viewModel.totalRemaining >= 0 ? viewModel.totalRemaining.formattedAsCurrency() : "Rp0")
                     : "Rp********")
                    .font(.jakarta(34, weight: .bold))
                    .foregroundColor(.appText)
                Text(viewModel.totalRemaining >= 0 ? "\(Int(viewModel.totalBudget > 0 ? viewModel.totalRemaining / viewModel.totalBudget * 100 : 0))%" : "0%")
                    .font(.jakarta(13, weight: .semibold))
                    .foregroundColor(viewModel.totalRemaining >= 0 ? .appPrimary : .appError)
                    .padding(.top, 4)
                Spacer()
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.sm)

            Divider()
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.lg)

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Total Budget")
                        .font(.jakarta(11))
                        .foregroundColor(.appTextSecondary)
                    Text(isBalanceVisible ? viewModel.totalBudget.formattedAsCurrency() : "Rp********")
                        .font(.jakarta(14, weight: .semibold))
                        .foregroundColor(.appText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Terpakai")
                        .font(.jakarta(11))
                        .foregroundColor(.appTextSecondary)
                    Text(isBalanceVisible ? viewModel.totalSpent.formattedAsCurrency() : "Rp********")
                        .font(.jakarta(14, weight: .semibold))
                        .foregroundColor(.appExpense)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.md)

            ProgressView(value: viewModel.totalBudget > 0 ? min(viewModel.totalSpent / viewModel.totalBudget, 1.0) : 0)
                .tint(viewModel.totalRemaining >= 0 ? .appPrimary : .appError)
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.lg)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.appCardBackground)
        )
        .overlay(alignment: .topTrailing) {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 48))
                .foregroundColor(.appPrimary.opacity(0.08))
                .offset(x: -12, y: -4)
        }
    }

    // MARK: - Transaction Card

    private var transactionCard: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.jakarta(12))
                    .foregroundColor(.appPrimary)
                Text("Net Cashflow Bulan Ini")
                    .font(.jakarta(12))
                    .foregroundColor(.appTextSecondary)
                Spacer()
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xl)

            HStack(spacing: 0) {
                Text("Rp")
                    .font(.jakarta(34, weight: .bold))
                    .foregroundColor(.appText)
                Text(isBalanceVisible
                     ? (viewModel.netCashflow >= 0
                        ? viewModel.netCashflow.formattedAsCurrency().replacingOccurrences(of: "Rp", with: "")
                        : "0")
                     : "********")
                    .font(.jakarta(34, weight: .bold))
                    .foregroundColor(.appText)
                Spacer()
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.sm)

            Divider()
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.lg)

            HStack(spacing: Spacing.md) {
                miniStatCard(
                    label: "Pemasukan",
                    amount: viewModel.totalIncome,
                    color: .appIncome,
                    icon: "arrow.down"
                )
                miniStatCard(
                    label: "Pengeluaran",
                    amount: viewModel.totalExpense,
                    color: .appExpense,
                    icon: "arrow.up"
                )
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.lg)

            if !viewModel.recentTransactions.isEmpty {
                Divider()
                    .padding(.horizontal, Spacing.xl)

                VStack(spacing: 0) {
                    ForEach(Array(viewModel.recentTransactions.prefix(5))) { transaction in
                        TransactionRow(transaction: transaction)
                            .padding(.horizontal, Spacing.xl)
                            .padding(.vertical, Spacing.sm)
                        if transaction.id != viewModel.recentTransactions.prefix(5).last?.id {
                            Divider()
                                .padding(.leading, 72)
                        }
                    }
                }
                .padding(.vertical, Spacing.sm)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.appCardBackground)
        )
        .overlay(alignment: .topTrailing) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 48))
                .foregroundColor(.appPrimary.opacity(0.08))
                .offset(x: -12, y: -4)
        }
    }

    private func miniStatCard(label: String, amount: Double, color: Color, icon: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: icon)
                        .font(.jakarta(11))
                        .foregroundColor(color)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.jakarta(10))
                    .foregroundColor(.appTextSecondary)
                Text(isBalanceVisible ? (amount > 0 ? abbreviatedAmount(amount) : "Rp0") : "Rp***")
                    .font(.jakarta(14, weight: .semibold))
                    .foregroundColor(color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 10)
        .background(color.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func abbreviatedAmount(_ amount: Double) -> String {
        switch amount {
        case 1_000_000_000...:
            String(format: "%.1f Miliar", amount / 1_000_000_000)
        case 1_000_000...:
            String(format: "%.0f Juta", amount / 1_000_000)
        case 1_000...:
            String(format: "%.0f Ribu", amount / 1_000)
        default:
            String(Int(amount))
        }
    }
}

// MARK: - Transaction Row

struct TransactionRow: View {
    let transaction: Transaction

    private var typeColor: Color {
        switch transaction.type {
        case .income: .appIncome
        case .expense: .appExpense
        case .transfer: .appPrimary
        }
    }

    private var typeIcon: String {
        switch transaction.type {
        case .income: "arrow.down"
        case .expense: "arrow.up"
        case .transfer: "arrow.left.arrow.right"
        }
    }

    private var typeLabel: String {
        switch transaction.type {
        case .income: "Pemasukan"
        case .expense: "Pengeluaran"
        case .transfer: "Transfer"
        }
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            Circle()
                .fill(typeColor)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: typeIcon)
                        .font(.jakarta(12))
                        .foregroundColor(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.note ?? typeLabel)
                    .font(.jakarta(15, weight: .medium))
                Text(transaction.date.formatted(date: .numeric, time: .omitted))
                    .font(.jakarta(12))
                    .foregroundColor(.appTextSecondary)
            }

            Spacer()

            Text(transaction.amount.formattedAsCurrency())
                .font(.jakarta(15, weight: .semibold))
                .foregroundColor(typeColor)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    DashboardView()
        .environmentObject(AuthViewModel())
}
