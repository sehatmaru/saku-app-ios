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
    /// Drives the "Bulan ini" grow-in; reset and set again to replay.
    @State private var isChartShown = false
    @State private var showAllBudgets = false
    @State private var selectedTab: AppTab = .home

    enum AppTab: Hashable {
        case home, transactions, budget, wallet
        /// iOS 26 "Tambah" circle; selecting it opens the add sheet instead of switching tabs.
        case add
    }

    var body: some View {
        tabs
        .onChange(of: selectedTab) { previous, tab in
            guard tab == .add else { return }
            selectedTab = previous
            showAddSheet = true
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
    }

    // MARK: - Tabs

    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 26, *) {
            TabView(selection: $selectedTab) {
                mainTabs
                // A search-role tab renders as the detached glass circle next to the tab bar.
                Tab(value: AppTab.add, role: .search) {
                    Color.clear
                } label: {
                    Label { Text("Tambah") } icon: { Image(uiImage: Self.plusIcon) }
                }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
        } else {
            TabView(selection: $selectedTab) {
                mainTabs
            }
            .overlay(alignment: .bottomTrailing) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.appPrimary)
                        .frame(width: 52, height: 52)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(Color.appDivider))
                        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                }
                .accessibilityLabel("Tambah transaksi")
                .padding(.trailing, 16)
                .padding(.bottom, 57) // above the 49pt tab bar
            }
        }
    }

    @TabContentBuilder<AppTab>
    private var mainTabs: some TabContent<AppTab> {
        Tab("Beranda", systemImage: "house.fill", value: AppTab.home) {
            NavigationStack { mainContent }
        }
        Tab("Transaksi", systemImage: "list.bullet", value: AppTab.transactions) {
            TransactionListView()
        }
        Tab("Budget", systemImage: "chart.pie.fill", value: AppTab.budget) {
            BudgetListView()
        }
        Tab("Dompet", systemImage: "wallet.bifold.fill", value: AppTab.wallet) {
            AccountListView()
        }
    }

    /// Tab bar items are template-tinted; an always-original image keeps the plus green.
    private static let plusIcon: UIImage = {
        let config = UIImage.SymbolConfiguration(weight: .semibold)
        let image = UIImage(systemName: "plus", withConfiguration: config) ?? UIImage()
        return image.withTintColor(UIColor(Color.appPrimary), renderingMode: .alwaysOriginal)
    }()

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
                    monthSection
                    SectionDivider()
                    budgetSection
                    SectionDivider()
                    billsSection
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

            SegmentBar(value: Double(score) / 100, color: healthColor(score), count: 40, height: 22, spacing: 3)
                .padding(.top, 16)

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

    // MARK: This month

    private var monthSection: some View {
        let days = viewModel.dailyExpenses
        let average = days.isEmpty ? 0 : days.reduce(0, +) / Double(days.count)
        let peak = max(days.max() ?? 0, average, 1) * 1.05
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "Bulan ini")
                NavigationLink("Analisis") { AnalyticsView(viewModel: viewModel) }
                    .font(.app(15))
                    .foregroundStyle(Color.appPrimary)
            }

            HStack(alignment: .top, spacing: 32) {
                countStat(average, label: "rata-rata / hari") { value in
                    isBalanceVisible ? value.rounded(.toNearestOrEven).formattedAsCurrency() : "Rp" + hiddenAmount
                }
                countStat(Double(viewModel.currentMonthTransactionCount), label: "transaksi") { "\(Int($0.rounded()))" }
            }
            .padding(.top, 14)

            dailyChart(days, average: average, peak: peak)
                .padding(.top, 22)

            HStack {
                Text("1 \(Self.monthFormatter.string(from: Date()))")
                Spacer()
                Text("Hari ini")
            }
            .font(.app(12))
            .foregroundStyle(Color.appTextSecondary)
            .padding(.top, 8)

            let slices = categorySlices
            if !slices.isEmpty {
                categoryBar(slices)
                    .padding(.top, 24)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { legend(slices) }
                    VStack(alignment: .leading, spacing: 6) { legend(slices) }
                }
                .padding(.top, 10)
            }
        }
        .padding(24)
        .padding(.vertical, 4)
        .onAppear(perform: replayChart)
    }

    private func countStat(_ value: Double, label: String, format: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            CountingText(value: isChartShown ? value : 0, format: format)
                .font(.app(28, weight: .light))
                .tracking(-0.8)
                .monospacedDigit()
                .foregroundStyle(Color.appText)
                .animation(.timingCurve(0.33, 1, 0.68, 1, duration: 1.1), value: isChartShown)
            Text(label)
                .font(.app(13))
                .foregroundStyle(Color.appTextSecondary)
        }
    }

    /// One bar per day so far; today in green, dashed line at the daily average. Tap to replay.
    private func dailyChart(_ days: [Double], average: Double, peak: Double) -> some View {
        let height: CGFloat = 96
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(days.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i == days.count - 1 ? Color.appPrimary : Self.barGray)
                    .frame(height: isChartShown ? max(2, height * days[i] / peak) : 2)
                    .animation(.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.7).delay(Double(i) * 0.022), value: isChartShown)
            }
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .bottom)
        .overlay(alignment: .bottom) {
            if average > 0 {
                DashedLine()
                    .stroke(Color.appTextSecondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(height: 1)
                    .offset(y: -height * average / peak)
                    .opacity(isChartShown ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(isChartShown ? 0.9 : 0), value: isChartShown)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: replayChart)
        .accessibilityElement()
        .accessibilityLabel("Pengeluaran harian bulan ini")
        .accessibilityHint("Ketuk untuk memutar ulang")
    }

    private func replayChart() {
        var reset = SwiftUI.Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { isChartShown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { isChartShown = true }
    }

    private struct CategorySlice: Identifiable {
        let name: String
        let share: Double
        let color: Color
        var id: String { name }
    }

    /// Top four spending categories plus "Lainnya".
    private var categorySlices: [CategorySlice] {
        let total = viewModel.categorySpending.map(\.amount).reduce(0, +)
        guard total > 0 else { return [] }
        var slices = viewModel.categorySpending.prefix(4).enumerated().map { i, item in
            CategorySlice(name: item.0.name, share: item.amount / total, color: Self.slicePalette[i])
        }
        let rest = 1 - slices.map(\.share).reduce(0, +)
        if rest > 0.005 {
            slices.append(CategorySlice(name: "Lainnya", share: rest, color: Self.slicePalette[4]))
        }
        return slices
    }

    private func categoryBar(_ slices: [CategorySlice]) -> some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(Array(slices.enumerated()), id: \.element.id) { i, slice in
                    Rectangle()
                        .fill(slice.color)
                        .overlay(alignment: .trailing) {
                            Rectangle().fill(Color.appBackground).frame(width: 2)
                        }
                        .frame(width: isChartShown ? geo.size.width * slice.share : 0)
                        .animation(.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.8).delay(0.5 + Double(i) * 0.09), value: isChartShown)
                }
            }
        }
        .frame(height: 8)
        .background(Color.appFill)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func legend(_ slices: [CategorySlice]) -> some View {
        ForEach(slices.prefix(3)) { slice in
            HStack(spacing: 6) {
                Circle().fill(slice.color).frame(width: 8, height: 8)
                Text(slice.name)
                    .foregroundStyle(Color.appTextSecondary)
                    .lineLimit(1)
                Text("\(Int((slice.share * 100).rounded()))%")
                    .foregroundStyle(Color.appText)
                    .monospacedDigit()
            }
            .font(.app(13))
        }
    }

    private static let barGray = Color(light: 0xD9D9DE, dark: 0x3A3A3C)
    private static let slicePalette: [Color] = [
        .appPrimary,
        Color(light: 0x3A3A3C, dark: 0xD1D1D6),
        Color(light: 0x8E8E93, dark: 0x8E8E93),
        Color(light: 0xC7C7CC, dark: 0x636366),
        Color(light: 0xE5E5EA, dark: 0x3A3A3C),
    ]

    // MARK: Budget

    /// Three budgets with the largest spend; "Lihat semua" expands inline.
    private var budgetSection: some View {
        let sorted = viewModel.budgets.sorted { $0.spent > $1.spent }
        let shown = showAllBudgets ? sorted : Array(sorted.prefix(3))
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader(
                title: "Budget",
                trailing: sorted.isEmpty ? nil : "Sisa " + (isBalanceVisible ? max(0, viewModel.totalRemaining).formattedAsCurrency() : "Rp" + hiddenAmount)
            )

            if sorted.isEmpty {
                Text("Belum ada budget")
                    .font(.app(15))
                    .foregroundStyle(Color.appTextSecondary)
                    .padding(.top, 14)
            } else {
                VStack(spacing: 0) {
                    ForEach(shown) { budgetRow($0) }
                }
                .padding(.top, 6)
            }

            if sorted.count > 3 {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { showAllBudgets.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text(showAllBudgets ? "Tampilkan lebih sedikit" : "Lihat semua (\(sorted.count))")
                        Image(systemName: showAllBudgets ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .font(.app(15, weight: .medium))
                    .foregroundStyle(Color.appText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.appFill, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
            }
        }
        .padding(24)
        .padding(.vertical, 4)
    }

    private func budgetRow(_ budget: Budget) -> some View {
        let category = viewModel.categories.first { $0.id == budget.categoryId }
        let ratio = budget.progress
        return HStack(spacing: 14) {
            Image(systemName: category?.icon ?? "tag")
                .font(.system(size: 19))
                .foregroundStyle(Color.appTextSecondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(category?.name ?? budget.name)
                        .font(.app(16, weight: .medium))
                        .foregroundStyle(Color.appText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Group {
                        if isBalanceVisible {
                            Text("Rp" + budget.spent.abbreviatedRupiah())
                                .foregroundStyle(Color.appText)
                                + Text(" / " + budget.amount.abbreviatedRupiah())
                                .foregroundStyle(Color.appTextTertiary)
                        } else {
                            Text("Rp" + hiddenAmount).foregroundStyle(Color.appText)
                        }
                    }
                    .font(.app(15))
                    .monospacedDigit()
                    .lineLimit(1)
                }
                SegmentBar(value: ratio, color: ratio >= 1 ? .appError : ratio >= 0.8 ? .appWarning : .appPrimary)
            }
        }
        .padding(.vertical, 14)
        .rowSeparator()
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
                HStack(spacing: 6) {
                    if let account = viewModel.accounts.first(where: { $0.id == sub.accountId }) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(account.walletColor)
                            .frame(width: 18, height: 12)
                    }
                    Text(accountName(for: sub.accountId))
                        .lineLimit(1)
                }
                .font(.app(13))
                .foregroundStyle(Color.appTextSecondary)
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
