import SwiftUI

/// Riwayat budget (design 2a): finished periods, three at a time, each opening its categories (2b)
/// and their transactions (2c).
struct BudgetHistoryView: View {
    @ObservedObject var viewModel: BudgetListViewModel

    @State private var budgets: [BudgetHistoryBudget] = []
    @State private var changes: [BudgetAmountChange] = []
    @State private var periods: [BudgetHistoryPeriod] = []
    @State private var next: Int?
    @State private var isLoaded = false
    @State private var failed = false
    @AppStorage("isBalanceVisible") private var isBalanceVisible = true

    private var shownIds: Set<String> { Set(viewModel.shownExpenseCategories.map(\.id)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if failed {
                    ErrorStateView(message: L("Riwayat belum bisa dimuat.")) { Task { await load() } }
                        .padding(24)
                } else if !isLoaded {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                } else if periods.isEmpty {
                    EmptyMessage(icon: "clock.arrow.circlepath", title: L("Belum ada riwayat"),
                                 message: L("Riwayat muncul setelah periode budget pertamamu selesai."))
                        .padding(.top, 48)
                } else {
                    ForEach(periods) { period in
                        NavigationLink(destination: BudgetHistoryPeriodView(period: period, viewModel: viewModel).detailPage()) {
                            periodRow(period)
                        }
                        .buttonStyle(RowPressStyle())
                    }
                    if next != nil {
                        Button { loadMore() } label: {
                            Text(L("Lihat lebih lama"))
                                .font(.app(15, weight: .medium))
                                .foregroundStyle(Color.appPrimary)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                    if periods.contains(where: \.hasEstimate) {
                        Text(L("Perkiraan: dihitung dari budget yang aktif sekarang, karena budget belum diatur di periode tersebut."))
                            .font(.app(13))
                            .lineSpacing(2)
                            .foregroundStyle(Color.appTextTertiary)
                            .padding(.horizontal, 24)
                            .padding(.top, 14)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color.appBackground)
        .navigationTitle(L("Riwayat budget"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func money(_ amount: Double) -> String {
        isBalanceVisible ? amount.formattedAsCurrency() : "Rp" + hiddenAmount
    }

    private func periodRow(_ period: BudgetHistoryPeriod) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(PaydayCycle.current.rangeLabel(for: period.interval.start))
                        .font(.app(16, weight: .medium))
                        .foregroundStyle(Color.appText)
                    Spacer(minLength: 0)
                    Text(period.status.title)
                        .font(.app(14))
                        .foregroundStyle(period.status == .over ? Color.appError : Color.appTextSecondary)
                }
                SegmentBar(value: period.progress, color: period.status.color, replays: false)
                Text(L("%@ dari %@", money(period.totalSpent), money(period.totalBudget)) + " · \(Int((period.progress * 100).rounded()))%")
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
                    .monospacedDigit()
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.appTextTertiary)
                .padding(.top, 4)
        }
        .padding(.leading, 24)
        .padding(.trailing, 20)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func load() async {
        failed = false
        do {
            async let b = SupabaseRepository.shared.fetchBudgetsForHistory()
            async let c = SupabaseRepository.shared.fetchBudgetAmountChanges()
            (budgets, changes) = try await (b, c)
            let first = BudgetHistory.page(budgets: budgets, changes: changes, transactions: viewModel.allExpenseTransactions,
                                           shownCategoryIds: shownIds)
            periods = first.periods
            next = first.next
            isLoaded = true
        } catch {
            failed = true
        }
    }

    private func loadMore() {
        guard let start = next else { return }
        let more = BudgetHistory.page(from: start, budgets: budgets, changes: changes,
                                      transactions: viewModel.allExpenseTransactions, shownCategoryIds: shownIds)
        withAnimation(.easeInOut(duration: 0.25)) {
            periods += more.periods
            next = more.next
        }
    }
}

/// Detail periode (design 2b): what was spent against the budget, Masuk/Keluar/Net, then each category.
struct BudgetHistoryPeriodView: View {
    let period: BudgetHistoryPeriod
    @ObservedObject var viewModel: BudgetListViewModel
    @AppStorage("isBalanceVisible") private var isBalanceVisible = true

    private func money(_ amount: Double) -> String {
        isBalanceVisible ? amount.formattedAsCurrency() : "Rp" + hiddenAmount
    }

    private func short(_ amount: Double) -> String {
        guard isBalanceVisible else { return hiddenAmount }
        return (amount < 0 ? "−" : "") + (abs(amount) < 1 ? "0" : abs(amount).abbreviatedRupiah())
    }

    private func category(_ id: String) -> Category? { viewModel.categories.first { $0.id == id } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                summary
                SectionDivider()
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(title: L("Per kategori"), trailing: L("%lld budget", period.rows.count))
                        .padding(.horizontal, 24)
                        .padding(.top, 22)
                        .padding(.bottom, 4)
                    ForEach(period.rows) { row in
                        NavigationLink(destination: BudgetHistoryTransactionsView(
                            row: row, category: category(row.categoryId), period: period, viewModel: viewModel).detailPage()) {
                            rowView(row)
                        }
                        .buttonStyle(RowPressStyle())
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .background(Color.appBackground)
        .navigationTitle(PaydayCycle.current.rangeLabel(for: period.interval.start))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("Terpakai")).font(.app(15))
                Spacer()
                if period.hasEstimate { Text(L("Perkiraan")).font(.app(13)) }
            }
            .foregroundStyle(Color.appTextSecondary)

            HeroAmount(value: period.totalSpent, size: .hero, isVisible: isBalanceVisible, weight: .ultraLight)
                .padding(.top, 8)

            SegmentBar(value: period.progress, color: period.status.color, replays: false)
                .padding(.top, 20)

            HStack {
                Text(L("%lld%% terpakai", Int((period.progress * 100).rounded())))
                Spacer()
                (Text(L("dari") + " ") + Text(money(period.totalBudget)).fontWeight(.medium).foregroundStyle(Color.appText))
            }
            .font(.app(15))
            .foregroundStyle(Color.appTextSecondary)
            .monospacedDigit()
            .padding(.top, 10)

            HStack {
                flow(L("Masuk"), short(period.income), Color.appText)
                Spacer()
                flow(L("Keluar"), short(period.expense), Color.appText)
                Spacer()
                flow(L("Net"), short(period.net), period.net < 0 ? Color.appError : Color.appText)
            }
            .padding(.top, 20)

            Text(L("Transfer antar dompet dan bayar kartu tidak dihitung."))
                .font(.app(13))
                .foregroundStyle(Color.appTextTertiary)
                .padding(.top, 8)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 24)
    }

    private func flow(_ title: String, _ value: String, _ color: Color) -> some View {
        (Text(title + " ").foregroundStyle(Color.appTextSecondary) + Text(value).fontWeight(.medium).foregroundStyle(color))
            .font(.app(15))
            .monospacedDigit()
    }

    private func rowView(_ row: BudgetHistoryRow) -> some View {
        let over = row.spent > row.amount
        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: category(row.categoryId)?.icon ?? "tag")
                .font(.system(size: 20))
                .foregroundStyle(Color.appTextSecondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(category(row.categoryId)?.name ?? L("Kategori"))
                        .font(.app(16, weight: .medium))
                        .foregroundStyle(Color.appText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(over ? L("Lewat %@", money(row.spent - row.amount)) : L("Sisa %@", money(row.amount - row.spent)))
                        .font(.app(14))
                        .foregroundStyle(over ? Color.appError : Color.appTextSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                SegmentBar(value: row.progress, color: row.status.color, replays: false)
                Text(L("%@ dari %@", money(row.spent), money(row.amount)) + marker(row))
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
                    .monospacedDigit()
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.appTextTertiary)
                .padding(.top, 4)
        }
        .padding(.leading, 24)
        .padding(.trailing, 20)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    /// Temporary and deleted budgets say so on their last line; estimates are flagged once, above.
    private func marker(_ row: BudgetHistoryRow) -> String {
        var parts: [String] = []
        if row.source == .temporary { parts.append(L("Sementara")) }
        if row.isDeleted { parts.append(L("Sudah dihapus")) }
        return parts.isEmpty ? "" : " · " + parts.joined(separator: " · ")
    }
}

/// Transaksi kategori (design 2c): the category's budget for that period, then its expenses by day.
struct BudgetHistoryTransactionsView: View {
    let row: BudgetHistoryRow
    let category: Category?
    let period: BudgetHistoryPeriod
    @ObservedObject var viewModel: BudgetListViewModel
    @AppStorage("isBalanceVisible") private var isBalanceVisible = true

    private func money(_ amount: Double) -> String {
        isBalanceVisible ? amount.formattedAsCurrency() : "Rp" + hiddenAmount
    }

    private var days: [(day: Date, transactions: [Transaction])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: row.transactions) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        f.locale = AppLanguage.locale
        return f
    }()

    var body: some View {
        let over = row.spent > row.amount
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(L("%@ dari %@", money(row.spent), money(row.amount)))
                            .font(.app(15))
                            .foregroundStyle(Color.appTextSecondary)
                        Spacer(minLength: 0)
                        Text(over ? L("Lewat %@", money(row.spent - row.amount)) : L("Sisa %@", money(row.amount - row.spent)))
                            .font(.app(14))
                            .foregroundStyle(over ? Color.appError : Color.appTextSecondary)
                    }
                    .monospacedDigit()
                    SegmentBar(value: row.progress, color: row.status.color, replays: false)
                        .padding(.top, 10)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                SectionDivider().padding(.top, 22)

                SectionHeader(title: L("Transaksi"), trailing: L("%lld transaksi", row.transactions.count))
                    .padding(.horizontal, 24)
                    .padding(.top, 22)
                    .padding(.bottom, 6)

                if row.transactions.isEmpty {
                    EmptyMessage(icon: "tray", title: L("Belum ada transaksi"),
                                 message: L("Tidak ada pengeluaran kategori ini di periode itu."))
                        .padding(.vertical, 32)
                } else {
                    ForEach(days, id: \.day) { group in
                        Text(Self.dayFormat.string(from: group.day))
                            .font(.app(13, weight: .semibold))
                            .foregroundStyle(Color.appTextSecondary)
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                            .padding(.bottom, 2)
                        ForEach(group.transactions) { tx in
                            TransactionRowView(transaction: tx, categories: category.map { [$0] } ?? viewModel.categories,
                                               accounts: viewModel.accounts, showAccount: true, showDate: false)
                                .padding(.horizontal, 24)
                        }
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .background(Color.appBackground)
        .navigationTitle(category?.name ?? L("Kategori"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension BudgetHistoryStatus {
    var title: String {
        switch self {
        case .safe: return L("Aman")
        case .near: return L("Mendekati")
        case .over: return L("Lewat")
        }
    }

    var color: Color {
        switch self {
        case .safe: return .appPrimary
        case .near: return .appWarning
        case .over: return .appError
        }
    }
}
