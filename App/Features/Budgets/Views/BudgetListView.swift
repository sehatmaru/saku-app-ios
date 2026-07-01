import SwiftUI

struct BudgetListView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel: BudgetListViewModel

    init(viewModel: BudgetListViewModel = BudgetListViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    @AppStorage("isBalanceVisible") private var isBalanceVisible = true
    @State private var showUnsetBudget = false
    @State private var showOverallHistory = false
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
                VStack(spacing: Spacing.lg) {
                    if let error = viewModel.errorMessage, !viewModel.hasLoadedOnce {
                        errorStateView(message: error)
                            .transition(.opacity)
                    } else if !viewModel.hasLoadedOnce {
                        budgetSkeleton
                            .transition(.opacity)
                    } else {
                        Group {
                            if viewModel.errorMessage != nil {
                                ErrorBanner(message: viewModel.errorMessage!)
                            }
                            summaryCard

                            ForEach(setItems) { item in
                            NavigationLink(destination: BudgetDetailView(
                                budget: item.budget!,
                                category: item.category,
                                allTransactions: viewModel.allExpenseTransactions.filter { $0.categoryId == item.category.id },
                                onAdjustBudget: { updated in
                                    Task {
                                        let categoryId = updated.categoryId
                                        let name = updated.name
                                        let amount = updated.amount
                                        let periodUnit = updated.periodUnit
                                        let periodInterval = updated.periodInterval
                                        let startDate = updated.startDate
                                        let endDate = updated.endDate
                                        let isActive = updated.isActive
                                        guard let userId = authViewModel.currentUser?.id else { return }
                                        await viewModel.updateBudget(id: updated.id, name: name, amount: amount, periodUnit: periodUnit, periodInterval: periodInterval, startDate: startDate, endDate: endDate, isActive: isActive)
                                    }
                                },
                                onUnsetBudget: {
                                    Task {
                                        await viewModel.removeBudget(id: item.budget!.id)
                                    }
                                }
                            )) {
                                BudgetCardView(budget: item.budget, category: item.category, onSetBudget: { budget in
                                    Task {
                                        guard let userId = authViewModel.currentUser?.id else { return }
                                        await viewModel.addBudget(categoryId: budget.categoryId, name: budget.name, amount: budget.amount, periodUnit: budget.periodUnit, periodInterval: budget.periodInterval, startDate: budget.startDate, endDate: budget.endDate, userId: userId)
                                    }
                                })
                            }
                            .buttonStyle(.plain)
                        }

                            if !unsetItems.isEmpty {
                                unsetSection
                            }
                        }
                        .transition(.opacity)
                    }
                }
                .padding()
                .animation(.easeInOut(duration: 0.3), value: viewModel.hasLoadedOnce)
            }
            .background(Color.appGroupedBackground)
            .navigationTitle("Budget")
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
            .sheet(isPresented: $showOverallHistory) {
                OverallBudgetHistoryView(totalBudget: viewModel.totalBudget, monthlyHistory: overallMonthlyHistory, budgetItems: viewModel.budgetItems, allExpenseTransactions: viewModel.allExpenseTransactions)
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
        VStack(spacing: Spacing.lg) {
            skeletonCard(height: 200)
            skeletonCard(height: 128)
            skeletonCard(height: 128)
            skeletonSectionHeader
            skeletonCard(height: 150)
        }
    }

    private var skeletonSectionHeader: some View {
        HStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.appTextSecondary.opacity(0.16))
                .frame(width: 112, height: 18)
            Spacer()
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.appTextSecondary.opacity(0.12))
                .frame(width: 36, height: 18)
        }
        .padding(.horizontal, Spacing.xs)
    }

    private func skeletonCard(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.appTextSecondary.opacity(0.16))
                .frame(width: 140, height: 16)
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.appTextSecondary.opacity(0.12))
                .frame(height: height - 48)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .redacted(reason: .placeholder)
        .shimmer()
    }

    private var unsetSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation {
                    showUnsetBudget.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "chart.pie")
                        .font(.jakarta(12))
                        .foregroundColor(.appTextSecondary)
                    Text("Belum diatur")
                        .font(.jakarta(13, weight: .medium))
                        .foregroundColor(.appText)
                    Spacer()
                    Text("\(unsetItems.count)")
                        .font(.jakarta(12, weight: .semibold))
                        .foregroundColor(.appTextSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.appTextSecondary.opacity(0.15))
                        .clipShape(Capsule())
                    Image(systemName: "chevron.down")
                        .font(.jakarta(10))
                        .foregroundColor(.appTextSecondary)
                        .rotationEffect(.degrees(showUnsetBudget ? 180 : 0))
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .padding(.vertical, 12)
                .padding(.horizontal, Spacing.lg)
            }
            .buttonStyle(.plain)

            if showUnsetBudget {
                VStack(spacing: Spacing.lg) {
                    ForEach(unsetItems) { item in
                        BudgetCardView(budget: item.budget, category: item.category, onSetBudget: { budget in
                            Task {
                                guard let userId = authViewModel.currentUser?.id else { return }
                                await viewModel.addBudget(categoryId: budget.categoryId, name: budget.name, amount: budget.amount, periodUnit: budget.periodUnit, periodInterval: budget.periodInterval, startDate: budget.startDate, endDate: budget.endDate, userId: userId)
                            }
                        })
                    }
                }
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.md)
                .padding(.horizontal, Spacing.lg)
            }
        }
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func miniStatCard(icon: String, label: String, amount: String, color: Color) -> some View {
        VStack(spacing: Spacing.xs) {
            Circle()
                .fill(color.opacity(0.12))
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: icon)
                        .font(.jakarta(11, weight: .semibold))
                        .foregroundColor(color)
                }
            Text(label)
                .font(.jakarta(10))
                .foregroundColor(.appTextSecondary)
            Text(amount)
                .font(.jakarta(12, weight: .semibold))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }

    private var summaryCard: some View {
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

            Divider()
                .padding(.horizontal, Spacing.xl)

            Button {
                showOverallHistory = true
            } label: {
                HStack(spacing: Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(Color.appPrimary.opacity(0.1))
                            .frame(width: 32, height: 32)
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.jakarta(13))
                            .foregroundColor(.appPrimary)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Riwayat Bulan Sebelumnya")
                            .font(.jakarta(13, weight: .medium))
                            .foregroundColor(.appText)
                        Text("Lihat performa budget bulan lalu")
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
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 48))
                .foregroundColor(.appPrimary.opacity(0.08))
                .offset(x: -12, y: -4)
        }
    }

}

struct BudgetCardView: View {
    let budget: Budget?
    let category: Category
    var onSetBudget: ((Budget) -> Void)?

    @AppStorage("isBalanceVisible") private var isBalanceVisible = true
    @State private var showSetBudget = false
    @State private var amountText = ""
    @State private var amountDigits = ""

    var body: some View {
        Group {
            if let budget {
                setCard(budget)
            } else {
                unsetCard
            }
        }
        .padding()
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .sheet(isPresented: $showSetBudget) {
            setBudgetSheet
                .presentationDetents([.medium])
                .presentationBackground(Color.appCardBackground)
        }
    }

    private var unsetCard: some View {
        HStack(spacing: Spacing.md) {
                    Image(systemName: category.icon ?? "tag")
                        .font(.jakarta(17))
                        .foregroundColor(.appPrimary)

            Text(category.name)
                .font(.jakarta(15, weight: .medium))
                .foregroundColor(.appText)

            Spacer()

            Button {
                showSetBudget = true
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "plus.circle.fill")
                        .font(.jakarta(12))
                    Text("Atur Budget")
                        .font(.jakarta(12, weight: .semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.appPrimary)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
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
                            .font(.jakarta(26, weight: .medium))
                            .foregroundColor(.appPrimary)
                    }

                    Text(category.name)
                        .font(.jakarta(17, weight: .semibold))
                        .foregroundColor(.appText)
                }
                .padding(.top, Spacing.xl)

                HStack {
                    Text("Rp")
                        .font(.jakarta(17, weight: .medium))
                        .foregroundColor(.appTextSecondary)
                    TextField("Budget per Bulan", text: $amountText)
                        .font(.jakarta(17, weight: .medium))
                        .keyboardType(.numberPad)
                }
                .padding()
                .background(Color.appGroupedBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, Spacing.xl)

                Spacer()

                Button("Simpan") {
                    save()
                }
                .frame(maxWidth: .infinity)
                .font(.jakarta(17, weight: .semibold))
                .foregroundColor(.appPrimary)
                .disabled(amountDigits.isEmpty)
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.xl)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") {
                        showSetBudget = false
                    }
                }
            }
            .onChange(of: amountText) { _, newValue in
                let digits = String(newValue.filter { $0.isWholeNumber })
                let formatted = digits.formattedWithThousandSeparator
                if formatted != newValue {
                    amountText = formatted
                }
                amountDigits = digits
            }
        }
    }

    private func setCard(_ budget: Budget) -> some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                Image(systemName: category.icon ?? "tag")
                    .font(.jakarta(17))
                    .foregroundColor(budget.spendingStatus == .overbudget ? .appError : budget.spendingStatus == .warning ? .appWarning : .appPrimary)
                Text(category.name)
                    .font(.jakarta(15, weight: .medium))
                Spacer()
                Text(budget.progress >= 1 ? "0%" : "\(Int((1 - budget.progress) * 100))%")
                    .font(.jakarta(12, weight: .semibold))
                    .foregroundColor(progressColor(budget))
            }

            ProgressView(value: min(budget.progress, 1.0))
                .tint(progressColor(budget))

            HStack {
                Text(isBalanceVisible
                     ? "\(budget.spent.formattedAsCurrency()) / \(budget.amount.formattedAsCurrency())"
                     : "Rp*** / Rp***")
                    .font(.jakarta(12))
                    .foregroundColor(.appTextSecondary)
                Spacer()
                switch budget.spendingStatus {
                case .normal:
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.down.left")
                            .font(.jakarta(9))
                        Text(isBalanceVisible ? budget.remaining.formattedAsCurrency() : "Rp***")
                            .font(.jakarta(11))
                    }
                    .foregroundColor(.appTextSecondary)
                case .warning:
                    HStack(spacing: 2) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.jakarta(9))
                        Text(isBalanceVisible ? "\(budget.dailyRemaining.formattedAsCurrency())/hari" : "Rp***/hari")
                            .font(.jakarta(11))
                    }
                    .foregroundColor(.appWarning)
                case .overbudget:
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up.right")
                            .font(.jakarta(9))
                        Text(isBalanceVisible ? abs(budget.remaining).formattedAsCurrency() : "Rp***")
                            .font(.jakarta(11))
                    }
                    .foregroundColor(.appError)
                }
            }
        }
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
        showSetBudget = false
        amountText = ""
        amountDigits = ""
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

    @Environment(\.dismiss) private var dismiss
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
                                        .font(.jakarta(12))
                                        .foregroundColor(.appTextSecondary)
                                    Text(String(group.year))
                                        .font(.jakarta(13, weight: .medium))
                                        .foregroundColor(.appText)
                                    Spacer()
                                    Text("\(group.items.count)")
                                        .font(.jakarta(12, weight: .semibold))
                                        .foregroundColor(.appTextSecondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Color.appTextSecondary.opacity(0.15))
                                        .clipShape(Capsule())
                                    Image(systemName: "chevron.down")
                                        .font(.jakarta(10))
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Tutup") {
                        dismiss()
                    }
                    .font(.jakarta(15, weight: .medium))
                }
            }
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
                        .font(.jakarta(11, weight: .semibold))
                        .foregroundColor(history.statusColor(totalBudget))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(history.monthLabel)
                        .font(.jakarta(14, weight: .medium))
                        .foregroundColor(.appText)
                    Text("Budget \(totalBudget.formattedAsCurrency())")
                        .font(.jakarta(11))
                        .foregroundColor(.appTextSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text(history.spent.formattedAsCurrency())
                        .font(.jakarta(14, weight: .semibold))
                        .foregroundColor(history.statusColor(totalBudget))
                    Text("\(Int(history.remainingPct(totalBudget)))%")
                        .font(.jakarta(11))
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
                                .font(.jakarta(17, weight: .medium))
                                .foregroundColor(.appPrimary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(monthLabel)
                                .font(.jakarta(17, weight: .semibold))
                                .foregroundColor(.appText)
                            Text("Budget \(totalBudget.formattedAsCurrency())")
                                .font(.jakarta(12))
                                .foregroundColor(.appTextSecondary)
                        }
                        Spacer()
                        Text(progress >= 1 ? "0%" : "\(Int((1 - progress) * 100))%")
                            .font(.jakarta(15, weight: .semibold))
                            .foregroundColor(progressColor)
                    }
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.xl)

                    HStack(spacing: 0) {
                        Text("Rp")
                            .font(.jakarta(28, weight: .bold))
                            .foregroundColor(.appText)
                        Text(remainingPct <= 0 ? "0" : remaining.formattedAsCurrency().replacingOccurrences(of: "Rp", with: ""))
                            .font(.jakarta(28, weight: .bold))
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
                                .font(.jakarta(11))
                                .foregroundColor(.appTextSecondary)
                            Text(totalBudget.formattedAsCurrency())
                                .font(.jakarta(14, weight: .semibold))
                                .foregroundColor(.appText)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("Terpakai")
                                .font(.jakarta(11))
                                .foregroundColor(.appTextSecondary)
                            Text(spent.formattedAsCurrency())
                                .font(.jakarta(14, weight: .semibold))
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
                        NavigationLink(destination: BudgetDetailView(budget: item.budget!, category: item.category, allTransactions: [], showHistoryButton: false)) {
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
                    .font(.jakarta(17))
                    .foregroundColor(budget.spendingStatus == .overbudget ? .appError : budget.spendingStatus == .warning ? .appWarning : .appPrimary)
                Text(category.name)
                    .font(.jakarta(15, weight: .medium))
                Spacer()
                Text(budget.progress >= 1 ? "0%" : "\(Int((1 - budget.progress) * 100))%")
                    .font(.jakarta(12, weight: .semibold))
                    .foregroundColor(cardProgressColor(budget))
            }

            ProgressView(value: min(budget.progress, 1.0))
                .tint(cardProgressColor(budget))

            HStack {
                Text("\(budget.spent.formattedAsCurrency()) / \(budget.amount.formattedAsCurrency())")
                    .font(.jakarta(12))
                    .foregroundColor(.appTextSecondary)
                Spacer()
                switch budget.spendingStatus {
                case .normal:
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.down.left")
                            .font(.jakarta(9))
                        Text(budget.remaining.formattedAsCurrency())
                            .font(.jakarta(11))
                    }
                    .foregroundColor(.appTextSecondary)
                case .warning:
                    HStack(spacing: 2) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.jakarta(9))
                        Text("\(budget.dailyRemaining.formattedAsCurrency())/hari")
                            .font(.jakarta(11))
                    }
                    .foregroundColor(.appWarning)
                case .overbudget:
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up.right")
                            .font(.jakarta(9))
                        Text(abs(budget.remaining).formattedAsCurrency())
                            .font(.jakarta(11))
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

#Preview {
    BudgetListPreview()
}

struct BudgetListPreview: View {
    @StateObject private var vm: BudgetListViewModel = {
        let v = BudgetListViewModel()
        v.hasLoadedOnce = true
        v.totalBudget = 2_000_000
        v.totalSpent = 1_200_000
        v.categories = [
            Category(id: "1", name: "Makanan", icon: "fork.knife", color: "#FF6B6B", type: .expense),
            Category(id: "2", name: "Transport", icon: "car.fill", color: "#4ECDC4", type: .expense),
            Category(id: "3", name: "Belanja", icon: "bag.fill", color: "#45B7D1", type: .expense),
        ]
        v.budgets = [
            Budget(id: "b1", categoryId: "1", name: "Makanan", amount: 800_000, periodUnit: "month", periodInterval: 1, startDate: "2026-07-01", endDate: nil, isActive: true, spent: 550_000),
            Budget(id: "b2", categoryId: "2", name: "Transport", amount: 500_000, periodUnit: "month", periodInterval: 1, startDate: "2026-07-01", endDate: nil, isActive: true, spent: 420_000),
        ]
        return v
    }()

    var body: some View {
        BudgetListView(viewModel: vm)
            .environmentObject(AuthViewModel())
    }
}
