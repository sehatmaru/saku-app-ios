import SwiftUI

struct BudgetListView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel: BudgetListViewModel

    init(viewModel: BudgetListViewModel = BudgetListViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    @AppStorage("isBalanceVisible") private var isBalanceVisibleStorage = true
    @State private var isBalanceVisible = true
    @State private var showUnsetBudget = true
    @State private var showAddBudget = false
    @State private var showBudgetSavedToast = false
    @State private var budgetSavedToastMessage = ""
    private var setItems: [BudgetListItem] {
        viewModel.budgetItems.filter { $0.budget != nil }
    }

    private var unsetItems: [BudgetListItem] {
        viewModel.budgetItems.filter { $0.budget == nil }
    }

    private var overallMonthlyHistory: [OverallHistoryItem] {
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!

        let budgetCategoryIds = Set(viewModel.budgetItems.filter { $0.budget != nil }.map { $0.category.id })
        let expenseTransactions = viewModel.allExpenseTransactions.filter {
            guard let catId = $0.categoryId else { return false }
            return budgetCategoryIds.contains(catId) && $0.type == .expense
        }

        let grouped = Dictionary(grouping: expenseTransactions) { tx in
            calendar.date(from: calendar.dateComponents([.year, .month], from: tx.date))!
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
                        Button {
                            withAnimation(.smooth) { isBalanceVisible.toggle() }
                            isBalanceVisibleStorage = isBalanceVisible
                        } label: {
                            Image(systemName: isBalanceVisible ? "eye" : "eye.slash")
                        }
                        .accessibilityLabel(isBalanceVisible ? "Sembunyikan saldo" : "Tampilkan saldo")
                        Button {
                            showAddBudget = true
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(Color.appPrimary)
                        }
                        .accessibilityLabel("Tambah budget")
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
                            summary
                            SectionDivider()

                            if !setItems.isEmpty {
                                VStack(alignment: .leading, spacing: 0) {
                                    SectionHeader(title: "Per kategori", trailing: "\(setItems.count) aktif")
                                    ForEach(Array(setItems.enumerated()), id: \.element.id) { i, item in
                                        budgetCardLink(item, index: i)
                                    }
                                }
                                .padding(.horizontal, 24)
                                .padding(.top, 28)
                            }

                            if !unsetItems.isEmpty {
                                unsetSection
                            }
                        }
                    }
                    .padding(.bottom, 24)
                    .animation(.easeInOut(duration: 0.3), value: viewModel.hasLoadedOnce)
                }
                .background(Color.appBackground)
                .toolbar(.hidden, for: .navigationBar)
                .sheet(isPresented: $showAddBudget) {
                    AddBudgetView { name, icon, amount in
                        guard let userId = authViewModel.currentUser?.id else { return .failure }
                        let result = await viewModel.addBudget(name: name, icon: icon, userId: userId, amount: amount)
                        if result == .success {
                            budgetSavedToastMessage = "Budget \(name) berhasil ditambahkan"
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                withAnimation { showBudgetSavedToast = true }
                            }
                        }
                        return result
                    }
                    .presentationDetents([.height(560), .large])
                }
                .toast(isPresented: $showBudgetSavedToast, message: budgetSavedToastMessage)
                .onAppear { isBalanceVisible = isBalanceVisibleStorage }
                .onChange(of: isBalanceVisibleStorage) { _, newValue in isBalanceVisible = newValue }
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

        /// 13h: labels stay; the amount and category rows shimmer.
        private var budgetSkeleton: some View {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Sisa budget \(Self.monthFormatter.string(from: Date()))")
                        .font(.app(15))
                        .foregroundStyle(Color.appTextSecondary)
                    SkeletonBlock(width: 250, height: 52, radius: 10)
                        .padding(.top, 8)
                    SegmentBar(value: 0, height: 12)
                        .padding(.top, 24)
                    SkeletonBlock(width: 220, height: 14)
                        .padding(.top, 18)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 32)

                SectionDivider()

                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(title: "Per kategori")
                    ForEach([(120.0, 60.0), (96.0, 52.0), (136.0, 66.0), (104.0, 48.0)], id: \.0) { name, amount in
                        HStack(alignment: .top, spacing: 14) {
                            Circle().fill(Color.appFill).frame(width: 24, height: 24)
                            VStack(spacing: 10) {
                                HStack {
                                    SkeletonBlock(width: name, height: 14)
                                    Spacer()
                                    RoundedRectangle(cornerRadius: 5).fill(Color.appFill).frame(width: amount, height: 14)
                                }
                                RoundedRectangle(cornerRadius: 2).fill(Color.appFill).frame(height: 8)
                            }
                        }
                        .padding(.vertical, 13)
                    }
                    .padding(.top, 6)
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
            }
            .accessibilityLabel("Memuat")
        }

        // MARK: Summary

        private var summary: some View {
            let remaining = viewModel.totalRemaining
            let pct = viewModel.totalBudget > 0 ? Int(max(0, remaining / viewModel.totalBudget * 100)) : 0
            let calendar = Calendar.current
            let daysLeft = (calendar.range(of: .day, in: .month, for: Date())?.count ?? 30) - calendar.component(.day, from: Date())
            return VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Sisa budget \(Self.monthFormatter.string(from: Date()))")
                    Spacer()
                    if !hasNoBudgets { Text("\(pct)%").monospacedDigit() }
                }
                .font(.app(15))
                .foregroundStyle(remaining < 0 ? Color.appError : Color.appTextSecondary)

                HeroAmount(value: max(0, remaining), size: .hero,
                           color: hasNoBudgets ? .appTextTertiary : .appText,
                           prefixColor: hasNoBudgets ? .appTextTertiary : .appTextSecondary,
                           isVisible: isBalanceVisible, weight: .ultraLight)
                    .padding(.top, 8)

                SegmentBar(
                    value: viewModel.totalBudget > 0 ? viewModel.totalSpent / viewModel.totalBudget : 0,
                    color: remaining < 0 ? .appError : .appPrimary,
                    height: 12
                )
                .padding(.top, 24)

                if hasNoBudgets {
                    // 13i: no limits yet, so one line of why and the button to set the first.
                    Text("Atur batas pengeluaran per kategori supaya tahu berapa yang aman dipakai tiap hari.")
                        .font(.app(15))
                        .lineSpacing(3)
                        .foregroundStyle(Color.appBody)
                        .padding(.top, 18)
                    EmptyStateButton(title: "Buat budget", isFullWidth: true) { showAddBudget = true }
                        .padding(.top, 20)
                } else {
                HStack {
                    total("Terpakai", viewModel.totalSpent)
                    Spacer()
                    total("Budget", viewModel.totalBudget)
                }
                .padding(.top, 12)

                if viewModel.totalBudget > 0 {
                    Group {
                        if remaining <= 0 {
                            Text("Budget bulan ini sudah habis.")
                        } else if daysLeft > 0 {
                            Text("Aman dipakai ")
                                + Text(masked(remaining / Double(daysLeft)) + "/hari")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.appText)
                                + Text(" untuk \(daysLeft) hari tersisa.")
                        } else {
                            Text("Hari terakhir: sisa ")
                                + Text(masked(remaining)).fontWeight(.semibold).foregroundStyle(Color.appText)
                                + Text(" bisa dipakai hari ini.")
                        }
                    }
                    .font(.app(15))
                    .lineSpacing(3)
                    .foregroundStyle(Color.appBody)
                    .padding(.top, 18)
                }

                historyLink
                    .padding(.top, 20)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 32)
        .padding(.bottom, hasNoBudgets ? 28 : 32)
    }

    private var hasNoBudgets: Bool { setItems.isEmpty }

    /// "Terpakai 3,04 jt" with the amount in the text colour.
    private func total(_ label: String, _ amount: Double) -> some View {
        (Text(label + " ").foregroundStyle(Color.appTextSecondary)
         + Text(isBalanceVisible ? amount.abbreviatedRupiah() : hiddenAmount)
            .fontWeight(.medium)
            .foregroundStyle(Color.appText))
            .font(.app(15))
            .monospacedDigit()
    }

    private func masked(_ amount: Double) -> String {
        isBalanceVisible ? amount.formattedAsCurrency() : "Rp" + hiddenAmount
    }

    private var historyLink: some View {
        NavigationLink(destination: OverallBudgetHistoryView(totalBudget: viewModel.totalBudget, monthlyHistory: overallMonthlyHistory, budgetItems: viewModel.budgetItems, allExpenseTransactions: viewModel.allExpenseTransactions)) {
            Label("Riwayat bulan sebelumnya", systemImage: "clock.arrow.circlepath")
                .font(.app(15, weight: .medium))
                .foregroundStyle(Color.appText)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.appFill, in: Capsule())
        }
        .buttonStyle(RowPressStyle())
    }

    private var unsetSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation { showUnsetBudget.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 8) {
                        Text("Belum diatur")
                            .font(.app(20, weight: .semibold))
                            .tracking(-0.2)
                            .foregroundStyle(Color.appText)
                        Image(systemName: showUnsetBudget ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.appTextSecondary)
                    }
                    Spacer()
                    Text("\(unsetItems.count)")
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showUnsetBudget {
                ForEach(unsetItems) { item in
                    BudgetCardView(budget: item.budget, category: item.category, onSetBudget: { budget in
                        Task {
                            guard let userId = authViewModel.currentUser?.id else { return }
                            await viewModel.setBudget(categoryId: budget.categoryId, name: budget.name, amount: budget.amount, periodUnit: budget.periodUnit, periodInterval: budget.periodInterval, startDate: budget.startDate, endDate: budget.endDate, userId: userId)
                        }
                    })
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
    }

    private func budgetCardLink(_ item: BudgetListItem, index: Int) -> some View {
        NavigationLink(destination: budgetDetailDestination(for: item)) {
            BudgetCardView(budget: item.budget, category: item.category, fillDelay: 0.3 + Double(index) * 0.08, onSetBudget: { budget in
                Task {
                    guard let userId = authViewModel.currentUser?.id else { return }
                    await viewModel.setBudget(categoryId: budget.categoryId, name: budget.name, amount: budget.amount, periodUnit: budget.periodUnit, periodInterval: budget.periodInterval, startDate: budget.startDate, endDate: budget.endDate, userId: userId)
                }
            })
        }
        .buttonStyle(RowPressStyle())
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        f.locale = Locale(identifier: "id_ID")
        return f
    }()

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

struct BudgetCardView: View {
    let budget: Budget?
    let category: Category
    /// Stagger for the segment bar's fill-in, so rows fill one after another.
    var fillDelay: Double = 0
    var onSetBudget: ((Budget) -> Void)?

    @AppStorage("isBalanceVisible") private var isBalanceVisible = true
    @State private var showSetBudget = false
    @State private var amountDigits = ""
    @State private var isSaving = false
    @State private var showBudgetToast = false
    @State private var budgetToastMessage = ""

    var body: some View {
        Group {
            if let budget {
                setCard(budget)
            } else {
                unsetCard
            }
        }
        .sheet(isPresented: $showSetBudget) {
            setBudgetSheet
                .presentationDetents([.height(500)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationBackground(Color.appBackground)
        }
    }

    private var unsetCard: some View {
        HStack(spacing: 14) {
            Image(systemName: category.icon ?? "tag")
                .font(.system(size: 19))
                .foregroundStyle(Color.appTextTertiary)
                .frame(width: 24)
            Text(category.name)
                .font(.app(16))
                .foregroundStyle(Color.appTextSecondary)
                .lineLimit(1)
            Spacer()
            Button("Atur") { showSetBudget = true }
                .font(.app(15, weight: .medium))
                .foregroundStyle(Color.appPrimary)
                .accessibilityLabel("Atur budget \(category.name)")
        }
        .padding(.vertical, 11)
    }

    private var amountValue: Int { Int(amountDigits) ?? 0 }

    private var setBudgetSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Batal") { showSetBudget = false }
                    .font(.app(17))
                    .foregroundStyle(Color.appTextSecondary)
                    .frame(width: 60, alignment: .leading)
                Spacer()
                Text("Atur budget")
                    .font(.app(17, weight: .semibold))
                    .foregroundStyle(Color.appText)
                Spacer()
                Color.clear.frame(width: 60, height: 1)
            }
            .frame(height: 48)
            .padding(.horizontal, 24)
            .padding(.top, 14)

            HStack(spacing: 8) {
                Image(systemName: category.icon ?? "tag")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.appTextSecondary)
                Text(category.name)
                    .font(.app(15))
                    .foregroundStyle(Color.appTextSecondary)
                Text("· per bulan")
                    .font(.app(15))
                    .foregroundStyle(Color.appTextTertiary)
            }
            .padding(.top, 16)

            HeroAmount(value: Double(amountValue), size: .large,
                       color: amountValue > 0 ? .appText : .appTextTertiary)
                .padding(.top, 8)
                .padding(.horizontal, 24)
                .accessibilityLabel("Nominal Rp\(amountValue)")

            Spacer(minLength: 16)

            AmountPad(color: .appPrimary, isEnabled: amountValue > 0, isSaving: isSaving, onPress: { key in
                guard let next = NumberPad.apply(key, to: amountValue) else { return }
                withAnimation(.snappy(duration: 0.2)) { amountDigits = next > 0 ? String(next) : "" }
            }, onSave: save)
            .disabled(isSaving)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(Color.appBackground)
        .toast(isPresented: $showBudgetToast, message: budgetToastMessage)
    }

    private func setCard(_ budget: Budget) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: category.icon ?? "tag")
                .font(.system(size: 19))
                .foregroundStyle(Color.appTextSecondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(category.name)
                        .font(.app(16))
                        .foregroundStyle(Color.appText)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(statusText(budget))
                        .font(.app(15))
                        .foregroundStyle(statusColor(budget))
                        .monospacedDigit()
                        .lineLimit(1)
                }
                SegmentBar(value: budget.progress, color: progressColor(budget), delay: fillDelay)
                Text(isBalanceVisible
                     ? "\(budget.spent.formattedAsCurrency()) dari \(budget.amount.formattedAsCurrency())"
                     : "Rp\(hiddenAmount) dari Rp\(hiddenAmount)")
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private func statusText(_ budget: Budget) -> String {
        let amount: (Double) -> String = { isBalanceVisible ? $0.formattedAsCurrency() : "Rp" + hiddenAmount }
        switch budget.spendingStatus {
        case .normal: return "Sisa " + amount(budget.remaining)
        case .warning: return amount(budget.dailyRemaining) + "/hari"
        case .overbudget: return budget.remaining == 0 ? "Habis" : "Lewat " + amount(abs(budget.remaining))
        }
    }

    private func statusColor(_ budget: Budget) -> Color {
        budget.spendingStatus == .normal ? .appTextSecondary : progressColor(budget)
    }

    private func progressColor(_ budget: Budget) -> Color {
        switch budget.spendingStatus {
        case .overbudget: return .appError
        case .warning: return .appWarning
        case .normal: return .appPrimary
        }
    }

    private func save() {
        guard let amount = Double(amountDigits), amount > 0 else { return }
        isSaving = true
        let startDate = ISO8601DateFormatter().string(from: Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!)
        let budget = Budget(
            id: UUID().uuidString,
            categoryId: category.id,
            name: category.name,
            amount: amount,
            periodUnit: "month",
            periodInterval: 1,
            startDate: startDate,
            endDate: nil,
            isActive: true,
            spent: 0
        )
        onSetBudget?(budget)
        isSaving = false
        showSetBudget = false
        amountDigits = ""
        budgetToastMessage = "Perubahan berhasil disimpan"
        withAnimation { showBudgetToast = true }
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
                        NavigationLink(destination: OverallMonthDetailView(totalBudget: totalBudget, month: history.month, budgetItems: budgetItems, allExpenseTransactions: allExpenseTransactions)) {
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
        let calendar = Calendar.current
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
              let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return [] }
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
                            NavigationLink(destination: BudgetDetailView(budget: item.budget!, category: item.category, allTransactions: [], accounts: [], showHistoryButton: false)) {
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
