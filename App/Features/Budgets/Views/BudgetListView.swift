import SwiftUI

struct BudgetListView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel: BudgetListViewModel

    init(viewModel: BudgetListViewModel = BudgetListViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    /// Same key as `PaydaySetting`, so the header follows a payday saved anywhere.
    @AppStorage("paydayDay") private var paydayRaw = 0
    /// "Nanti saja" on the "Kapan kamu gajian?" card, per device.
    @AppStorage("paydayCardDismissed") private var isPaydayCardDismissed = false
    @State private var showAddBudget = false
    @State private var showPaydaySheet = false
    /// Payday the header keeps showing while it fades out to the new period.
    @State private var frozenPayday: Int?
    @State private var isPeriodHidden = false
    /// Row that just got a budget, tinted for a moment.
    @State private var flashId: String?
    @State private var toastText = ""
    @State private var isToastShown = false

    private var setItems: [BudgetListItem] {
        viewModel.budgetItems.filter { $0.budget != nil }
    }

    private var headerPayday: Int? {
        let day = frozenPayday ?? paydayRaw
        return day == 0 ? nil : day
    }

    private var showsPaydayCard: Bool {
        viewModel.hasLoadedOnce && paydayRaw == 0 && !isPaydayCardDismissed
    }

    private var overallMonthlyHistory: [OverallHistoryItem] {
        let calendar = Calendar.current
        let now = Date()
        // Periods run from payday; each is keyed by its first day.
        let currentMonth = PaydayCycle.current.period(containing: now, calendar: calendar).start

        let budgetCategoryIds = Set(viewModel.budgetItems.filter { $0.budget != nil }.map { $0.category.id })
        let expenseTransactions = viewModel.allExpenseTransactions.filter {
            guard let catId = $0.categoryId else { return false }
            return budgetCategoryIds.contains(catId) && $0.type == .expense
        }

        let grouped = Dictionary(grouping: expenseTransactions) { tx in
            PaydayCycle.current.period(containing: tx.date, calendar: calendar).start
        }

        return grouped
            .filter { $0.key < currentMonth }
            .map { month, txs in
                OverallHistoryItem(month: month, spent: txs.reduce(0) { $0 + $1.amount })
            }
            .sorted { $0.month > $1.month }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ScreenHeader(title: "Budget") {
                        NavigationLink(destination: OverallBudgetHistoryView(totalBudget: viewModel.totalBudget, monthlyHistory: overallMonthlyHistory, budgetItems: viewModel.budgetItems, allExpenseTransactions: viewModel.allExpenseTransactions).detailPage()) {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        .accessibilityLabel("Riwayat bulan sebelumnya")
                        Button {
                            showAddBudget = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(Color.appPrimary, in: Circle())
                        }
                        .buttonStyle(PressScaleStyle())
                        .opacity(viewModel.hasLoadedOnce ? 1 : 0.4)
                        .disabled(!viewModel.hasLoadedOnce)
                        .accessibilityLabel("Tambah budget")
                    }

                    periodHeader

                    if showsPaydayCard {
                        paydayCard
                            .padding(.horizontal, 24)
                            .padding(.top, 18)
                            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                    }

                    if let error = viewModel.errorMessage, !viewModel.hasLoadedOnce {
                        errorStateView(message: error)
                            .padding(24)
                    } else if !viewModel.hasLoadedOnce {
                        budgetSkeleton
                    } else {
                        if let error = viewModel.errorMessage {
                            ErrorBanner(message: error).padding(.horizontal, 24).padding(.top, 16)
                        }
                        if setItems.isEmpty {
                            emptyState
                        } else {
                            budgetList
                        }
                    }
                }
                .padding(.bottom, 24)
                .animation(.easeInOut(duration: 0.3), value: viewModel.hasLoadedOnce)
                .animation(.settle(0.42), value: showsPaydayCard)
            }
            .background(Color.appBackground)
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(isPresented: $showAddBudget) {
                if let userId = authViewModel.currentUser?.id {
                    AddBudgetView(viewModel: viewModel, userId: userId) { category in
                        budgetAdded(category)
                    }
                }
            }
            .sheet(isPresented: $showPaydaySheet) {
                PaydaySheet(context: .card) { day in paydayPicked(day) }
            }
            .toast(toastText, isShown: $isToastShown)
            .task {
                guard let userId = authViewModel.currentUser?.id else { return }
                await viewModel.loadBudgets(userId: userId)
            }
            .onReceive(NotificationCenter.default.publisher(for: .dataDidChange)) { _ in
                guard let userId = authViewModel.currentUser?.id else { return }
                Task {
                    await viewModel.loadBudgets(userId: userId, forceRefresh: true)
                }
            }
            .refreshable {
                guard let userId = authViewModel.currentUser?.id else { return }
                await viewModel.loadBudgets(userId: userId, forceRefresh: true)
            }
        }
    }

    private func errorStateView(message: String) -> some View {
        ErrorStateView(message: message) {
            guard let userId = authViewModel.currentUser?.id else { return }
            Task {
                await viewModel.loadBudgets(userId: userId, forceRefresh: true)
            }
        }
    }

    private func showToast(_ text: String) {
        toastText = text
        isToastShown = true
    }

    // MARK: Period

    /// "25 Sep – 24 Okt", days left, and one tick per day of the period.
    private var periodHeader: some View {
        let cycle = PaydayCycle(day: headerPayday ?? 1)
        let days = cycle.days()
        let dayNumber = days.total - days.left
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(cycle.rangeLabel())
                    .font(.app(20, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.appText)
                Spacer()
                Text("\(days.left + 1) hari lagi")
                    .font(.app(15, weight: .semibold))
                    .foregroundStyle(Color.appPrimary)
            }
            .monospacedDigit()
            SegmentBar(value: Double(dayNumber) / Double(max(days.total, 1)), count: days.total,
                       isActive: !isPeriodHidden)
                .id(days.total)
                .padding(.top, 10)
            Text(headerPayday.map { "Gajian tiap tanggal \($0)" } ?? "Mengikuti tanggal 1")
                + Text(" · hari ke-\(dayNumber) dari \(days.total)")
        }
        .font(.app(13))
        .foregroundStyle(Color.appTextSecondary)
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .opacity(isPeriodHidden ? 0 : 1)
        .offset(y: isPeriodHidden ? 8 : 0)
        .animation(.easeInOut(duration: 0.22), value: isPeriodHidden)
        .accessibilityElement(children: .combine)
    }

    private var paydayCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 19))
                .foregroundStyle(Color.appPrimary)
                .frame(width: 40, height: 40)
                .background(Color.appBackground, in: Circle())
                .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
            VStack(alignment: .leading, spacing: 4) {
                Text("Kapan kamu gajian?")
                    .font(.app(16, weight: .semibold))
                    .foregroundStyle(Color.appText)
                Text("Kami pakai tanggal ini supaya budget dan ringkasan bulananmu dimulai saat gaji masuk, bukan tanggal 1.")
                    .font(.app(14))
                    .lineSpacing(2)
                    .foregroundStyle(Color.appTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    Button {
                        frozenPayday = paydayRaw
                        showPaydaySheet = true
                    } label: {
                        Text("Atur")
                            .font(.app(15, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .frame(height: 34)
                            .background(Color.appPrimary, in: Capsule())
                    }
                    .buttonStyle(PressScaleStyle())
                    Button("Nanti saja") { isPaydayCardDismissed = true }
                        .font(.app(15, weight: .medium))
                        .foregroundStyle(Color.appTextSecondary)
                }
                .padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16))
    }

    /// Card sheet closed: fade the header out, bring it back on the new period, then say so.
    private func paydayPicked(_ day: Int?) {
        guard day != nil else { frozenPayday = nil; return }
        isPeriodHidden = true
        Task {
            try? await Task.sleep(for: .milliseconds(360))
            frozenPayday = nil
            isPeriodHidden = false
            try? await Task.sleep(for: .milliseconds(140))
            showToast("Periode budget diperbarui")
        }
    }

    // MARK: Budgets

    private var budgetList: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Per kategori", trailing: "\(setItems.count) aktif")
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 4)
            ForEach(Array(setItems.enumerated()), id: \.element.id) { i, item in
                NavigationLink(destination: budgetDetailDestination(for: item).detailPage()) {
                    BudgetCardView(budget: item.budget, category: item.category,
                                   fillDelay: 0.3 + Double(i) * 0.07, isFillActive: !isPeriodHidden)
                        .padding(.horizontal, 24)
                        .background(flashId == item.category.id ? Color.appPrimary.opacity(0.1) : .clear)
                        .animation(.easeInOut(duration: 0.7), value: flashId)
                }
                .buttonStyle(RowPressStyle())
            }
            Text("Budget dihitung per kategori. Tiap periode mulai dari nol, sisa tidak terbawa ke periode berikutnya.")
                .font(.app(13))
                .lineSpacing(2)
                .foregroundStyle(Color.appTextTertiary)
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 36)
        }
        .padding(.top, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            EmptyMessage(icon: "chart.pie",
                         title: "Belum ada budget",
                         message: "Atur batas pengeluaran per kategori. Tiap periode mulai dari nol, sisa tidak terbawa.")
            EmptyStateButton(title: "Tambah budget") { showAddBudget = true }
        }
        .padding(.horizontal, 40)
        .padding(.top, 90)
    }

    private func budgetAdded(_ category: Category) {
        flashId = category.id
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            showToast("Budget \(category.name) aktif")
            try? await Task.sleep(for: .milliseconds(1100))
            flashId = nil
        }
    }

    /// Placeholder rows while budgets load.
    private var budgetSkeleton: some View {
        VStack(spacing: 0) {
            ForEach([0.46, 0.58, 0.40, 0.62, 0.50], id: \.self) { share in
                HStack(spacing: 14) {
                    Circle().fill(Color.appFill).frame(width: 40, height: 40)
                    GeometryReader { geo in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                SkeletonBlock(width: geo.size.width * share, height: 14, radius: 7)
                                Spacer()
                                SkeletonBlock(width: geo.size.width * 0.22, height: 14, radius: 7)
                            }
                            SkeletonBlock(height: 4, radius: 2)
                            SkeletonBlock(width: geo.size.width * 0.55, height: 11, radius: 6)
                        }
                        .frame(maxHeight: .infinity)
                    }
                }
                .frame(height: 80)
                .padding(.horizontal, 24)
            }
        }
        .padding(.top, 14)
        .accessibilityLabel("Memuat")
    }

    private func budgetDetailDestination(for item: BudgetListItem) -> BudgetDetailView {
        BudgetDetailView(
            budget: item.budget!,
            category: item.category,
            allTransactions: viewModel.allExpenseTransactions.filter { $0.categoryId == item.category.id },
            accounts: viewModel.accounts,
            onAdjustBudget: { updated in
                Task {
                    let name = updated.name
                    let amount = updated.amount
                    let periodUnit = updated.periodUnit
                    let periodInterval = updated.periodInterval
                    let startDate = updated.startDate
                    let endDate = updated.endDate
                    let isActive = updated.isActive
                    await viewModel.updateBudget(id: updated.id, name: name, amount: amount, periodUnit: periodUnit, periodInterval: periodInterval, startDate: startDate, endDate: endDate, isActive: isActive)
                }
            },
            onUnsetBudget: {
                Task {
                    await viewModel.removeBudget(id: item.budget!.id)
                }
            }
        )
    }
}

/// Budget row: name and status, 30 ticks green / orange from 80% / red from 100%, spent of amount.
struct BudgetCardView: View {
    let budget: Budget?
    let category: Category
    /// Stagger for the segment bar's fill-in, so rows fill one after another.
    var fillDelay: Double = 0
    /// Empties the bar while false, e.g. while the period changes.
    var isFillActive = true

    @AppStorage("isBalanceVisible") private var isBalanceVisible = true

    var body: some View {
        if let budget {
            row(budget)
        }
    }

    private func money(_ amount: Double) -> String {
        isBalanceVisible ? amount.formattedAsCurrency() : "Rp" + hiddenAmount
    }

    private func row(_ budget: Budget) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: category.icon ?? "tag")
                .font(.system(size: 20))
                .foregroundStyle(Color.appTextSecondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(category.name)
                        .font(.app(16, weight: .medium))
                        .foregroundStyle(Color.appText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(statusText(budget))
                        .font(.app(14))
                        .foregroundStyle(budget.progress >= 0.8 ? color(budget) : Color.appTextSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                SegmentBar(value: budget.progress, color: color(budget), delay: fillDelay, isActive: isFillActive)
                Text("\(money(budget.spent)) dari \(money(budget.amount))")
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private func statusText(_ budget: Budget) -> String {
        if budget.remaining < 0 {
            // Big overruns shortened ("Lewat Rp6 M") so the status fits beside the name.
            let over = -budget.remaining
            return "Lewat " + (over >= 10_000_000 && isBalanceVisible ? "Rp" + over.abbreviatedRupiah() : money(over))
        }
        if budget.remaining == 0 { return "Habis" }
        // Today still counts as a day to spend in.
        return money(budget.remaining / Double(budget.daysRemaining + 1)) + "/hari"
    }

    private func color(_ budget: Budget) -> Color {
        budget.progress >= 1 ? .appError : budget.progress >= 0.8 ? .appWarning : .appPrimary
    }
}

struct OverallHistoryItem: Identifiable {
    let id = UUID()
    let month: Date
    let spent: Double

    var monthLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = Locale(identifier: "id_ID")
        return formatter.string(from: month)
    }

    func remainingPct(_ totalBudget: Double) -> Double {
        totalBudget > 0 ? max(0, (1 - spent / totalBudget) * 100) : 0
    }

    func statusColor(_ totalBudget: Double) -> Color {
        let r = remainingPct(totalBudget)
        return r <= 0 ? .appError : r <= 20 ? .appWarning : .appPrimary
    }

    /// Spent share of the budget for the bar, 0 when there is no budget.
    func progress(_ totalBudget: Double) -> Double {
        totalBudget > 0 ? spent / totalBudget : 0
    }
}

/// Thin 6pt rounded progress bar for history rows.
private struct ThinBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Color.appDivider)
                RoundedRectangle(cornerRadius: 3).fill(color)
                    .frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

struct OverallBudgetHistoryView: View {
    let totalBudget: Double
    let monthlyHistory: [OverallHistoryItem]
    let budgetItems: [BudgetListItem]
    let allExpenseTransactions: [Transaction]

    @AppStorage("isBalanceVisible") private var isBalanceVisible = true
    @State private var expandedYears: Set<Int> = []

    private var groupedByYear: [(year: Int, items: [OverallHistoryItem])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: monthlyHistory) { history in
            calendar.component(.year, from: history.month)
        }
        return grouped.map { (year: $0.key, items: $0.value.sorted { $0.month > $1.month }) }
            .sorted { $0.year > $1.year }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if monthlyHistory.isEmpty {
                    EmptyMessage(icon: "clock.arrow.circlepath",
                                 title: "Belum ada riwayat",
                                 message: "Riwayat muncul setelah bulan pertama budget kamu selesai.")
                        .padding(.horizontal, 24)
                        .padding(.top, 80)
                }
                ForEach(Array(groupedByYear.enumerated()), id: \.element.year) { i, group in
                    if i > 0 { SectionDivider() }
                    yearSection(group.year, group.items)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color.appBackground)
        .onAppear {
            if expandedYears.isEmpty {
                let currentYear = Calendar.current.component(.year, from: Date())
                expandedYears = [currentYear]
            }
        }
        .navigationTitle("Riwayat Budget")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func yearSection(_ year: Int, _ items: [OverallHistoryItem]) -> some View {
        let isExpanded = expandedYears.contains(year)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation {
                    if isExpanded {
                        expandedYears.remove(year)
                    } else {
                        expandedYears.insert(year)
                    }
                }
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 8) {
                        Text(String(year))
                            .font(.app(20, weight: .semibold))
                            .tracking(-0.2)
                            .foregroundStyle(Color.appText)
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.appTextSecondary)
                    }
                    Spacer()
                    Text("\(items.count) bulan")
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isExpanded ? .isSelected : [])

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(items) { history in
                        NavigationLink(destination: OverallMonthDetailView(totalBudget: totalBudget, month: history.month, budgetItems: budgetItems, allExpenseTransactions: allExpenseTransactions).detailPage()) {
                            historyRow(history)
                        }
                        .buttonStyle(RowPressStyle())
                    }
                }
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 8)
    }

    private func money(_ amount: Double) -> String {
        isBalanceVisible ? amount.formattedAsCurrency() : "Rp" + hiddenAmount
    }

    private func historyRow(_ history: OverallHistoryItem) -> some View {
        let color = history.statusColor(totalBudget)
        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: color == .appPrimary ? "checkmark.circle" : "exclamationmark.circle")
                .font(.system(size: 19))
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(history.monthLabel)
                        .font(.app(16))
                        .foregroundStyle(Color.appText)
                    Spacer(minLength: 8)
                    Text(money(history.spent))
                        .font(.app(15))
                        .foregroundStyle(color == .appPrimary ? Color.appText : color)
                        .monospacedDigit()
                }
                ThinBar(value: history.progress(totalBudget), color: color)
                HStack {
                    Text("Budget \(money(totalBudget))")
                    Spacer()
                    Text("Sisa \(Int(history.remainingPct(totalBudget)))%")
                }
                .font(.app(13))
                .foregroundStyle(Color.appTextSecondary)
                .monospacedDigit()
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.appTextTertiary)
                .padding(.top, 4)
        }
        .padding(.vertical, 14)
        .rowSeparator()
        .contentShape(Rectangle())
    }
}

struct OverallMonthDetailView: View {
    let totalBudget: Double
    let month: Date
    let budgetItems: [BudgetListItem]
    let allExpenseTransactions: [Transaction]

    @AppStorage("isBalanceVisible") private var isBalanceVisible = true

    private var monthLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = Locale(identifier: "id_ID")
        return formatter.string(from: month)
    }

    private var transactions: [Transaction] {
        // `month` is the first day of a payday period.
        let period = PaydayCycle.current.period(containing: month)
        let (monthStart, nextMonth) = (period.start, period.end)
        return allExpenseTransactions
            .filter { $0.date >= monthStart && $0.date < nextMonth }
            .sorted { $0.date > $1.date }
    }

    private var spent: Double {
        transactions.reduce(0) { $0 + $1.amount }
    }

    private var remaining: Double { totalBudget - spent }
    private var progress: Double { totalBudget > 0 ? spent / totalBudget : 0 }
    private var remainingPct: Double { progress >= 1 ? 0 : (1 - progress) * 100 }
    private var progressColor: Color { remainingPct <= 0 ? .appError : remainingPct <= 20 ? .appWarning : .appPrimary }
    private var setItems: [BudgetListItem] { budgetItems.filter { $0.budget != nil } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                summary
                SectionDivider()

                if !setItems.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeader(title: "Per kategori", trailing: "\(setItems.count)")
                        ForEach(Array(setItems.enumerated()), id: \.element.id) { i, item in
                            NavigationLink(destination: BudgetDetailView(budget: item.budget!, category: item.category, allTransactions: [], accounts: [], showHistoryButton: false).detailPage()) {
                                BudgetCardView(budget: item.budget, category: item.category, fillDelay: 0.3 + Double(i) * 0.08)
                            }
                            .buttonStyle(RowPressStyle())
                        }
                        .padding(.top, 6)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color.appBackground)
        .navigationTitle(monthLabel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sisa budget")
                Spacer()
                Text("\(Int(remainingPct))%").monospacedDigit()
            }
            .font(.app(15))
            .foregroundStyle(remainingPct <= 0 ? Color.appError : Color.appTextSecondary)

            HeroAmount(value: remainingPct <= 0 ? 0 : remaining, size: .large,
                       isVisible: isBalanceVisible, weight: .ultraLight)
                .padding(.top, 8)

            SegmentBar(value: progress, color: progressColor, height: 12)
                .padding(.top, 24)

            HStack {
                total("Terpakai", spent)
                Spacer()
                total("Budget", totalBudget)
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 32)
    }

    private func total(_ label: String, _ amount: Double) -> some View {
        (Text(label + " ").foregroundStyle(Color.appTextSecondary)
         + Text(isBalanceVisible ? amount.abbreviatedRupiah() : hiddenAmount)
            .fontWeight(.medium)
            .foregroundStyle(Color.appText))
            .font(.app(15))
            .monospacedDigit()
    }
}
