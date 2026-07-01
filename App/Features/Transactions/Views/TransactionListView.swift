import SwiftUI

struct TransactionListView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel: TransactionListViewModel

    init(viewModel: TransactionListViewModel = TransactionListViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    @AppStorage("isBalanceVisible") private var isBalanceVisible = true
    @State private var filter = TransactionFilter()
    @State private var expandedMonths: Set<String> = []
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var showAdvancedSearch = false
    @State private var showBackToTop = false
    @State private var hasInitialExpanded = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ZStack {
                    ScrollView {
                        VStack(spacing: 0) {
                            Color.clear
                                .frame(height: 0)
                                .id("scrollTop")

                            if let error = viewModel.errorMessage, !viewModel.hasLoadedOnce {
                                errorStateView(message: error)
                                    .transition(.opacity)
                            } else if !viewModel.hasLoadedOnce {
                                transactionSkeleton
                                    .transition(.opacity)
                            } else {
                                Group {
                                    if viewModel.errorMessage != nil {
                                        ErrorBanner(message: viewModel.errorMessage!)
                                    }
                                    summaryCard
                                        .padding(.horizontal)

                                    Color.clear
                                        .frame(height: 1)
                                        .onAppear { showBackToTop = false }
                                        .onDisappear { showBackToTop = true }

                                    filterChips
                                        .padding(.top, Spacing.xs)

                                    if filteredTransactions.isEmpty {
                                        emptyState
                                    } else {
                                        groupedTransactionList
                                    }

                                    Color.clear
                                        .frame(height: Spacing.xl)
                                }
                                .transition(.opacity)
                            }
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: viewModel.hasLoadedOnce)
                    .background(Color.appGroupedBackground)
                    .navigationBarTitleDisplayMode(.inline)
                    .searchable(
                        text: $searchText,
                        isPresented: $isSearching,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Cari transaksi..."
                    )
                    .scrollDismissesKeyboard(.immediately)
                    .navigationTitle("")
                    .refreshable {
                        guard let userId = authViewModel.currentUser?.id else { return }
                        await viewModel.loadTransactions(userId: userId, forceRefresh: true)
                    }
                    .onAppear { expandInitialMonths() }
                    .onChange(of: viewModel.allTransactions.count) { _, _ in expandInitialMonths() }
                    .task {
                        guard let userId = authViewModel.currentUser?.id, viewModel.allTransactions.isEmpty else { return }
                        await viewModel.loadTransactions(userId: userId)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .dataDidChange)) { _ in
                        guard let userId = authViewModel.currentUser?.id else { return }
                        Task {
                            await viewModel.loadTransactions(userId: userId, forceRefresh: true)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if showBackToTop {
                            Button {
                                withAnimation(.spring(response: 0.4)) {
                                    proxy.scrollTo("scrollTop", anchor: .top)
                                }
                            } label: {
                                Image(systemName: "chevron.up")
                                    .font(.jakarta(16, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(Color.appPrimary)
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                            }
                            .padding(.trailing, Spacing.xl)
                            .padding(.bottom, Spacing.xl)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: showBackToTop)
                    .sheet(isPresented: $showAdvancedSearch) {
                        AdvancedSearchView(filter: $filter, categories: viewModel.categories)
                            .presentationDetents([.medium, .large])
                    }
                }
            }
        }
    }

    private func errorStateView(message: String) -> some View {
        ErrorStateView(message: message) {
            guard let userId = authViewModel.currentUser?.id else { return }
            Task {
                await viewModel.loadTransactions(userId: userId, forceRefresh: true)
            }
        }
    }

    private func expandInitialMonths() {
        guard !hasInitialExpanded else { return }
        let sections = viewModel.sections(for: filteredTransactions)
        guard !sections.isEmpty else { return }
        expandedMonths = Set(sections.prefix(2).map { $0.id })
        hasInitialExpanded = true
    }

    private var transactionSkeleton: some View {
        VStack(spacing: Spacing.lg) {
            RoundedRectangle(cornerRadius: 20).fill(Color.appCardBackground).frame(height: 170).redacted(reason: .placeholder)
            RoundedRectangle(cornerRadius: 16).fill(Color.appCardBackground).frame(height: 56).redacted(reason: .placeholder)
            RoundedRectangle(cornerRadius: 16).fill(Color.appCardBackground).frame(height: 260).redacted(reason: .placeholder)
        }
        .padding()
        .shimmer()
    }

    // MARK: Summary

    private var summaryCard: some View {
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
                let balance = viewModel.thisMonthBalance
                Text(isBalanceVisible
                     ? (balance >= 0
                        ? balance.formattedAsCurrency()
                        : "-\(abs(balance).formattedAsCurrency())")
                     : "********")
                    .font(.jakarta(34, weight: .bold))
                    .foregroundColor(balance >= 0 ? .appText : .appError)
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
                    amount: viewModel.thisMonthIncome,
                    color: .appIncome,
                    icon: "arrow.down"
                )

                miniStatCard(
                    label: "Pengeluaran",
                    amount: viewModel.thisMonthExpense,
                    color: .appExpense,
                    icon: "arrow.up"
                )
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.lg)
        }
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(alignment: .topTrailing) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 48))
                .foregroundColor(.appPrimary.opacity(0.08))
                .offset(x: -12, y: -4)
        }
        .padding(.top)
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

    // MARK: Filter Chips

    private var filterChips: some View {
        HStack(spacing: Spacing.sm) {
            filterButton

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    if hasAdvancedFilters {
                        activeFilterChips
                    } else {
                        defaultFilterChips
                    }
                }
                .padding(.vertical, Spacing.sm)
            }
        }
        .padding(.horizontal)
    }

    private var hasAdvancedFilters: Bool {
        !filter.expenseCategoryIds.isEmpty
        || !filter.incomeCategoryIds.isEmpty
        || filter.dateFrom != nil
        || filter.dateTo != nil
    }

    private var defaultFilterChips: some View {
        Group {
            FilterChip(title: "Pemasukan", isSelected: filter.transactionTypes.contains(.income)) {
                toggleType(.income)
            }
            FilterChip(title: "Pengeluaran", isSelected: filter.transactionTypes.contains(.expense)) {
                toggleType(.expense)
            }
            FilterChip(title: "Transfer", isSelected: filter.transactionTypes.contains(.transfer)) {
                toggleType(.transfer)
            }
        }
    }

    private var activeFilterChips: some View {
        Group {
            if !filter.transactionTypes.isEmpty {
                ForEach(Array(filter.transactionTypes).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { type in
                    FilterChip(title: typeLabel(type), isSelected: true) {
                        filter.transactionTypes.remove(type)
                    }
                }
            }

            if !filter.expenseCategoryIds.isEmpty || !filter.incomeCategoryIds.isEmpty {
                let count = filter.expenseCategoryIds.count + filter.incomeCategoryIds.count
                ActiveFilterChip(
                    title: "Kategori (\(count))",
                    onRemove: {
                        filter.expenseCategoryIds = []
                        filter.incomeCategoryIds = []
                    }
                )
            }

            if let from = filter.dateFrom, let to = filter.dateTo {
                ActiveFilterChip(
                    title: "\(from.formatted(date: .numeric, time: .omitted)) - \(to.formatted(date: .numeric, time: .omitted))",
                    onRemove: {
                        filter.dateFrom = nil
                        filter.dateTo = nil
                    }
                )
            } else if let from = filter.dateFrom {
                ActiveFilterChip(
                    title: "Dari \(from.formatted(date: .numeric, time: .omitted))",
                    onRemove: { filter.dateFrom = nil }
                )
            } else if let to = filter.dateTo {
                ActiveFilterChip(
                    title: "Sampai \(to.formatted(date: .numeric, time: .omitted))",
                    onRemove: { filter.dateTo = nil }
                )
            }
        }
    }

    private var filterButton: some View {
        Button {
            showAdvancedSearch = true
        } label: {
            Text(Image(systemName: "line.3.horizontal.decrease"))
                .font(.jakarta(14, weight: filter.hasActiveFilters ? .semibold : .regular))
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .background(filter.hasActiveFilters ? Color.appPrimary.opacity(0.12) : Color(.systemGray6))
                .foregroundColor(filter.hasActiveFilters ? Color.appPrimary : .appText)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topTrailing) {
                    if filter.hasActiveFilters {
                        Text("\(filter.activeFilterCount)")
                            .font(.jakarta(9, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 14, height: 14)
                            .background(Color.appPrimary)
                            .clipShape(Circle())
                            .offset(x: 5, y: -5)
                    }
                }
        }
    }

    private func typeLabel(_ type: Transaction.TransactionType) -> String {
        switch type {
        case .income: "Pemasukan"
        case .expense: "Pengeluaran"
        case .transfer: "Transfer"
        }
    }

    private func toggleType(_ type: Transaction.TransactionType) {
        if filter.transactionTypes.contains(type) {
            filter.transactionTypes.remove(type)
        } else {
            filter.transactionTypes.insert(type)
        }
    }

    // MARK: Filtered Transactions

    private var filteredTransactions: [Transaction] {
        var result = viewModel.allTransactions

        if !filter.transactionTypes.isEmpty {
            result = result.filter { filter.transactionTypes.contains($0.type) }
        }

        if !filter.expenseCategoryIds.isEmpty {
            result = result.filter { tx in
                guard tx.type == .expense, let catId = tx.categoryId else { return true }
                return filter.expenseCategoryIds.contains(catId)
            }
        }

        if !filter.incomeCategoryIds.isEmpty {
            result = result.filter { tx in
                guard tx.type == .income, let catId = tx.categoryId else { return true }
                return filter.incomeCategoryIds.contains(catId)
            }
        }

        if let from = filter.dateFrom {
            result = result.filter { $0.date >= from }
        }
        if let to = filter.dateTo {
            let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: to)!
            result = result.filter { $0.date <= endOfDay }
        }

        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearchText.isEmpty {
            result = result.filter { transaction in
                let note = transaction.note ?? ""
                return note.localizedCaseInsensitiveContains(trimmedSearchText)
            }
        }

        return result
    }

    // MARK: Grouped List

    private var groupedTransactionList: some View {
        let sections = viewModel.sections(for: filteredTransactions)
        return LazyVStack(spacing: Spacing.lg) {
            ForEach(sections) { section in
                VStack(spacing: 0) {
                    Button {
                        withAnimation {
                            if expandedMonths.contains(section.id) {
                                expandedMonths.remove(section.id)
                            } else {
                                expandedMonths.insert(section.id)
                            }
                        }
                    } label: {
                        sectionHeader(section)
                    }
                    .buttonStyle(.plain)

                    if expandedMonths.contains(section.id) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(section.transactions.enumerated()), id: \.element.id) { index, transaction in
                                NavigationLink(destination: TransactionDetailView(transaction: transaction, categories: viewModel.categories, accounts: viewModel.accounts)) {
                                    transactionRow(transaction)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, Spacing.lg)
                                if index < section.transactions.count - 1 {
                                    Divider()
                                        .padding(.leading, 52)
                                }
                            }
                        }
                        .padding(.vertical, Spacing.sm)
                    }
                }
                .background(Color.appCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)
            }
        }
        .padding(.top, Spacing.sm)
    }

    private func sectionHeader(_ section: TransactionSection) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.appPrimary)
                    .frame(width: 4)
                    .clipShape(Capsule())

                HStack(spacing: 4) {
                    Text(section.label)
                        .font(.jakarta(15, weight: .semibold))
                        .foregroundColor(.appText)

                    Spacer()

                    Text("\(section.transactions.count) transaksi")
                        .font(.jakarta(13, weight: .semibold))
                        .foregroundColor(.appTextSecondary)

                    Image(systemName: "chevron.down")
                        .font(.jakarta(9))
                        .foregroundColor(.appTextSecondary)
                        .rotationEffect(.degrees(expandedMonths.contains(section.id) ? 0 : -90))
                        .padding(.leading, 4)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, 12)
            }
        }
    }

    private func transactionRow(_ transaction: Transaction) -> some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(transactionColor(transaction.type).opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: categoryIcon(for: transaction))
                    .font(.jakarta(16))
                    .foregroundColor(transactionColor(transaction.type))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.note ?? label(for: transaction.type))
                    .font(.jakarta(14, weight: .medium))
                Text(transaction.date.formatted(date: .numeric, time: .omitted))
                    .font(.jakarta(11))
                    .foregroundColor(.appTextSecondary)
            }

            Spacer()

            Text(transaction.amount.formattedAsCurrency())
                .font(.jakarta(14, weight: .semibold))
                .foregroundColor(transactionColor(transaction.type))
        }
        .padding(.vertical, Spacing.sm)
    }

    private func transactionColor(_ type: Transaction.TransactionType) -> Color {
        switch type {
        case .income: .appIncome
        case .expense: .appExpense
        case .transfer: .appPrimary
        }
    }

    private func label(for type: Transaction.TransactionType) -> String {
        switch type {
        case .income: "Pemasukan"
        case .expense: "Pengeluaran"
        case .transfer: "Transfer"
        }
    }

    private func categoryIcon(for transaction: Transaction) -> String {
        guard let categoryId = transaction.categoryId else {
            switch transaction.type {
            case .income: return "arrow.down"
            case .expense: return "arrow.up"
            case .transfer: return "arrow.left.arrow.right"
            }
        }
        let category = viewModel.categories.first { $0.id == categoryId }
        return category?.icon ?? (transaction.type == .income ? "arrow.down" : "arrow.up")
    }

    // MARK: Empty State

    private var emptyState: some View {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSearchEmpty = !trimmedSearchText.isEmpty

        return VStack(spacing: Spacing.md) {
            Image(systemName: isSearchEmpty ? "magnifyingglass" : "tray")
                .font(.jakarta(40))
                .foregroundColor(.appTextSecondary)
            Text(isSearchEmpty ? "Tidak ada hasil" : "Belum ada transaksi")
                .font(.jakarta(15))
                .foregroundColor(.appTextSecondary)
            if isSearchEmpty {
                Text("Cari \"\(trimmedSearchText)\"")
                    .font(.jakarta(13))
                    .foregroundColor(.appTextSecondary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xxxl)
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding()
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

struct ActiveFilterChip: View {
    let title: String
    let onRemove: () -> Void

    var body: some View {
        Text(title)
            .font(.jakarta(14))
            .fontWeight(.semibold)
            .lineLimit(1)
            .padding(.leading, Spacing.lg)
            .padding(.trailing, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .background(Color.appPrimary.opacity(0.12))
            .foregroundColor(Color.appPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .topTrailing) {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.jakarta(7, weight: .bold))
                        .foregroundColor(.white)
                        .padding(3)
                        .background(Color.appPrimary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .offset(x: 5, y: -5)
            }
    }
}

#Preview {
    TransactionListPreview()
}

struct TransactionListPreview: View {
    @StateObject private var vm: TransactionListViewModel = {
        let v = TransactionListViewModel()
        v.hasLoadedOnce = true
        v.allTransactions = [
            Transaction(id: "1", accountId: "a1", counterpartyAccountId: nil, categoryId: "1", amount: 50_000, type: .expense, description: nil, note: "Nasi Goreng", date: Date()),
            Transaction(id: "2", accountId: "a1", counterpartyAccountId: nil, categoryId: "2", amount: 20_000, type: .expense, description: nil, note: "Bensin", date: Date()),
            Transaction(id: "3", accountId: "a1", counterpartyAccountId: nil, categoryId: nil, amount: 500_000, type: .income, description: nil, note: "Gaji", date: Date()),
        ]
        v.categories = [
            Category(id: "1", name: "Makanan", icon: "fork.knife", color: "#FF6B6B", type: .expense),
            Category(id: "2", name: "Transport", icon: "car.fill", color: "#4ECDC4", type: .expense),
        ]
        v.accounts = [
            Account(id: "a1", name: "BCA", type: .bank, icon: "building.columns.fill", isArchived: false, openingBalance: 5_000_000, currentBalance: 5_430_000),
        ]
        v.thisMonthIncome = 3_200_000
        v.thisMonthExpense = 2_750_000
        return v
    }()

    var body: some View {
        TransactionListView(viewModel: vm)
            .environmentObject(AuthViewModel())
    }
}
