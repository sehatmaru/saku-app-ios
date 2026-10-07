import SwiftUI

/// Riwayat budget: finished periods, three at a time, each opening its categories and transactions.
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
                Text(L("Lihat bagaimana budgetmu di periode sebelumnya."))
                    .font(.app(15))
                    .foregroundStyle(Color.appTextSecondary)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

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
                            periodRow(period).padding(.horizontal, 24)
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
                        .padding(.top, 8)
                    }
                }
            }
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
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(PaydayCycle.current.rangeLabel(for: period.interval.start))
                        .font(.app(16, weight: .medium))
                        .foregroundStyle(Color.appText)
                    if period.hasEstimate { Chip(text: L("Perkiraan")) }
                }
                Text(L("%@ dari %@", money(period.totalSpent), money(period.totalBudget)))
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(Int((period.progress * 100).rounded()))%")
                    .font(.app(15, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(period.status.color)
                Text(period.status.title)
                    .font(.app(12))
                    .foregroundStyle(Color.appTextSecondary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.appTextTertiary)
        }
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

struct BudgetHistoryPeriodView: View {
    let period: BudgetHistoryPeriod
    @ObservedObject var viewModel: BudgetListViewModel
    @AppStorage("isBalanceVisible") private var isBalanceVisible = true

    private func money(_ amount: Double) -> String {
        isBalanceVisible ? amount.formattedAsCurrency() : "Rp" + hiddenAmount
    }

    private func category(_ id: String) -> Category? { viewModel.categories.first { $0.id == id } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                summary
                SectionDivider()
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(title: L("Per kategori"), trailing: L("%lld budget", period.rows.count))
                        .padding(.bottom, 4)
                    ForEach(period.rows) { row in
                        NavigationLink(destination: BudgetHistoryTransactionsView(
                            row: row, category: category(row.categoryId), period: period, viewModel: viewModel).detailPage()) {
                            rowView(row)
                        }
                        .buttonStyle(RowPressStyle())
                    }
                    if period.hasEstimate || period.rows.contains(where: { $0.source == .temporary || $0.isDeleted }) {
                        Text(legend)
                            .font(.app(12))
                            .lineSpacing(2)
                            .foregroundStyle(Color.appTextTertiary)
                            .padding(.top, 14)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 32)
            }
        }
        .background(Color.appBackground)
        .navigationTitle(PaydayCycle.current.rangeLabel(for: period.interval.start))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var legend: String {
        var lines: [String] = []
        if period.rows.contains(where: { $0.source == .temporary }) {
            lines.append(L("Sementara: periode ini memakai budget sementara, bukan budget awal."))
        }
        if period.hasEstimate {
            lines.append(L("Perkiraan: fitur riwayat belum ada saat periode ini berjalan, jadi dipakai nominal budget terakhirmu. Angkanya bisa sedikit berbeda dari yang kamu atur saat itu."))
        }
        if period.rows.contains(where: { $0.isDeleted }) {
            lines.append(L("Sudah dihapus: budget ini sudah kamu hapus, tapi tetap ditampilkan karena aktif di periode ini."))
        }
        return lines.joined(separator: "\n")
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("Terpakai"))
                Spacer()
                Text("\(Int((period.progress * 100).rounded()))%").monospacedDigit()
            }
            .font(.app(15))
            .foregroundStyle(period.status == .over ? Color.appError : Color.appTextSecondary)

            Text(money(period.totalSpent))
                .font(.app(34, weight: .light))
                .monospacedDigit()
                .foregroundStyle(Color.appText)
                .padding(.top, 6)

            SegmentBar(value: period.progress, color: period.status.color, height: 12)
                .padding(.top, 20)

            HStack {
                stat(L("Terpakai"), money(period.totalSpent))
                Spacer()
                stat(L("Budget"), money(period.totalBudget))
            }
            .padding(.top, 12)

            VStack(spacing: 10) {
                flow(L("Masuk"), period.income, Color.appText)
                flow(L("Keluar"), period.expense, Color.appText)
                flow(L("Net"), period.net, period.net < 0 ? Color.appError : Color.appPrimary)
            }
            .padding(.top, 22)

            Text(L("Net = pemasukan - pengeluaran. Transfer antar dompet dan pembayaran kartu tidak dihitung."))
                .font(.app(12))
                .foregroundStyle(Color.appTextTertiary)
                .padding(.top, 8)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 28)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.app(13)).foregroundStyle(Color.appTextSecondary)
            Text(value).font(.app(15, weight: .medium)).monospacedDigit().foregroundStyle(Color.appText)
        }
    }

    private func flow(_ title: String, _ value: Double, _ color: Color) -> some View {
        HStack {
            Text(title).font(.app(15)).foregroundStyle(Color.appTextSecondary)
            Spacer()
            Text(isBalanceVisible ? (value < 0 ? "-" : "") + abs(value).formattedAsCurrency() : "Rp" + hiddenAmount)
                .font(.app(15, weight: .medium)).monospacedDigit().foregroundStyle(color)
        }
    }

    private func rowView(_ row: BudgetHistoryRow) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: category(row.categoryId)?.icon ?? "tag")
                .font(.system(size: 20))
                .foregroundStyle(Color.appTextSecondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(category(row.categoryId)?.name ?? L("Kategori"))
                        .font(.app(16, weight: .medium))
                        .foregroundStyle(Color.appText)
                        .lineLimit(1)
                    if row.source == .temporary { Chip(text: L("Sementara")) }
                    if row.source == .estimate { Chip(text: L("Perkiraan")) }
                    if row.isDeleted { Chip(text: L("Sudah dihapus")) }
                    Spacer(minLength: 0)
                    Text(row.status.title)
                        .font(.app(14))
                        .foregroundStyle(row.status.color)
                }
                SegmentBar(value: row.progress, color: row.status.color)
                Text(L("%@ dari %@", money(row.spent), money(row.amount)))
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
                    .monospacedDigit()
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.appTextTertiary)
                .padding(.top, 4)
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

/// The expenses behind one category row of a past period; the total matches the row.
struct BudgetHistoryTransactionsView: View {
    let row: BudgetHistoryRow
    let category: Category?
    let period: BudgetHistoryPeriod
    @ObservedObject var viewModel: BudgetListViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: L("Transaksi"), trailing: L("%lld transaksi", row.transactions.count))
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 6)
                if row.transactions.isEmpty {
                    EmptyMessage(icon: "tray", title: L("Belum ada transaksi"),
                                 message: L("Tidak ada pengeluaran kategori ini di periode itu."))
                        .padding(.vertical, 32)
                } else {
                    ForEach(row.transactions) { tx in
                        TransactionRowView(transaction: tx, categories: category.map { [$0] } ?? viewModel.categories,
                                           accounts: viewModel.accounts, showAccount: true)
                            .padding(.horizontal, 24)
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

private struct Chip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.app(11, weight: .medium))
            .foregroundStyle(Color.appTextSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.appFill, in: Capsule())
            .lineLimit(1)
    }
}

private extension BudgetHistoryStatus {
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
