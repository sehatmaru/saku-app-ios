import SwiftUI

struct TransactionListView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel: TransactionListViewModel

    /// Opens the add-transaction form from the empty state.
    private let onAdd: () -> Void

    init(viewModel: TransactionListViewModel = TransactionListViewModel(), onAdd: @escaping () -> Void = {}) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onAdd = onAdd
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

                        ScreenHeader(title: L("Transaksi")) {
                            Button {
                                withAnimation(.smooth) { isBalanceVisible.toggle() }
                                isBalanceVisibleStorage = isBalanceVisible
                            } label: {
                                Image(systemName: isBalanceVisible ? "eye" : "eye.slash")
                            }
                            .accessibilityLabel(isBalanceVisible ? L("Sembunyikan saldo") : L("Tampilkan saldo"))
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

                            if !hasNoTransactions {
                                filterChips
                            }

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
                        .accessibilityLabel(L("Kembali ke atas"))
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

    /// 13e: the summary label stays; the amount, chips and rows shimmer.
    private var transactionSkeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Net cashflow \(Self.monthFormatter.string(from: Date()))")
                    .font(.app(15))
                    .foregroundStyle(Color.appTextSecondary)
                SkeletonBlock(width: 230, height: 48, radius: 10)
                    .padding(.top, 8)
                RoundedRectangle(cornerRadius: 3).fill(Color.appFill)
                    .frame(height: 6)
                    .padding(.top, 22)
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 24)

            HStack(spacing: 8) {
                ForEach([40, 76, 92, 84], id: \.self) { width in
                    Capsule().fill(Color.appFill).frame(width: CGFloat(width), height: 34)
                }
            }
            .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 0) {
                SkeletonBlock(width: 150, height: 20, radius: 6)
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        ForEach(Self.skeletonRows, id: \.a) { row in
                            HStack(spacing: 14) {
                                Circle().fill(Color.appFill).frame(width: 24, height: 24)
                                VStack(alignment: .leading, spacing: 7) {
                                    SkeletonBlock(width: geo.size.width * row.a, height: 14)
                                    RoundedRectangle(cornerRadius: 4).fill(Color.appFill)
                                        .frame(width: geo.size.width * row.b, height: 11)
                                }
                                Spacer(minLength: 0)
                                SkeletonBlock(width: row.c, height: 14)
                            }
                            .padding(.vertical, 12)
                        }
                    }
                }
                .frame(height: CGFloat(Self.skeletonRows.count) * 48)
                .padding(.top, 14)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
        .accessibilityLabel(L("Memuat"))
    }

    /// Widths of the skeleton rows: title and subtitle as shares of the row, amount in points.
    private static let skeletonRows: [(a: CGFloat, b: CGFloat, c: CGFloat)] = [
        (0.56, 0.32, 72), (0.44, 0.26, 64), (0.62, 0.36, 80), (0.48, 0.28, 60),
        (0.58, 0.34, 76), (0.40, 0.24, 68), (0.52, 0.30, 70),
    ]

    /// Nothing recorded yet, as opposed to a search or filter that matches nothing.
    private var hasNoTransactions: Bool { viewModel.allTransactions.isEmpty }

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
                .accessibilityLabel(L("Hapus pencarian"))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Summary

    /// Net cashflow in green or red, the money-in vs money-out bar, then Masuk and Keluar.
    private var summary: some View {
        let net = viewModel.thisMonthBalance
        let tone: Color = net > 0 ? .appIncome : net < 0 ? .appError : .appText
        return VStack(alignment: .leading, spacing: 0) {
            Text("Net cashflow \(Self.monthFormatter.string(from: Date()))")
                .font(.app(15))
                .foregroundStyle(Color.appTextSecondary)

            HeroAmount(
                value: net,
                prefix: net > 0 ? "+Rp" : net < 0 ? "−Rp" : "Rp",
                color: hasNoTransactions ? .appTextTertiary : tone,
                prefixColor: hasNoTransactions ? .appTextTertiary : net == 0 ? .appTextSecondary : tone,
                isVisible: isBalanceVisible,
                weight: .ultraLight
            )
            .padding(.top, 8)

            if hasNoTransactions {
                RoundedRectangle(cornerRadius: 3).fill(Color.appDivider)
                    .frame(height: 6)
                    .padding(.top, 22)
            } else {
                FlowSplitBar(income: viewModel.thisMonthIncome, expense: viewModel.thisMonthExpense)
                    .padding(.top, 22)

                HStack {
                    flowTotal(Lx("Masuk", en: "In"), viewModel.thisMonthIncome)
                    Spacer()
                    flowTotal(Lx("Keluar", en: "Out"), viewModel.thisMonthExpense)
                }
                .padding(.top, 12)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 32)
        .padding(.bottom, 28)
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
                FilterChip(title: L("Semua"), isSelected: filter.transactionTypes.isEmpty) {
                    filter.transactionTypes = []
                }
                ForEach([Transaction.TransactionType.income, .expense, .transfer], id: \.self) { type in
                    FilterChip(title: typeLabel(type), isSelected: filter.transactionTypes == [type]) {
                        filter.transactionTypes = filter.transactionTypes == [type] ? [] : [type]
                    }
                }
                FilterChip(title: L("Berulang"), isSelected: filter.recurringOnly) {
                    filter.recurringOnly.toggle()
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
                    title: L("Kategori (%lld)", count),
                    onRemove: {
                        filter.expenseCategoryIds = []
                        filter.incomeCategoryIds = []
                    }
                )
            }

            if let from = filter.dateFrom, let to = filter.dateTo {
                ActiveFilterChip(
                    title: "\(from.formatted(Date.FormatStyle(date: .numeric, time: .omitted).locale(AppLanguage.locale))) - \(to.formatted(Date.FormatStyle(date: .numeric, time: .omitted).locale(AppLanguage.locale)))",
                    onRemove: {
                        filter.dateFrom = nil
                        filter.dateTo = nil
                    }
                )
            } else if let from = filter.dateFrom {
                ActiveFilterChip(
                    title: L("Dari %@", from.formatted(Date.FormatStyle(date: .numeric, time: .omitted).locale(AppLanguage.locale))),
                    onRemove: { filter.dateFrom = nil }
                )
            } else if let to = filter.dateTo {
                ActiveFilterChip(
                    title: L("Sampai %@", to.formatted(Date.FormatStyle(date: .numeric, time: .omitted).locale(AppLanguage.locale))),
                    onRemove: { filter.dateTo = nil }
                )
            }
        }
    }

    private var filterButton: some View {
        let count = filter.activeFilterCount - (filter.transactionTypes.isEmpty ? 0 : 1) - (filter.recurringOnly ? 1 : 0)
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
        .accessibilityLabel(L("Filter lanjutan"))
    }

    private func typeLabel(_ type: Transaction.TransactionType) -> String {
        switch type {
        case .income: L("Pemasukan")
        case .expense: L("Pengeluaran")
        case .transfer: L("Transfer")
        case .adjustment: L("Penyesuaian saldo")
        case .cardPayment: L("Bayar tagihan")
        }
    }

    // MARK: Filtered Transactions

    private var filteredTransactions: [Transaction] {
        var result = viewModel.allTransactions

        if !filter.transactionTypes.isEmpty {
            result = result.filter { filter.transactionTypes.contains($0.type) }
        }

        if filter.recurringOnly {
            result = result.filter(\.isRecurring)
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
                        .foregroundStyle(net > 0 ? Color.appIncome : Color.appError)
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
            NavigationLink(destination: TransactionDetailView(transaction: transaction, categories: viewModel.categories, accounts: viewModel.accounts).detailPage()) {
                TransactionRowView(
                    transaction: transaction,
                    categories: viewModel.categories,
                    accounts: viewModel.accounts,
                    showBalance: isBalanceVisible,
                    showDate: false
                )
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
                    .foregroundStyle(total > 0 ? Color.appIncome : Color.appError)
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
        case .transfer, .adjustment, .cardPayment: 0
        }
    }

    // MARK: Empty State

    /// 13f when nothing is recorded yet, 13g when a search or filter matches nothing.
    @ViewBuilder
    private var emptyState: some View {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasNoTransactions {
            VStack(spacing: 22) {
                EmptyMessage(
                    icon: "tray",
                    title: L("Belum ada transaksi"),
                    message: L("Pemasukan dan pengeluaran yang kamu catat di %@ akan muncul di sini.", Self.monthFormatter.string(from: Date()))
                )
                EmptyStateButton(title: L("Catat transaksi"), action: onAdd)
            }
            .padding(.horizontal, 40)
            .padding(.top, 68)
        } else {
            VStack(spacing: 22) {
                EmptyMessage(
                    icon: "magnifyingglass",
                    title: L("Tidak ada hasil"),
                    message: query.isEmpty
                        ? L("Tidak ada transaksi dengan filter ini.")
                        : L("Tidak ada transaksi \"%@\" dengan filter ini.", query)
                )
                EmptyStateButton(title: L("Hapus filter"), icon: nil, isSecondary: true) {
                    withAnimation(.smooth) {
                        searchText = ""
                        filter = TransactionFilter()
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 96)
        }
    }

    private static var monthFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        f.locale = AppLanguage.locale
        return f
    }
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
