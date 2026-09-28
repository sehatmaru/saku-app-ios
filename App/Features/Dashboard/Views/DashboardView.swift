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
    /// Day index picked in the "Bulan ini" chart; nil means today.
    @State private var selectedDay: Int?
    @State private var showAllBudgets = false
    @State private var selectedTab: AppTab = .home
    @State private var tabBarScroll = TabBarScroll()
    /// Dompet slides in over the app from Beranda's hero; it is no longer a tab.
    @State private var showsWallets = false
    @State private var didWelcome = false

    enum AppTab: Hashable {
        case home, transactions, budget, profile
    }

    var body: some View {
        ZStack {
            tabs
            if showsWallets {
                AccountListView { withAnimation(.settle(0.46)) { showsWallets = false } }
                    .background(Color.appBackground.ignoresSafeArea())
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }
        }
        .onChange(of: selectedTab) { tabBarScroll.reset() }
        .onChange(of: showAddSheet) { _, isShown in if isShown { Haptics.add() } }
        .tint(.appPrimary)
        .onAppear {
            if !didWelcome {
                didWelcome = true
                Haptics.welcome()
            }
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
        .fullScreenCover(isPresented: $showAddSheet) {
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
            }
        }
    }

    // MARK: - Tabs

    /// Our own glass bar over a TabView whose system bar is hidden.
    private var tabs: some View {
        TabView(selection: $selectedTab) {
            mainTabs
        }
        .environment(tabBarScroll)
        .overlay(alignment: .bottom) {
            GlassTabBar(
                leading: [.init(tab: .home, label: "Beranda", icon: "house.fill"),
                          .init(tab: .transactions, label: "Transaksi", icon: "list.bullet")],
                trailing: [.init(tab: .budget, label: "Budget", icon: "chart.pie.fill"),
                           .init(tab: .profile, label: "Profil", icon: "person.crop.circle.fill", avatar: initials)],
                selection: $selectedTab,
                isHidden: tabBarScroll.isHidden
            ) {
                showAddSheet = true
            }
        }
    }

    private var initials: String { authViewModel.currentUser?.initials ?? "U" }

    @TabContentBuilder<AppTab>
    private var mainTabs: some TabContent<AppTab> {
        Tab("Beranda", systemImage: "house.fill", value: AppTab.home) {
            NavigationStack { mainContent }
                .glassTabBarSpace()
        }
        Tab("Transaksi", systemImage: "list.bullet", value: AppTab.transactions) {
            TransactionListView()
                .glassTabBarSpace()
        }
        Tab("Budget", systemImage: "chart.pie.fill", value: AppTab.budget) {
            BudgetListView()
                .glassTabBarSpace()
        }
        Tab("Profil", systemImage: "person.crop.circle.fill", value: AppTab.profile) {
            ProfileView()
                .glassTabBarSpace()
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
                    monthSection
                    SectionDivider()
                    budgetSection
                        .padding(.bottom, 90)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: viewModel.hasLoadedOnce)
        }
        .tracksTabBarScroll()
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
            HomeLogo()
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
        .padding(.top, 8)
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

    /// Big total, a green/red bar for money in vs out, then Masuk · Keluar · Net.
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Total saldo")
                    .font(.app(15))
                    .foregroundStyle(Color.appTextSecondary)
                Spacer()
                walletsButton
            }
            HeroAmount(value: viewModel.balance, size: .hero, isVisible: isBalanceVisible, weight: .ultraLight)
                .padding(.top, 2)

            FlowSplitBar(income: viewModel.totalIncome, expense: viewModel.totalExpense)
                .padding(.top, 28)

            HStack {
                flowStat("Masuk", viewModel.totalIncome)
                Spacer()
                flowStat("Keluar", viewModel.totalExpense)
                Spacer()
                flowStat("Net", viewModel.netCashflow, signed: true)
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 24)
        .padding(.top, 36)
        .padding(.bottom, 36)
    }

    /// Mini card stack with "Dompet · N akun"; opens the Dompet page.
    private var walletsButton: some View {
        Button {
            withAnimation(.settle(0.46)) { showsWallets = true }
        } label: {
            HStack(spacing: 8) {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(["D9A93A", "472B91", "1A1F71"].enumerated()), id: \.offset) { i, hex in
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(hex: hex))
                            .frame(width: 30, height: 20)
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
                            .offset(x: CGFloat(2 - i) * 3, y: 2 + CGFloat(i) * 5)
                    }
                }
                .frame(width: 36, height: 32, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Dompet")
                        .font(.app(14, weight: .semibold))
                        .foregroundStyle(Color.appText)
                    Text("\(viewModel.accounts.filter(\.isActive).count) akun")
                        .font(.app(11))
                        .foregroundStyle(Color.appTextSecondary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(light: 0x8E8E93, dark: 0x8E8E93))
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .frame(height: 48)
            .background(Color.appFill, in: Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("Buka Dompet")
    }

    /// "Masuk 12 jt"; Net is green when positive and red when negative.
    private func flowStat(_ label: String, _ amount: Double, signed: Bool = false) -> some View {
        let sign = signed ? (amount > 0 ? "+" : amount < 0 ? "−" : "") : ""
        let color: Color = signed ? (amount > 0 ? .appPrimary : amount < 0 ? .appError : .appText) : .appText
        return (Text(label + " ").foregroundStyle(Color.appTextSecondary)
                + Text(isBalanceVisible ? sign + amount.abbreviatedRupiah() : hiddenAmount)
                    .fontWeight(.medium)
                    .foregroundStyle(color))
            .font(.app(15))
            .monospacedDigit()
            .lineLimit(1)
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
                .padding(.top, 18)

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

    /// One bar per day so far with a dashed daily-average line. Tap a bar to see that day's spending.
    private func dailyChart(_ days: [Double], average: Double, peak: Double) -> some View {
        let height: CGFloat = 96
        let selected = min(selectedDay ?? days.count - 1, days.count - 1)
        return VStack(spacing: 4) {
            if selected >= 0 {
                dayLabel(days, selected: selected)
            }
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(days.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i == selected ? Color.appPrimary : Self.barGray)
                        .animation(.easeInOut(duration: 0.2), value: selected)
                        .frame(height: isChartShown ? max(2, height * days[i] / peak) : 2)
                        .animation(.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.7).delay(Double(i) * 0.022), value: isChartShown)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedDay = i }
                        .accessibilityElement()
                        .accessibilityLabel(dayTitle(i, of: days.count))
                        .accessibilityValue(isBalanceVisible ? "Rp" + days[i].formattedAsDigits() : "tersembunyi")
                        .accessibilityAddTraits(i == selected ? [.isButton, .isSelected] : .isButton)
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
                        .allowsHitTesting(false)
                }
            }
        }
    }

    /// Black pill above the chart naming the selected day and its spending; follows the bar.
    private func dayLabel(_ days: [Double], selected: Int) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let x = (CGFloat(selected) + 0.5) * w / CGFloat(days.count)
            HStack(spacing: 6) {
                Text(dayTitle(selected, of: days.count))
                    .foregroundStyle(Color.appBackground.opacity(0.7))
                Text(isBalanceVisible ? "−Rp" + days[selected].formattedAsDigits() : "Rp" + hiddenAmount)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.appBackground)
                    .contentTransition(.numericText())
            }
            .font(.app(13))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Color.appText, in: Capsule())
            .position(x: min(max(x, 78), max(w - 78, 78)), y: 14)
            .animation(.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.26), value: selected)
            .opacity(isChartShown ? 1 : 0)
            .animation(.easeInOut(duration: 0.3).delay(isChartShown ? 0.7 : 0), value: isChartShown)
        }
        .frame(height: 30)
        .accessibilityHidden(true)
    }

    /// "Hari ini" for the last bar, otherwise e.g. "Sel, 15 Sep".
    private func dayTitle(_ index: Int, of count: Int) -> String {
        guard index != count - 1 else { return "Hari ini" }
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        let date = calendar.date(byAdding: .day, value: index, to: start) ?? start
        return Self.weekdayDayFormatter.string(from: date)
    }

    private func replayChart() {
        var reset = SwiftUI.Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            isChartShown = false
            selectedDay = nil
        }
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
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, budget in budgetRow(budget, index: i) }
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

    private func budgetRow(_ budget: Budget, index: Int) -> some View {
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
                SegmentBar(value: ratio, color: ratio >= 1 ? .appError : ratio >= 0.8 ? .appWarning : .appPrimary,
                           delay: 0.3 + Double(index) * 0.08)
            }
        }
        .padding(.vertical, 12)
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

    private static let shortDayFormatter = formatter("EEEE, d MMM")
    private static let monthFormatter = formatter("MMM")
    private static let weekdayDayFormatter = formatter("EEE, d MMM")
}

/// Beranda's header mark: the pocket pops in, cards rise and fan, then "SakuQ" fades up.
/// Every 5 s the cards drop back in and rise again; tapping replays the whole intro.
private struct HomeLogo: View {
    @State private var showsPocket = false
    @State private var isOpen = false
    @State private var isFanned = false
    @State private var showsWord = false
    @State private var run = 0

    var body: some View {
        Button { run += 1 } label: {
            HStack(spacing: 8) {
                PocketLogo(isOpen: isOpen, isFanned: isFanned, stagger: 0.12, duration: 0.9,
                           pocketColor: .appBrand, isPlain: true)
                    .frame(width: 24, height: 24)
                    .opacity(showsPocket ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: showsPocket)
                    .scaleEffect(showsPocket ? 1 : 0.6, anchor: .bottom)
                    .animation(.timingCurve(0.3, 1.4, 0.5, 1, duration: 0.7), value: showsPocket)
                    .frame(width: 28, height: 28)
                Text("SakuQ")
                    .font(.wordmark(19))
                    .tracking(-0.5)
                    .foregroundStyle(Color.appText)
                    .rise(showsWord, y: 6)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("SakuQ")
        .task(id: run) { await play() }
    }

    private func play() async {
        var reset = SwiftUI.Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            showsPocket = false
            isOpen = false
            isFanned = false
            showsWord = false
        }
        let start = ContinuousClock.now
        for (t, step) in [(0.15, 1), (0.65, 2), (1.25, 3), (1.6, 4)] {
            try? await Task.sleep(until: start + .seconds(t), clock: .continuous)
            guard !Task.isCancelled else { return }
            switch step {
            case 1: showsPocket = true
            case 2: isOpen = true
            case 3: isFanned = true
            default: showsWord = true
            }
        }
        // Loops until the view goes away or a tap restarts it.
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            isOpen = false
            isFanned = false
            try? await Task.sleep(for: .seconds(1))
            isOpen = true
            try? await Task.sleep(for: .seconds(0.6))
            isFanned = true
        }
    }
}
