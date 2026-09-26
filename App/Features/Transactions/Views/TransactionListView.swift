import SwiftUI

struct TransactionListView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel: TransactionListViewModel

    init(viewModel: TransactionListViewModel = TransactionListViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    @AppStorage("isBalanceVisible") private var isBalanceVisibleStorage = true
    @State private var isBalanceVisible = true
    @State private var filter = TransactionFilter()
    @State private var expandedMonths: Set<String> = []
    /// Months where the user tapped "Tampilkan N lainnya".
    @State private var fullyShownMonths: Set<String> = []
    @State private var searchText = ""
    @State private var showAdvancedSearch = false
    @State private var showBackToTop = false
    @State private var hasInitialExpanded = false

    /// Rows shown per month before "Tampilkan N lainnya".
    private let previewCount = 7

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear
                            .frame(height: 0)
                            .id("scrollTop")

                        ScreenHeader(title: "Transaksi") {
                            Button {
                                withAnimation(.smooth) { isBalanceVisible.toggle() }
                                isBalanceVisibleStorage = isBalanceVisible
                            } label: {
                                Image(systemName: isBalanceVisible ? "eye" : "eye.slash")
                            }
                            .accessibilityLabel(isBalanceVisible ? "Sembunyikan saldo" : "Tampilkan saldo")
                        }

                        searchField
                            .padding(.horizontal, 24)
                            .padding(.top, 14)

                        if let error = viewModel.errorMessage, !viewModel.hasLoadedOnce {
                            errorStateView(message: error)
                                .padding(24)
                        } else if !viewModel.hasLoadedOnce {
                            transactionSkeleton
                        } else {
                            if let error = viewModel.errorMessage {
                                ErrorBanner(message: error).padding(.horizontal, 24).padding(.top, 16)
                            }
                            summary

                            Color.clear
                                .frame(height: 1)
                                .onAppear { showBackToTop = false }
                                .onDisappear { showBackToTop = true }

                            filterChips

                            if filteredTransactions.isEmpty {
                                emptyState
                            } else {
                                groupedTransactionList
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
                .animation(.easeInOut(duration: 0.3), value: viewModel.hasLoadedOnce)
                .background(Color.appBackground)
                .toolbar(.hidden, for: .navigationBar)
                .scrollDismissesKeyboard(.immediately)
                .refreshable {
                    guard let userId = authViewModel.currentUser?.id else { return }
                    await viewModel.loadTransactions(userId: userId, forceRefresh: true)
                }
                .onAppear { expandInitialMonths(); isBalanceVisible = isBalanceVisibleStorage }
                .onChange(of: isBalanceVisibleStorage) { _, newValue in isBalanceVisible = newValue }
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
                                .font(.app(16, weight: .semibold))
                                .foregroundStyle(Color.appText)
                                .frame(width: 44, height: 44)
                                .background(.regularMaterial, in: Circle())
                                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                        }
                        .accessibilityLabel("Kembali ke atas")
                        .padding(.trailing, 24)
                        .padding(.bottom, 16)
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
        guard let first = sections.first else { return }
        expandedMonths = [first.id]
        hasInitialExpanded = true
    }

    private var transactionSkeleton: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach([180, 240, 0, 0, 0, 0], id: \.self) { width in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.appFill)
                    .frame(maxWidth: width == 0 ? .infinity : CGFloat(width))
                    .frame(height: width == 240 ? 40 : 14)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .shimmer()
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(Color.appTextSecondary)
            TextField("Cari transaksi...", text: $searchText)
                .font(.app(16))
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.appTextTertiary)
                }
                .accessibilityLabel("Hapus pencarian")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Summary

    private var summary: some View {
        let net = viewModel.thisMonthBalance
        return VStack(alignment: .leading, spacing: 0) {
            Text("Net cashflow \(Self.monthFormatter.string(from: Date()))")
                .font(.app(15))
                .foregroundStyle(Color.appTextSecondary)

            HeroAmount(
                value: net,
                size: .medium,
                prefix: net > 0 ? "+Rp" : net < 0 ? "−Rp" : "Rp",
                color: net > 0 ? .appIncome : .appText,
                prefixColor: net > 0 ? .appIncome : .appTextSecondary,
                isVisible: isBalanceVisible
            )
            .padding(.top, 8)

            HStack(spacing: 28) {
                flowTotal("Masuk", viewModel.thisMonthIncome)
                flowTotal("Keluar", viewModel.thisMonthExpense)
            }
            .padding(.top, 12)
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

    // MARK: Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterButton
                if hasAdvancedFilters {
                    activeFilterChips
                }
                FilterChip(title: "Semua", isSelected: filter.transactionTypes.isEmpty) {
                    filter.transactionTypes = []
                }
                ForEach([Transaction.TransactionType.income, .expense, .transfer], id: \.self) { type in
                    FilterChip(title: typeLabel(type), isSelected: filter.transactionTypes == [type]) {
                        filter.transactionTypes = filter.transactionTypes == [type] ? [] : [type]
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 2)
        }
        .padding(.bottom, 8)
    }

    private var hasAdvancedFilters: Bool {
        !filter.expenseCategoryIds.isEmpty
        || !filter.incomeCategoryIds.isEmpty
        || filter.dateFrom != nil
        || filter.dateTo != nil
    }

    private var activeFilterChips: some View {
        Group {
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
        let count = filter.activeFilterCount - (filter.transactionTypes.isEmpty ? 0 : 1)
        return Button {
            showAdvancedSearch = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 15))
                .foregroundStyle(count > 0 ? Color.appPrimary : Color.appText)
                .frame(width: 40, height: 34)
                .overlay(Capsule().strokeBorder(count > 0 ? Color.appPrimary : Color.appBorder))
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        Text("\(count)")
                            .font(.app(9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 14, height: 14)
                            .background(Color.appPrimary, in: Circle())
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter lanjutan")
    }

    private func typeLabel(_ type: Transaction.TransactionType) -> String {
        switch type {
        case .income: "Pemasukan"
        case .expense: "Pengeluaran"
        case .transfer: "Transfer"
        case .adjustment: "Penyesuaian saldo"
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
        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                let expanded = expandedMonths.contains(section.id)
                Button {
                    withAnimation {
                        if expanded {
                            expandedMonths.remove(section.id)
                        } else {
                            expandedMonths.insert(section.id)
                        }
                    }
                } label: {
                    monthHeader(section, expanded: expanded)
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) {
                    if index > 0 {
                        Rectangle().fill(Color.appDivider).frame(height: 1)
                    }
                }
                .padding(.top, index > 0 && expandedMonths.contains(sections[index - 1].id) ? 14 : 0)

                if expanded {
                    monthRows(section)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    private func monthHeader(_ section: TransactionSection, expanded: Bool) -> some View {
        let net = section.transactions.reduce(0) { $0 + signedAmount($1) }
        return HStack {
            HStack(spacing: 8) {
                Text(section.label)
                    .font(.app(20, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Color.appText)
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.appTextSecondary)
            }
            Spacer()
            HStack(spacing: 0) {
                Text("\(section.transactions.count) transaksi")
                if !expanded, isBalanceVisible, net != 0 {
                    Text(" · ")
                    Text((net > 0 ? "+Rp" : "−Rp") + net.abbreviatedRupiah())
                        .foregroundStyle(net > 0 ? Color.appIncome : Color.appTextSecondary)
                }
            }
            .font(.app(13))
            .foregroundStyle(Color.appTextSecondary)
            .monospacedDigit()
        }
        .padding(.vertical, expanded ? 14 : 18)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func monthRows(_ section: TransactionSection) -> some View {
        let showAll = fullyShownMonths.contains(section.id)
        let rows = showAll ? section.transactions : Array(section.transactions.prefix(previewCount))
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, transaction in
            if index == 0 || !Calendar.current.isDate(transaction.date, inSameDayAs: rows[index - 1].date) {
                dayHeader(for: transaction.date, in: section.transactions)
            }
            NavigationLink(destination: TransactionDetailView(transaction: transaction, categories: viewModel.categories, accounts: viewModel.accounts)) {
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
            .buttonStyle(RowPressStyle())
        }
        if !showAll, section.transactions.count > previewCount {
            Button("Tampilkan \(section.transactions.count - previewCount) lainnya") {
                withAnimation { _ = fullyShownMonths.insert(section.id) }
            }
            .font(.app(15))
            .foregroundStyle(Color.appPrimary)
            .frame(maxWidth: .infinity)
            .padding(.top, 18)
            .padding(.bottom, 6)
        }
    }

    private func dayHeader(for date: Date, in transactions: [Transaction]) -> some View {
        let total = transactions
            .filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
            .reduce(0) { $0 + signedAmount($1) }
        return HStack {
            Text(DashboardView.dayHeader(for: date))
            Spacer()
            if isBalanceVisible, total != 0 {
                Text((total > 0 ? "+" : "−") + abs(total).formattedAsCurrency())
            }
        }
        .font(.app(13))
        .tracking(0.2)
        .foregroundStyle(Color.appTextSecondary)
        .monospacedDigit()
        .padding(.top, 20)
    }

    /// Income positive, expense negative; transfers don't change the total.
    private func signedAmount(_ transaction: Transaction) -> Double {
        switch transaction.type {
        case .income: transaction.amount
        case .expense: -transaction.amount
        case .transfer, .adjustment: 0
        }
    }

    // MARK: Empty State

    private var emptyState: some View {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSearchEmpty = !trimmedSearchText.isEmpty

        return VStack(spacing: Spacing.md) {
            Image(systemName: isSearchEmpty ? "magnifyingglass" : "tray")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.appTextTertiary)
            Text(isSearchEmpty ? "Tidak ada hasil" : "Belum ada transaksi")
                .font(.app(16))
                .foregroundStyle(Color.appTextSecondary)
            if isSearchEmpty {
                Text("Cari \"\(trimmedSearchText)\"")
                    .font(.app(13))
                    .foregroundStyle(Color.appTextTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        f.locale = Locale(identifier: "id_ID")
        return f
    }()
}

struct ActiveFilterChip: View {
    let title: String
    let onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: 6) {
                Text(title)
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
            .font(.app(14, weight: .medium))
            .padding(.horizontal, 14)
            .frame(height: 34)
            .foregroundStyle(Color.appPrimary)
            .background(Color.appPrimary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Hapus filter")
    }
}

struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.5 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}
