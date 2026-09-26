import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel: DashboardViewModel
    @AppStorage("isBalanceVisible") private var isBalanceVisibleStorage = true

    init(viewModel: DashboardViewModel = DashboardViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    @State private var isBalanceVisible = true
    @State private var showAddSheet = false
    @State private var detailTransaction: Transaction?

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
                    Label("Akun", systemImage: "wallet.pass.fill")
                }

            ProfileView()
                .environmentObject(authViewModel)
                .tabItem {
                    Label("Akun", systemImage: "person.fill")
                }
        }
        .tint(.appPrimary)
        .onAppear {
            isBalanceVisible = isBalanceVisibleStorage
            if let userId = authViewModel.currentUser?.id {
                Task {
                    await SubscriptionBillingService.processDueBills(userId: userId)
                    await SubscriptionBillingService.resyncNotifications(userId: userId)
                    await viewModel.loadDashboard(userId: userId)
                }
            }
        }
        .onChange(of: isBalanceVisibleStorage) { _, newValue in
            isBalanceVisible = newValue
        }
        .onReceive(NotificationCenter.default.publisher(for: .dataDidChange)) { _ in
            if let userId = authViewModel.currentUser?.id {
                Task {
                    await viewModel.loadDashboard(userId: userId, forceRefresh: true)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            if let userId = authViewModel.currentUser?.id {
                AddTransactionView(
                    categories: viewModel.categories,
                    accounts: viewModel.accounts,
                    userId: userId,
                    onSave: {
                        Task {
                            await viewModel.loadDashboard(userId: userId, forceRefresh: true)
                        }
                    }
                )
                .presentationDetents([.fraction(0.68), .large])
            }
        }
        .sheet(item: $detailTransaction) { txn in
            TransactionDetailView(
                transaction: txn,
                categories: viewModel.categories,
                accounts: viewModel.accounts,
                isEditable: false
            )
            .presentationDetents([.medium, .large])
        }
    }

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                if let error = viewModel.errorMessage, !viewModel.hasLoadedOnce {
                    errorStateView(message: error)
                        .transition(.opacity)
                } else if !viewModel.hasLoadedOnce {
                    dashboardSkeleton
                        .transition(.opacity)
                } else {
                    Group {
                        if viewModel.errorMessage != nil {
                            ErrorBanner(message: viewModel.errorMessage!)
                        }
                        summaryCard
                        healthScoreCard
                        statisticsCard
                        budgetCard
                        upcomingBillsCard
                        transactionCard
                    }
                    .transition(.opacity)
                }
            }
            .padding()
            .animation(.easeInOut(duration: 0.3), value: viewModel.hasLoadedOnce)
        }
        .background(Color.appGroupedBackground)
        .refreshable {
            if let userId = authViewModel.currentUser?.id {
                await viewModel.loadDashboard(userId: userId, forceRefresh: true)
            }
        }
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

    private var dashboardSkeleton: some View {
        VStack(spacing: Spacing.lg) {
            skeletonSummary
            skeletonHealthScore
            skeletonStatistics
            skeletonBudget
            skeletonTransaction
        }
    }

    private func skeletonLine(width: CGFloat? = nil) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.appTextSecondary.opacity(0.12))
            .frame(width: width, height: 12)
    }

    private var skeletonSummary: some View {
        VStack(spacing: 0) {
            skeletonLine(width: 120)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.xl)

            RoundedRectangle(cornerRadius: 6)
                .fill(Color.appTextSecondary.opacity(0.1))
                .frame(height: 36)
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.sm)

            skeletonLine(width: 80)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.xl)
                .padding(.top, 4)

            Divider()
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.lg)

            HStack(spacing: 0) {
                ForEach(0..<3) { _ in
                    VStack(spacing: 6) {
                        skeletonLine(width: 50)
                        skeletonLine(width: 70)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.lg)

            RoundedRectangle(cornerRadius: 14)
                .fill(Color.appPrimary.opacity(0.15))
                .frame(height: 46)
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.lg)
        }
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.appCardBackground))
        .shimmer()
    }

    private var skeletonHealthScore: some View {
        VStack(spacing: 0) {
            skeletonLine(width: 160)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.xl)

            VStack(spacing: Spacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        skeletonLine(width: 80)
                        skeletonLine(width: 50)
                    }
                    Spacer()
                    skeletonLine(width: 60)
                }
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.appTextSecondary.opacity(0.08))
                    .frame(height: 18)
            }
            .padding(Spacing.xl)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color.appTextSecondary.opacity(0.05)))

            HStack(spacing: 0) {
                ForEach(0..<3) { _ in
                    VStack(spacing: 6) {
                        skeletonLine(width: 30)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.appTextSecondary.opacity(0.1))
                            .frame(width: 48, height: 6)
                        skeletonLine(width: 40)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, Spacing.md)
            .padding(.horizontal, Spacing.lg)
            .background(Color.appCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .offset(y: -10)
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.sm)
        }
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.appCardBackground))
        .shimmer()
    }

    private var skeletonStatistics: some View {
        VStack(spacing: 0) {
            skeletonLine(width: 140)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.xl)

            HStack(spacing: 0) {
                ForEach(0..<3) { _ in
                    VStack(spacing: 6) {
                        skeletonLine(width: 50)
                        skeletonLine(width: 70)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.md)

            Divider()
                .padding(.horizontal, Spacing.xl)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.md), count: 2), spacing: Spacing.md) {
                ForEach(0..<4) { _ in
                    HStack(spacing: Spacing.sm) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.appTextSecondary.opacity(0.08))
                            .frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 4) {
                            skeletonLine(width: 50)
                            skeletonLine(width: 80)
                        }
                    }
                    .padding(Spacing.sm)
                    .background(Color.appGroupedBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)
        }
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.appCardBackground))
        .shimmer()
    }

    private var skeletonBudget: some View {
        VStack(spacing: 0) {
            skeletonLine(width: 150)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.xl)

            HStack(alignment: .top, spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.appTextSecondary.opacity(0.1))
                    .frame(width: 140, height: 36)
                skeletonLine(width: 40)
                Spacer()
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.sm)

            Divider()
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.lg)

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    skeletonLine(width: 60)
                    skeletonLine(width: 100)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    skeletonLine(width: 50)
                    skeletonLine(width: 100)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.md)

            RoundedRectangle(cornerRadius: 4)
                .fill(Color.appTextSecondary.opacity(0.1))
                .frame(height: 6)
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.lg)
        }
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.appCardBackground))
        .shimmer()
    }

    private var skeletonTransaction: some View {
        VStack(spacing: 0) {
            skeletonLine(width: 160)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.xl)

            RoundedRectangle(cornerRadius: 6)
                .fill(Color.appTextSecondary.opacity(0.1))
                .frame(height: 36)
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.sm)

            Divider()
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.lg)

            HStack(spacing: Spacing.md) {
                ForEach(0..<2) { _ in
                    HStack(spacing: Spacing.sm) {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.appTextSecondary.opacity(0.08))
                            .frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 4) {
                            skeletonLine(width: 50)
                            skeletonLine(width: 70)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 10)
                    .background(Color.appTextSecondary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.lg)
        }
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.appCardBackground))
        .shimmer()
    }

    private func errorStateView(message: String) -> some View {
        ErrorStateView(message: message) {
            if let userId = authViewModel.currentUser?.id {
                Task {
                    await viewModel.loadDashboard(userId: userId, forceRefresh: true)
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
                Text("Total Saldo Saat Ini")
                    .font(.jakarta(12))
                    .foregroundColor(.appTextSecondary)
                Spacer()
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xl)

            HStack {
                Text(isBalanceVisible ? viewModel.balance.formattedAsCurrency() : "Rp********")
                    .font(.jakarta(34, weight: .bold))
                    .foregroundColor(.appText)
                    .contentTransition(.numericText())
                Spacer()
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.sm)

            Divider()
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.lg)

            HStack(spacing: 0) {
                statItem(title: "Pemasukan Bulan Ini", amount: viewModel.totalIncome, color: .appIncome, diff: viewModel.incomeChange, lastMonth: viewModel.previousMonthIncome)
                Divider().frame(height: 28)
                statItem(title: "Pengeluaran Bulan Ini", amount: viewModel.totalExpense, color: .appExpense, diff: viewModel.expenseChange, lastMonth: viewModel.previousMonthExpense)
                Divider().frame(height: 28)
                statItem(title: "Net Cashflow", amount: viewModel.netCashflow, color: viewModel.netCashflow >= 0 ? .appIncome : .appExpense, diff: viewModel.netCashflowChange, lastMonth: viewModel.previousMonthNetCashflow)
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

    private func statItem(title: String, amount: Double, color: Color, diff: Double? = nil, lastMonth: Double? = nil) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.jakarta(11))
                .foregroundColor(.appTextSecondary)
            Text(isBalanceVisible ? abbreviatedAmount(amount) : "Rp******")
                .font(.jakarta(13, weight: .semibold))
                .foregroundColor(color)

            if let diff, let lastMonth, lastMonth > 0 {
                let pct = diff / lastMonth * 100
                HStack(spacing: 2) {
                    Image(systemName: diff >= 0 ? "arrow.up" : "arrow.down")
                        .font(.jakarta(7, weight: .bold))
                    Text("\(abs(pct), specifier: "%.1f")%")
                        .font(.jakarta(9, weight: .medium))
                }
                .foregroundColor(diff >= 0 ? color : .appExpense)
            }
        }
        .frame(maxWidth: .infinity)
    }



    private func recapItem(icon: String, iconColor: Color, title: String, value: String, subtitle: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.jakarta(10))
                .foregroundColor(iconColor)
                .frame(width: 28, height: 28)
                .background(iconColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.jakarta(10))
                    .foregroundColor(.appTextSecondary)
                Text(isBalanceVisible ? value : "***")
                    .font(.jakarta(13, weight: .semibold))
                    .foregroundColor(iconColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(subtitle)
                    .font(.jakarta(8))
                    .foregroundColor(.appTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Health Score Card

    private var healthScoreCard: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "heart.fill")
                    .font(.jakarta(12))
                    .foregroundColor(.appPrimary)
                Text("Skor Kesehatan Finansial")
                    .font(.jakarta(12))
                    .foregroundColor(.appTextSecondary)
                Spacer()
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xl)

            healthScoreSpotlight
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.lg)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.appCardBackground)
        )
        .overlay(alignment: .topTrailing) {
            Image(systemName: "heart.fill")
                .font(.system(size: 48))
                .foregroundColor(.appPrimary.opacity(0.08))
                .offset(x: -12, y: -4)
        }
    }

    // MARK: - Statistics Card

    private var statisticsCard: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.jakarta(12))
                    .foregroundColor(.appPrimary)
                Text("Statistik Bulan Ini")
                    .font(.jakarta(12))
                    .foregroundColor(.appTextSecondary)
                Spacer()
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xl)

            HStack(spacing: 0) {
                statItem(title: "Pemasukan", amount: viewModel.totalIncome, color: .appIncome)
                Divider().frame(height: 36)
                statItem(title: "Pengeluaran", amount: viewModel.totalExpense, color: .appExpense)
                Divider().frame(height: 36)
                statItem(title: "Cashflow", amount: viewModel.netCashflow, color: viewModel.netCashflow >= 0 ? .appIncome : .appExpense)
            }
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.md)

            Divider()
                .padding(.horizontal, Spacing.xl)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.md), count: 2), spacing: Spacing.md) {
                statInfoCard(
                    icon: "calendar.day.timeline.left",
                    label: "Rata-rata Harian",
                    value: viewModel.averageDailySpending.formattedAsCurrency(),
                    color: .appPrimary
                )
                statInfoCard(
                    icon: "arrow.left.arrow.right",
                    label: "Total Transaksi",
                    value: "\(viewModel.currentMonthTransactionCount) kali",
                    color: .blue
                )
                statInfoCard(
                    icon: "tag.fill",
                    label: "Kategori Tertinggi",
                    value: viewModel.topCategoryName,
                    subvalue: "\(Int(viewModel.topCategoryPct))% pengeluaran",
                    color: .appWarning
                )
                statInfoCard(
                    icon: "chart.pie.fill",
                    label: "Sisa Budget",
                    value: viewModel.totalBudget > 0 ? "\(Int(max(0, viewModel.totalRemaining / viewModel.totalBudget * 100)))%" : "-",
                    color: viewModel.totalRemaining >= 0 ? .appIncome : .appError
                )
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)

            if !viewModel.financialTips.isEmpty {
                Divider()
                    .padding(.horizontal, Spacing.xl)

                financialTipsSection
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.sm)
            }

            Divider()
                .padding(.horizontal, Spacing.xl)

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

    private func statInfoCard(icon: String, label: String, value: String, subvalue: String? = nil, color: Color) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.jakarta(12))
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.jakarta(9))
                    .foregroundColor(.appTextSecondary)
                Text(value)
                    .font(.jakarta(12, weight: .semibold))
                    .foregroundColor(.appText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let subvalue = subvalue {
                    Text(subvalue)
                        .font(.jakarta(8))
                        .foregroundColor(color)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background(Color.appGroupedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Financial Tips

    private var financialTipsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: 4) {
                Image(systemName: "lightbulb.fill")
                    .font(.jakarta(11))
                    .foregroundColor(.appWarning)
                Text("Tips Finansial")
                    .font(.jakarta(13, weight: .semibold))
                    .foregroundColor(.appText)
            }

            ForEach(viewModel.financialTips.prefix(2)) { tip in
                HStack(spacing: Spacing.sm) {
                    Image(systemName: tip.icon)
                        .font(.jakarta(10))
                        .foregroundColor(tip.type.color)
                        .frame(width: 24, height: 24)
                        .background(tip.type.bgColor)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Text(tip.message)
                        .font(.jakarta(11))
                        .foregroundColor(.appTextSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.bottom, Spacing.sm)
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
                    Image(systemName: cat.icon ?? "tag")
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

    // MARK: - Upcoming Bills Card

    private var upcomingBillsCard: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "repeat")
                    .font(.jakarta(12))
                    .foregroundColor(.appPrimary)
                Text("Tagihan Terdekat")
                    .font(.jakarta(12))
                    .foregroundColor(.appTextSecondary)
                Spacer()
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xl)

            if viewModel.upcomingSubscriptions.isEmpty {
                Text("Belum ada tagihan berulang")
                    .font(.jakarta(13))
                    .foregroundColor(.appTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.lg)
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.upcomingSubscriptions) { sub in
                        HStack(spacing: Spacing.sm) {
                            ZStack {
                                Circle()
                                    .fill(Color.appExpense.opacity(0.1))
                                    .frame(width: 34, height: 34)
                                Image(systemName: "creditcard.fill")
                                    .font(.jakarta(12))
                                    .foregroundColor(.appExpense)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sub.name)
                                    .font(.jakarta(14, weight: .semibold))
                                    .foregroundColor(.appText)
                                    .lineLimit(1)
                                Text("\(accountName(for: sub.accountId)) • \(sub.billingDateString)")
                                    .font(.jakarta(10))
                                    .foregroundColor(.appTextSecondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Text(isBalanceVisible ? sub.amount.formattedAsCurrency() : "Rp******")
                                .font(.jakarta(13, weight: .semibold))
                                .foregroundColor(.appText)
                        }
                        .padding(.horizontal, Spacing.xl)
                        .padding(.vertical, 10)
                        if sub.id != viewModel.upcomingSubscriptions.last?.id {
                            Divider().padding(.leading, Spacing.xl + 46)
                        }
                    }
                }
                .padding(.top, Spacing.sm)

                Divider()
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.sm)

                HStack {
                    Text("Total per bulan")
                        .font(.jakarta(11))
                        .foregroundColor(.appTextSecondary)
                    Spacer()
                    Text(isBalanceVisible ? viewModel.totalMonthlySubscriptions.formattedAsCurrency() : "Rp******")
                        .font(.jakarta(13, weight: .semibold))
                        .foregroundColor(.appExpense)
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.md)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.appCardBackground)
        )
    }

    private func accountName(for id: String) -> String {
        viewModel.accounts.first(where: { $0.id == id })?.name ?? "Kartu Kredit"
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
                     ? viewModel.netCashflow.formattedAsCurrency().replacingOccurrences(of: "Rp", with: "")
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
                        TransactionRow(transaction: transaction, categories: viewModel.categories, accounts: viewModel.accounts, showWalletBadge: true)
                            .contentShape(Rectangle())
                            .onTapGesture { detailTransaction = transaction }
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
                Text(isBalanceVisible ? abbreviatedAmount(amount) : "Rp******")
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
        let prefix = amount < 0 ? "-" : (amount > 0 ? "" : "")
        let absVal = abs(amount)
        let formatted: String
        switch absVal {
        case 1_000_000_000...:
            formatted = String(format: "%.1f Miliar", absVal / 1_000_000_000)
        case 1_000_000...:
            formatted = String(format: "%.0f Juta", absVal / 1_000_000)
        case 1_000...:
            formatted = String(format: "%.0f Ribu", absVal / 1_000)
        default:
            formatted = String(Int(absVal))
        }
        return "\(prefix)\(formatted)"
    }
}

// MARK: - Transaction Row

struct TransactionRow: View {
    let transaction: Transaction
    let categories: [Category]
    let accounts: [Account]
    var showWalletBadge: Bool = false

    var body: some View {
        TransactionRowView(
            transaction: transaction,
            categories: categories,
            accounts: accounts,
            showWalletBadge: showWalletBadge
        )
    }
}
