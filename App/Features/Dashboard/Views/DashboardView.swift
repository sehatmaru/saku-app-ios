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
    @State private var selectedTab: AppTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { mainContent }
                .tag(AppTab.home)
                .toolbar(.hidden, for: .tabBar)

            TransactionListView()
                .tag(AppTab.transactions)
                .toolbar(.hidden, for: .tabBar)

            BudgetListView()
                .tag(AppTab.budget)
                .toolbar(.hidden, for: .tabBar)

            AccountListView()
                .tag(AppTab.wallet)
                .toolbar(.hidden, for: .tabBar)

            ProfileView()
                .environmentObject(authViewModel)
                .tag(AppTab.profile)
                .toolbar(.hidden, for: .tabBar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FloatingTabBar(selection: $selectedTab) { showAddSheet = true }
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

    // MARK: - Beranda

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                homeHeader

                if let error = viewModel.errorMessage, !viewModel.hasLoadedOnce {
                    errorStateView(message: error)
                        .padding(24)
                } else if !viewModel.hasLoadedOnce {
                    homeSkeleton
                } else {
                    if let error = viewModel.errorMessage {
                        ErrorBanner(message: error).padding(.horizontal, 24).padding(.top, 16)
                    }
                    summarySection
                    SectionDivider()
                    healthSection
                    SectionDivider()
                    statisticsSection
                    SectionDivider()
                    budgetSection
                    SectionDivider()
                    billsSection
                    SectionDivider()
                    cashflowSection
                }
            }
            .animation(.easeInOut(duration: 0.3), value: viewModel.hasLoadedOnce)
        }
        .background(Color.appBackground)
        .refreshable {
            if let userId = authViewModel.currentUser?.id {
                await viewModel.loadDashboard(userId: userId, forceRefresh: true)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var homeHeader: some View {
        HStack {
            Text(Self.headerDateFormatter.string(from: Date()))
                .font(.app(15))
                .foregroundStyle(Color.appTextSecondary)
            Spacer()
            Button {
                withAnimation(.smooth) { isBalanceVisible.toggle() }
                isBalanceVisibleStorage = isBalanceVisible
            } label: {
                Image(systemName: isBalanceVisible ? "eye" : "eye.slash")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.appText)
            }
            .accessibilityLabel(isBalanceVisible ? "Sembunyikan saldo" : "Tampilkan saldo")
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
    }

    private var homeSkeleton: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach([120, 260, 200, 0, 160, 300, 240], id: \.self) { width in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.appFill)
                    .frame(maxWidth: width == 0 ? .infinity : CGFloat(width))
                    .frame(height: width == 260 ? 48 : 14)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 36)
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

    // MARK: Summary

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Total saldo")
                .font(.app(15))
                .foregroundStyle(Color.appTextSecondary)
            HeroAmount(value: viewModel.balance, isVisible: isBalanceVisible)
                .padding(.top, 6)

            HStack(alignment: .top, spacing: 28) {
                flowStat("Masuk", amount: viewModel.totalIncome, change: viewModel.incomeChange, base: viewModel.previousMonthIncome)
                flowStat("Keluar", amount: viewModel.totalExpense, change: viewModel.expenseChange, base: viewModel.previousMonthExpense, highlightsGrowth: false)
                flowStat("Net", amount: viewModel.netCashflow, change: viewModel.netCashflowChange, base: abs(viewModel.previousMonthNetCashflow), signed: true)
            }
            .padding(.top, 22)

            Button { showAddSheet = true } label: {
                Label("Tambah transaksi", systemImage: "plus")
                    .font(.app(16, weight: .medium))
                    .foregroundStyle(Color.appText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .overlay(Capsule().strokeBorder(Color.appBorder))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 24)
        }
        .padding(.horizontal, 24)
        .padding(.top, 36)
        .padding(.bottom, 28)
    }

    /// Label, abbreviated amount and month-over-month change; growth is green unless it's spending.
    private func flowStat(_ label: String, amount: Double, change: Double, base: Double, highlightsGrowth: Bool = true, signed: Bool = false) -> some View {
        let valueColor: Color = signed && amount > 0 ? .appIncome : .appText
        let sign = signed ? (amount > 0 ? "+" : amount < 0 ? "−" : "") : ""
        return VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.app(13))
                .foregroundStyle(Color.appTextSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(isBalanceVisible ? sign + amount.abbreviatedRupiah() : hiddenAmount)
                    .font(.app(17, weight: .medium))
                    .foregroundStyle(valueColor)
                if base > 0 {
                    let pct = Int((change / base * 100).rounded())
                    Text((pct >= 0 ? "+" : "−") + "\(abs(pct))%")
                        .font(.app(13))
                        .foregroundStyle(signed ? (amount > 0 ? Color.appIncome : Color.appTextSecondary) : (highlightsGrowth && pct > 0 ? Color.appIncome : Color.appTextSecondary))
                }
            }
            .monospacedDigit()
        }
    }

    // MARK: Health score

    private var healthSection: some View {
        let score = viewModel.healthScore
        let filled = score * 40 / 100
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Kesehatan finansial", trailing: viewModel.healthScoreLabel, trailingColor: healthColor(score))

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(score)")
                    .font(.app(56, weight: .light))
                    .tracking(-2)
                Text("/ 100")
                    .font(.app(17))
                    .foregroundStyle(Color.appTextSecondary)
            }
            .padding(.top, 14)

            HStack(spacing: 3) {
                ForEach(0..<40, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(i < filled ? healthColor(score) : Color.appDivider)
                }
            }
            .frame(height: 22)
            .padding(.top, 16)
            .accessibilityHidden(true)

            HStack(spacing: 0) {
                scorePart("Arus kas", viewModel.cashflowScore, of: 40)
                scorePart("Budget", viewModel.budgetScore, of: 35)
                scorePart("Diversifikasi", viewModel.diversityScore, of: 25)
            }
            .padding(.top, 18)
        }
        .padding(24)
        .padding(.vertical, 4)
    }

    private func scorePart(_ label: String, _ score: Int, of max: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.app(13))
                .foregroundStyle(Color.appTextSecondary)
            (Text("\(score)").foregroundStyle(Color.appText) + Text("/\(max)").foregroundStyle(Color.appTextTertiary))
                .font(.app(17))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func healthColor(_ score: Int) -> Color {
        switch score {
        case 60...: .appPrimary
        case 40..<60: .appWarning
        default: .appError
        }
    }

    // MARK: Statistics

    private var statisticsSection: some View {
        let remainingPct = viewModel.totalBudget > 0
            ? "\(Int(max(0, viewModel.totalRemaining / viewModel.totalBudget * 100)))%" : "-"
        let topCategory = viewModel.categorySpending.isEmpty
            ? "-" : "\(viewModel.topCategoryName) · \(Int(viewModel.topCategoryPct))%"
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "Statistik bulan ini")
                NavigationLink("Analisis") { AnalyticsView(viewModel: viewModel) }
                    .font(.app(15))
                    .foregroundStyle(Color.appPrimary)
            }

            VStack(spacing: 0) {
                statRow("Rata-rata harian", isBalanceVisible ? viewModel.averageDailySpending.formattedAsCurrency() : "Rp" + hiddenAmount)
                statRow("Total transaksi", "\(viewModel.currentMonthTransactionCount)")
                statRow("Kategori tertinggi", topCategory)
                statRow("Sisa budget", remainingPct)
            }
            .padding(.top, 8)

            let tips = viewModel.financialTips.prefix(2)
            if !tips.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(tips) { tip in
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(tipColor(tip.type))
                                .frame(width: 2)
                            Text(tip.message)
                                .font(.app(15))
                                .lineSpacing(3)
                                .foregroundStyle(Color.appBody)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 20)
            }
        }
        .padding(24)
        .padding(.vertical, 4)
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.app(16))
                .foregroundStyle(Color.appTextSecondary)
            Spacer()
            Text(value)
                .font(.app(16, weight: .medium))
                .foregroundStyle(Color.appText)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
        .padding(.vertical, 14)
        .rowSeparator()
    }

    private func tipColor(_ type: TipItem.TipType) -> Color {
        switch type {
        case .success: .appPrimary
        case .info: .appTextTertiary
        case .warning: .appWarning
        }
    }

    // MARK: Budget

    private var budgetSection: some View {
        let over = viewModel.totalRemaining < 0
        let pct = viewModel.totalBudget > 0 ? Int(max(0, viewModel.totalRemaining / viewModel.totalBudget * 100)) : 0
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Sisa budget", trailing: "\(pct)%", trailingColor: over ? .appError : .appTextSecondary)

            HeroAmount(value: max(0, viewModel.totalRemaining), size: .medium, isVisible: isBalanceVisible)
                .padding(.top, 14)

            ThinProgress(
                value: viewModel.totalBudget > 0 ? viewModel.totalSpent / viewModel.totalBudget : 0,
                color: over ? .appError : .appText
            )
            .padding(.top, 18)

            HStack {
                Text("Terpakai " + (isBalanceVisible ? viewModel.totalSpent.formattedAsCurrency() : "Rp" + hiddenAmount))
                Spacer()
                Text("Budget " + (isBalanceVisible ? viewModel.totalBudget.formattedAsCurrency() : "Rp" + hiddenAmount))
            }
            .font(.app(13))
            .foregroundStyle(Color.appTextSecondary)
            .monospacedDigit()
            .padding(.top, 10)
        }
        .padding(24)
        .padding(.vertical, 4)
    }

    // MARK: Bills

    private var billsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(
                title: "Tagihan terdekat",
                trailing: viewModel.upcomingSubscriptions.isEmpty ? nil
                    : (isBalanceVisible ? viewModel.totalMonthlySubscriptions.formattedAsCurrency() : "Rp" + hiddenAmount) + "/bln"
            )

            if viewModel.upcomingSubscriptions.isEmpty {
                Text("Belum ada tagihan berulang")
                    .font(.app(15))
                    .foregroundStyle(Color.appTextSecondary)
                    .padding(.top, 14)
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.upcomingSubscriptions) { sub in
                        billRow(sub)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(24)
        .padding(.vertical, 4)
    }

    private func billRow(_ sub: CardSubscription) -> some View {
        let date = sub.nextBillingDateAsDate
        let daysLeft = date.map { Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: $0).day ?? 0 } ?? 99
        return HStack(spacing: 16) {
            VStack(spacing: 3) {
                Text(date.map { Self.dayFormatter.string(from: $0) } ?? "-")
                    .font(.app(22, weight: .light))
                    .monospacedDigit()
                Text(date.map { Self.monthFormatter.string(from: $0).uppercased() } ?? "")
                    .font(.app(11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(daysLeft <= 2 ? Color.appWarning : Color.appTextSecondary)
            }
            .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(sub.name)
                    .font(.app(16, weight: .medium))
                    .lineLimit(1)
                Text(accountName(for: sub.accountId))
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(isBalanceVisible ? sub.amount.formattedAsCurrency() : "Rp" + hiddenAmount)
                .font(.app(16))
                .monospacedDigit()
        }
        .foregroundStyle(Color.appText)
        .padding(.vertical, 14)
        .rowSeparator()
    }

    private func accountName(for id: String) -> String {
        viewModel.accounts.first(where: { $0.id == id })?.name ?? "Kartu Kredit"
    }

    // MARK: Cashflow + recent transactions

    private var cashflowSection: some View {
        let net = viewModel.netCashflow
        let recent = Array(viewModel.recentTransactions.prefix(5))
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Net cashflow", trailing: "Semua transaksi", trailingColor: .appPrimary) {
                selectedTab = .transactions
            }

            HeroAmount(
                value: net,
                size: .medium,
                prefix: net > 0 ? "+Rp" : net < 0 ? "−Rp" : "Rp",
                color: net > 0 ? .appIncome : .appText,
                prefixColor: net > 0 ? .appIncome : .appTextSecondary,
                isVisible: isBalanceVisible
            )
            .padding(.top, 14)

            HStack(spacing: 28) {
                flowTotal("Masuk", viewModel.totalIncome)
                flowTotal("Keluar", viewModel.totalExpense)
            }
            .padding(.top, 12)

            ForEach(Array(recent.enumerated()), id: \.element.id) { index, transaction in
                if index == 0 || !Calendar.current.isDate(transaction.date, inSameDayAs: recent[index - 1].date) {
                    Text(Self.dayHeader(for: transaction.date))
                        .font(.app(13))
                        .tracking(0.2)
                        .foregroundStyle(Color.appTextSecondary)
                        .padding(.top, index == 0 ? 28 : 22)
                }
                Button { detailTransaction = transaction } label: {
                    TransactionRowView(
                        transaction: transaction,
                        categories: viewModel.categories,
                        accounts: viewModel.accounts,
                        showBalance: isBalanceVisible,
                        showAccount: true,
                        showDate: false
                    )
                    .rowSeparator()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 24)
    }

    private func flowTotal(_ label: String, _ amount: Double) -> some View {
        (Text(label + " ").foregroundStyle(Color.appTextSecondary)
            + Text(isBalanceVisible ? amount.abbreviatedRupiah() : hiddenAmount)
                .fontWeight(.medium)
                .foregroundStyle(Color.appText))
            .font(.app(15))
            .monospacedDigit()
    }

    // MARK: Formatting

    /// "Hari ini", "Kemarin", or "Kamis, 24 Sep".
    static func dayHeader(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Hari ini" }
        if calendar.isDateInYesterday(date) { return "Kemarin" }
        return shortDayFormatter.string(from: date)
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = format
        f.locale = Locale(identifier: "id_ID")
        return f
    }

    private static let headerDateFormatter = formatter("EEEE, d MMMM")
    private static let shortDayFormatter = formatter("EEEE, d MMM")
    private static let dayFormatter = formatter("d")
    private static let monthFormatter = formatter("MMM")
}
