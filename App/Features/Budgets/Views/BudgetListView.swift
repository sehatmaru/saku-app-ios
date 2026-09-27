import SwiftUI

struct BudgetListView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel: BudgetListViewModel

    init(viewModel: BudgetListViewModel = BudgetListViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    @AppStorage("isBalanceVisible") private var isBalanceVisibleStorage = true
    @State private var isBalanceVisible = true
    @State private var showUnsetBudget = false
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
                        historyLink

                        if !setItems.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                SectionHeader(title: "Per kategori", trailing: "\(setItems.count) aktif")
                                ForEach(setItems) { item in
                                    budgetCardLink(item)
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
                .presentationDetents([.fraction(0.68), .large])
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

    private var budgetSkeleton: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach([180, 260, 0, 0, 0, 0], id: \.self) { width in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.appFill)
                    .frame(maxWidth: width == 0 ? .infinity : CGFloat(width))
                    .frame(height: width == 260 ? 48 : 14)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .shimmer()
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
                Text("\(pct)%").monospacedDigit()
            }
            .font(.app(15))
            .foregroundStyle(remaining < 0 ? Color.appError : Color.appTextSecondary)

            HeroAmount(value: max(0, remaining), isVisible: isBalanceVisible)
                .padding(.top, 8)

            SegmentBar(
                value: viewModel.totalBudget > 0 ? viewModel.totalSpent / viewModel.totalBudget : 0,
                color: remaining < 0 ? .appError : .appPrimary,
                height: 12
            )
            .padding(.top, 20)

            HStack {
                Text("Terpakai " + masked(viewModel.totalSpent))
                Spacer()
                Text("Budget " + masked(viewModel.totalBudget))
            }
            .font(.app(13))
            .foregroundStyle(Color.appTextSecondary)
            .monospacedDigit()
            .padding(.top, 10)

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
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 24)
    }

    private func masked(_ amount: Double) -> String {
        isBalanceVisible ? amount.formattedAsCurrency() : "Rp" + hiddenAmount
    }

    private var historyLink: some View {
        NavigationLink(destination: OverallBudgetHistoryView(totalBudget: viewModel.totalBudget, monthlyHistory: overallMonthlyHistory, budgetItems: viewModel.budgetItems, allExpenseTransactions: viewModel.allExpenseTransactions)) {
            HStack(spacing: 14) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 19))
                    .foregroundStyle(Color.appTextSecondary)
                    .frame(width: 24)
                Text("Riwayat bulan sebelumnya")
                    .font(.app(16))
                    .foregroundStyle(Color.appText)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appTextTertiary)
            }
            .padding(.vertical, 14)
            .overlay(alignment: .top) { Rectangle().fill(Color.appDivider).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Color.appDivider).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .padding(.horizontal, 24)
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

    private func budgetCardLink(_ item: BudgetListItem) -> some View {
        NavigationLink(destination: budgetDetailDestination(for: item)) {
            BudgetCardView(budget: item.budget, category: item.category, onSetBudget: { budget in
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
    var onSetBudget: ((Budget) -> Void)?

    @AppStorage("isBalanceVisible") private var isBalanceVisible = true
    @State private var showSetBudget = false
    @State private var showAmountKeyboard = false
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
        .rowSeparator()
        .sheet(isPresented: $showSetBudget) {
            setBudgetSheet
                .presentationDetents([.medium])
                .presentationBackground(Color.appCardBackground)
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
            Spacer()
            Button("Atur") { showSetBudget = true }
                .font(.app(15, weight: .medium))
                .foregroundStyle(Color.appPrimary)
                .accessibilityLabel("Atur budget \(category.name)")
        }
        .padding(.vertical, 14)
    }

    private var setBudgetSheet: some View {
        NavigationStack {
            VStack(spacing: Spacing.xl) {
                VStack(spacing: Spacing.sm) {
                    ZStack {
                        Circle()
                            .fill(Color.appPrimary.opacity(0.12))
                            .frame(width: 64, height: 64)
                        Image(systemName: category.icon ?? "tag")
                            .font(.app(26, weight: .medium))
                            .foregroundColor(.appPrimary)
                    }

                    Text(category.name)
                        .font(.app(17, weight: .semibold))
                        .foregroundColor(.appText)
                }
                .padding(.top, Spacing.xl)

                HStack {
                    Text("Rp")
                        .font(.app(17, weight: .medium))
                        .foregroundColor(.appTextSecondary)
                    Text(amountDigits.isEmpty ? "0" : amountDigits.formattedWithThousandSeparator)
                        .font(.app(17, weight: .medium))
                        .foregroundColor(.appText)
                }
                .padding()
                .background(Color.appGroupedBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, Spacing.xl)
                .contentShape(Rectangle())
                .onTapGesture { showAmountKeyboard = true }

                Spacer()

                if isSaving {
                    ProgressView()
                        .tint(.appPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, Spacing.xl)
                        .padding(.bottom, Spacing.xl)
                } else {
                    Button("Simpan") {
                        save()
                    }
                    .frame(maxWidth: .infinity)
                    .font(.app(17, weight: .semibold))
                    .foregroundColor(.appPrimary)
                    .disabled(amountDigits.isEmpty)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.bottom, Spacing.xl)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showAmountKeyboard {
                    AmountKeyboard(amountDigits: $amountDigits, maxDigits: 12) {
                        showAmountKeyboard = false
                    }
                    .padding(.top, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onTapGesture { if showAmountKeyboard { showAmountKeyboard = false } }
            .animation(.easeInOut(duration: 0.25), value: showAmountKeyboard)
            .toast(isPresented: $showBudgetToast, message: budgetToastMessage)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") {
                        showSetBudget = false
                    }
                }
            }
        }
    }

    private func setCard(_ budget: Budget) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: category.icon ?? "tag")
                    .font(.system(size: 19))
                    .foregroundStyle(Color.appTextSecondary)
                    .frame(width: 24)
                Text(category.name)
                    .font(.app(16, weight: .medium))
                    .foregroundStyle(Color.appText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(statusText(budget))
                    .font(.app(14))
                    .foregroundStyle(statusColor(budget))
                    .monospacedDigit()
            }

            Group {
                SegmentBar(value: budget.progress, color: progressColor(budget))
                Text(isBalanceVisible
                     ? "\(budget.spent.formattedAsCurrency()) dari \(budget.amount.formattedAsCurrency())"
                     : "Rp\(hiddenAmount) dari Rp\(hiddenAmount)")
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
                    .monospacedDigit()
            }
            .padding(.leading, 38)
        }
        .padding(.vertical, 16)
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
}

struct OverallBudgetHistoryView: View {
    let totalBudget: Double
    let monthlyHistory: [OverallHistoryItem]
    let budgetItems: [BudgetListItem]
    let allExpenseTransactions: [Transaction]

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
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.md) {
                    ForEach(groupedByYear, id: \.year) { group in
                        VStack(spacing: 0) {
                            Button {
                                withAnimation {
                                    if expandedYears.contains(group.year) {
                                        expandedYears.remove(group.year)
                                    } else {
                                        expandedYears.insert(group.year)
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "calendar")
                                        .font(.app(12))
                                        .foregroundColor(.appTextSecondary)
                                    Text(String(group.year))
                                        .font(.app(13, weight: .medium))
                                        .foregroundColor(.appText)
                                    Spacer()
                                    Text("\(group.items.count)")
                                        .font(.app(12, weight: .semibold))
                                        .foregroundColor(.appTextSecondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Color.appTextSecondary.opacity(0.15))
                                        .clipShape(Capsule())
                                    Image(systemName: "chevron.down")
                                        .font(.app(10))
                                        .foregroundColor(.appTextSecondary)
                                        .rotationEffect(.degrees(expandedYears.contains(group.year) ? 180 : 0))
                                }
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                                .padding(.vertical, 12)
                                .padding(.horizontal, Spacing.lg)
                            }
                            .buttonStyle(.plain)

                            if expandedYears.contains(group.year) {
                                VStack(spacing: 0) {
                                    ForEach(Array(group.items.enumerated()), id: \.element.id) { index, history in
                                        NavigationLink(destination: OverallMonthDetailView(totalBudget: totalBudget, month: history.month, budgetItems: budgetItems, allExpenseTransactions: allExpenseTransactions)) {
                                            historyRow(history)
                                        }
                                        .buttonStyle(.plain)
                                        if index < group.items.count - 1 {
                                            Divider()
                                                .padding(.leading, 48)
                                        }
                                    }
                                }
                                .padding(.top, Spacing.sm)
                                .padding(.bottom, Spacing.md)
                                .padding(.horizontal, Spacing.lg)
                            }
                        }
                        .background(Color.appCardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                    }
                }
                .padding(.top)
            }
            .background(Color.appGroupedBackground)
            .onAppear {
                if expandedYears.isEmpty {
                    let currentYear = Calendar.current.component(.year, from: Date())
                    expandedYears = [currentYear]
                }
            }
            .background(Color.appGroupedBackground)
            .navigationTitle("Riwayat Budget")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func historyRow(_ history: OverallHistoryItem) -> some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(history.statusColor(totalBudget).opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: history.statusColor(totalBudget) == .appPrimary ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.app(11, weight: .semibold))
                        .foregroundColor(history.statusColor(totalBudget))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(history.monthLabel)
                        .font(.app(14, weight: .medium))
                        .foregroundColor(.appText)
                    Text("Budget \(totalBudget.formattedAsCurrency())")
                        .font(.app(11))
                        .foregroundColor(.appTextSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text(history.spent.formattedAsCurrency())
                        .font(.app(14, weight: .semibold))
                        .foregroundColor(history.statusColor(totalBudget))
                    Text("\(Int(history.remainingPct(totalBudget)))%")
                        .font(.app(11))
                        .foregroundColor(.appTextSecondary)
                }
            }

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.appCardBackground)
                    .frame(height: 6)
                Capsule()
                    .fill(history.statusColor(totalBudget))
                    .frame(width: nil, height: 6)
                    .scaleEffect(x: min(history.spent / totalBudget, 1), y: 1, anchor: .leading)
            }
        }
        .padding(.vertical, 10)
    }
}

struct OverallMonthDetailView: View {
    let totalBudget: Double
    let month: Date
    let budgetItems: [BudgetListItem]
    let allExpenseTransactions: [Transaction]

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

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: Spacing.sm) {
                        ZStack {
                            Circle()
                                .fill(Color.appPrimary.opacity(0.12))
                                .frame(width: 40, height: 40)
                            Image(systemName: "chart.pie.fill")
                                .font(.app(17, weight: .medium))
                                .foregroundColor(.appPrimary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(monthLabel)
                                .font(.app(17, weight: .semibold))
                                .foregroundColor(.appText)
                            Text("Budget \(totalBudget.formattedAsCurrency())")
                                .font(.app(12))
                                .foregroundColor(.appTextSecondary)
                        }
                        Spacer()
                        let pctText = progress >= 1 ? "0%" : "\(Int((1 - progress) * 100))%"
                        Text(pctText)
                            .font(.app(15, weight: .semibold))
                            .foregroundColor(progressColor)
                    }
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.xl)

                    HStack(spacing: 0) {
                        Text("Rp")
                            .font(.app(28, weight: .bold))
                            .foregroundColor(.appText)
                        Text(remainingPct <= 0 ? "0" : remaining.formattedAsCurrency().replacingOccurrences(of: "Rp", with: ""))
                            .font(.app(28, weight: .bold))
                            .foregroundColor(.appText)
                        Spacer()
                    }
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.xs)

                    Divider()
                        .padding(.horizontal, Spacing.xl)
                        .padding(.top, Spacing.md)

                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Total Budget")
                                .font(.app(11))
                                .foregroundColor(.appTextSecondary)
                            Text(totalBudget.formattedAsCurrency())
                                .font(.app(14, weight: .semibold))
                                .foregroundColor(.appText)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("Terpakai")
                                .font(.app(11))
                                .foregroundColor(.appTextSecondary)
                            Text(spent.formattedAsCurrency())
                                .font(.app(14, weight: .semibold))
                                .foregroundColor(.appExpense)
                        }
                    }
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.md)

                    ProgressView(value: min(progress, 1.0))
                        .tint(progressColor)
                        .padding(.horizontal, Spacing.xl)
                        .padding(.top, Spacing.sm)
                        .padding(.bottom, Spacing.lg)
                }
                .background(Color.appCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal)

                VStack(spacing: Spacing.sm) {
                    ForEach(budgetItems.filter { $0.budget != nil }) { item in
                        NavigationLink(destination: BudgetDetailView(budget: item.budget!, category: item.category, allTransactions: [], accounts: [], showHistoryButton: false)) {
                            budgetCardContent(item.budget!, item.category)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()

                Color.clear
                    .frame(height: Spacing.xl)
                    .padding(.bottom)
            }
        }
        .background(Color.appGroupedBackground)
        .navigationTitle(monthLabel)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func budgetCardContent(_ budget: Budget, _ category: Category) -> some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                Image(systemName: category.icon ?? "tag")
                    .font(.app(17))
                    .foregroundColor(budget.spendingStatus == .overbudget ? .appError : budget.spendingStatus == .warning ? .appWarning : .appPrimary)
                Text(category.name)
                    .font(.app(15, weight: .medium))
                Spacer()
                Text(budget.progress >= 1 ? "0%" : "\(Int((1 - budget.progress) * 100))%")
                    .font(.app(12, weight: .semibold))
                    .foregroundColor(cardProgressColor(budget))
            }

            ProgressView(value: min(budget.progress, 1.0))
                .tint(cardProgressColor(budget))

            HStack {
                Text("\(budget.spent.formattedAsCurrency()) / \(budget.amount.formattedAsCurrency())")
                    .font(.app(12))
                    .foregroundColor(.appTextSecondary)
                Spacer()
                switch budget.spendingStatus {
                case .normal:
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.down.left")
                            .font(.app(9))
                        Text(budget.remaining.formattedAsCurrency())
                            .font(.app(11))
                    }
                    .foregroundColor(.appTextSecondary)
                case .warning:
                    HStack(spacing: 2) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.app(9))
                        Text("\(budget.dailyRemaining.formattedAsCurrency())/hari")
                            .font(.app(11))
                    }
                    .foregroundColor(.appWarning)
                case .overbudget:
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up.right")
                            .font(.app(9))
                        Text(abs(budget.remaining).formattedAsCurrency())
                            .font(.app(11))
                    }
                    .foregroundColor(.appError)
                }
            }
        }
        .padding()
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func cardProgressColor(_ budget: Budget) -> Color {
        switch budget.spendingStatus {
        case .overbudget: return .appError
        case .warning: return .appWarning
        case .normal: return .appPrimary
        }
    }
}
