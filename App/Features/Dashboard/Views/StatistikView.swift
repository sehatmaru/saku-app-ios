import SwiftUI

/// Statistik (Enhancement 1, Epic 8): the whole payday period on one page, free for everyone. It replaces the old
/// Analitik page and follows the "Beranda" privacy switch. All figures are worked out on the device by `PeriodStatistics`.
struct StatistikView: View {
    /// "Buat budget": the Budget tab, with this page closed behind it.
    var onOpenBudget: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var data = ExportViewModel()
    @AppStorage("isBalanceVisible") private var isVisible = true
    /// 0 is the running period, -1 the one before, and so on.
    @State private var offset = 0
    @State private var showsAdd = false

    private var cycle: PaydayCycle { PaydayCycle.current }
    private var userId: String? { authViewModel.currentUser?.id }
    private var firstRecord: Date? { data.transactions.map(\.date).min() }

    private var result: PeriodStatistics.Result {
        let interval = cycle.period(offset: offset)
        let expenseIds = Set(data.categories.filter { $0.type == .expense }.map(\.id))
        let names = Dictionary(data.categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let period = BudgetHistory.period(interval, budgets: data.historyBudgets, changes: data.amountChanges,
                                          transactions: data.transactions, shownCategoryIds: expenseIds)
        let lines = (period?.rows ?? []).map {
            ReportModel.BudgetLine(name: names[$0.categoryId] ?? L("Tanpa kategori"), spent: $0.spent, amount: $0.amount,
                                   isProvisional: $0.source == .temporary)
        }
        return PeriodStatistics.make(transactions: data.transactions, categories: data.categories, accounts: data.accounts,
                                     budgetLines: lines, cycle: cycle, interval: interval)
    }

    /// An earlier period is only worth opening when it ends after the first record.
    private var canGoBack: Bool {
        guard let firstRecord else { return false }
        return cycle.period(offset: offset - 1).end > firstRecord
    }

    var body: some View {
        Group {
            if data.isReady {
                ScrollView {
                    StatistikPage(result: result, isVisible: isVisible, canGoBack: canGoBack, canGoForward: offset < 0,
                                  onBack: { withAnimation(.smooth) { offset -= 1 } },
                                  onForward: { withAnimation(.smooth) { offset += 1 } },
                                  onAdd: { showsAdd = true },
                                  onOpenBudget: { onOpenBudget(); dismiss() })
                        .id(offset)
                }
                .scrollIndicators(.hidden)
            } else if data.loadFailed {
                VStack(spacing: 12) {
                    Text("Statistik belum bisa dimuat. Periksa koneksi lalu coba lagi.")
                        .font(.app(15)).foregroundStyle(Color.appTextSecondary).multilineTextAlignment(.center)
                    Button(L("Coba lagi")) { Task { await data.load(userId: userId) } }
                        .font(.app(16, weight: .semibold)).foregroundStyle(Color.appPrimary)
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.appBackground)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.smooth) { isVisible.toggle() }
                } label: {
                    // eye.slash is taller than eye; a fixed frame keeps the bar still.
                    Image(systemName: isVisible ? "eye" : "eye.slash").font(.system(size: 18)).foregroundStyle(Color.appTextSecondary)
                        .frame(width: 28, height: 25)
                }
                .accessibilityLabel(isVisible ? L("Sembunyikan saldo") : L("Tampilkan saldo"))
            }
        }
        .task { await data.load(userId: userId) }
        .sheet(isPresented: $showsAdd) {
            if let userId {
                AddTransactionView(categories: data.categories, accounts: data.accounts, userId: userId, onSave: {})
            }
        }
    }
}

// MARK: - Page

/// The page for one computed period. Pure: it is handed the numbers, so it can be drawn for a check without a network.
struct StatistikPage: View {
    let result: PeriodStatistics.Result
    var isVisible = true
    var canGoBack = true
    var canGoForward = false
    var animated = true
    var onBack: () -> Void = {}
    var onForward: () -> Void = {}
    var onAdd: () -> Void = {}
    var onOpenBudget: () -> Void = {}
    @State private var appeared = false

    // Layout A of the design ("padat").
    private let pad: CGFloat = 16, gap: CGFloat = 10, radius: CGFloat = 16, titleSize: CGFloat = 17, heroSize: CGFloat = 40

    private var money: StatistikMoney { StatistikMoney(isVisible: isVisible) }
    private var isShown: Bool { appeared || !animated }

    var body: some View {
        VStack(alignment: .leading, spacing: gap) {
            Text("Statistik").font(.app(34, weight: .bold)).tracking(-0.7).padding(.bottom, 2)
            periodPicker
            if result.isEmpty {
                emptyState
                if let assets = result.assets { assetsCard(assets) }
            } else {
                summaryCard.rise(isShown, y: 14, delay: 0.06)
                if let assets = result.assets { assetsCard(assets).rise(isShown, y: 14, delay: 0.09) }
                calendarCard.rise(isShown, y: 14, delay: 0.12)
                trendCard.rise(isShown, y: 14, delay: 0.18)
                expenseCard.rise(isShown, y: 14, delay: 0.24)
                incomeCard.rise(isShown, y: 14, delay: 0.30)
                walletCard.rise(isShown, y: 14, delay: 0.36)
                timeCard.rise(isShown, y: 14, delay: 0.42)
                budgetCard.rise(isShown, y: 14, delay: 0.48)
                highlightsCard.rise(isShown, y: 14, delay: 0.54)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 100)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { appeared = true }
    }

    // MARK: Chrome

    private func card<Content: View>(_ title: String, trailing: String? = nil, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.app(titleSize, weight: .semibold))
                if let trailing {
                    Spacer(minLength: 8)
                    Text(trailing).font(.app(12)).foregroundStyle(Color.appTextSecondary)
                }
            }
            content()
        }
        .padding(pad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: radius))
    }

    private func label(_ text: String) -> some View { Text(text).font(.app(12)).foregroundStyle(Color.appTextSecondary) }

    private func stat(_ title: String, _ value: String, color: Color = .appText, sub: String? = nil, bold: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            label(title)
            Text(value).font(.app(bold ? 15 : 17, weight: bold ? .semibold : .medium)).monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
            if let sub { label(sub).monospacedDigit().lineLimit(2).fixedSize(horizontal: false, vertical: true) }
        }
    }

    private var periodPicker: some View {
        HStack {
            stepButton("chevron.left", enabled: canGoBack, action: onBack)
            Spacer()
            VStack(spacing: 0) {
                Text(result.label).font(.app(15, weight: .semibold))
                Text(periodSub).font(.app(12)).foregroundStyle(Color.appTextSecondary)
            }
            Spacer()
            stepButton("chevron.right", enabled: canGoForward, action: onForward)
        }
        .padding(6)
        .background(Color.appFill, in: Capsule())
        .rise(isShown, y: 14, delay: 0)
    }

    private var periodSub: String {
        result.isCurrent ? L("Periode gajian · hari ke-%lld dari %lld", result.elapsedDays, result.totalDays) : L("Periode gajian · selesai")
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(Color.appText)
                .frame(width: 36, height: 36)
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.25)
        .accessibilityLabel(symbol == "chevron.left" ? L("Periode sebelumnya") : L("Periode berikutnya"))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach([30.0, 48, 22, 58], id: \.self) { h in
                    RoundedRectangle(cornerRadius: 4).fill(Color.appBorder.opacity(0.6)).frame(width: 18, height: h)
                }
            }
            .frame(height: 64, alignment: .bottom)
            Rectangle().fill(Color.appBorder).frame(width: 124, height: 1.5)
            Text("Belum ada transaksi").font(.app(20, weight: .semibold))
            Text(L("Pemasukan dan pengeluaran yang kamu catat di %@ akan muncul di sini.", result.label))
                .font(.app(15)).foregroundStyle(Color.appTextSecondary).multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            Button(action: onAdd) {
                Text("Catat transaksi").font(.app(16, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 28).frame(height: 48).background(Color.appPrimary, in: Capsule())
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 72)
        .rise(isShown, y: 14, delay: 0.06)
    }

    // MARK: A. Ringkasan

    private var summaryCard: some View {
        let s = result.summary
        return card(L("Ringkasan periode")) {
            VStack(alignment: .leading, spacing: 0) {
                label(L("Net periode ini")).font(.app(13))
                HStack(alignment: .top, spacing: 4) {
                    Text((s.net < 0 ? "−" : "") + "Rp").font(.app(15)).foregroundStyle(Color.appTextSecondary).padding(.top, heroSize * 0.12)
                    Text(isVisible ? s.net.formattedAsDigits() : hiddenAmount)
                        .font(.app(heroSize, weight: .light)).tracking(-1.2).monospacedDigit()
                        .foregroundStyle(s.net < 0 ? Color.appError : Color.appText)
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
            }
            Sparkline(values: s.remaining, animated: animated, shown: isShown).frame(height: 44)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], alignment: .leading, spacing: 14) {
                stat(L("Masuk"), money.full(s.income), color: .appPrimary)
                stat(L("Keluar"), money.full(s.expense))
                stat(L("Rasio tabungan"), s.savingsRate.map { StatistikMoney.percent($0) } ?? "—",
                     color: (s.savingsRate ?? 0) < 0 ? .appError : .appPrimary)
                stat(L("Transaksi"), "\(s.transactions)")
                stat(L("Rata-rata per hari"), money.full(s.perDay))
                stat(L("Rata-rata per transaksi"), s.perTransaction.map { money.full($0) } ?? "—")
            }
            Divider().overlay(Color.appDivider)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    label(L("Proyeksi pengeluaran akhir periode"))
                    Text(projectionNote(s.projectionNote)).font(.app(12)).foregroundStyle(Color.appTextTertiary)
                }
                Spacer(minLength: 12)
                Text(s.projection.map { money.full($0) } ?? "—").font(.app(17, weight: .medium)).monospacedDigit().lineLimit(1)
            }
        }
    }

    private func projectionNote(_ note: PeriodStatistics.ProjectionNote) -> String {
        switch note {
        case .fromAverage(let perDay): L("Dari rata-rata %@/hari", money.full(perDay))
        case .needsHistory: L("Butuh minimal 1 periode data")
        case .finished: L("Periode sudah selesai")
        }
    }

    // MARK: Total aset

    /// What the wallets hold today, split by wallet type. It is the balance now, whichever period is open.
    private func assetsCard(_ assets: PeriodStatistics.Assets) -> some View {
        let shades: [Double] = [1, 0.7, 0.45, 0.25]
        let topShare = assets.rows.map(\.share).max() ?? 1
        return card(L("Total aset"), trailing: L("Per hari ini")) {
            VStack(alignment: .leading, spacing: 0) {
                label(L("Kas dan investasi")).font(.app(13))
                HStack(alignment: .top, spacing: 4) {
                    Text("Rp").font(.app(15)).foregroundStyle(Color.appTextSecondary).padding(.top, heroSize * 0.12)
                    Text(isVisible ? assets.total.formattedAsDigits() : hiddenAmount)
                        .font(.app(heroSize, weight: .light)).tracking(-1.2).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                stat(L("Kas"), money.full(assets.cash)).frame(maxWidth: .infinity, alignment: .leading)
                stat(L("Investasi"), money.full(assets.invested)).frame(maxWidth: .infinity, alignment: .leading)
            }
            InvestmentChartView(seriesFor: { assets.history.series(range: $0) }, isBalanceVisible: isVisible,
                                valueLabel: L("Total aset"), capitalLabel: L("Investasi"),
                                emptyText: L("Grafik muncul setelah ada catatan di 2 hari yang berbeda."), showsDots: false)
            if let investment = assets.investment {
                VStack(spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        label(L("Untung/rugi investasi")).font(.app(14))
                        Spacer(minLength: 8)
                        Text(gainText(investment)).font(.app(15, weight: .semibold)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .foregroundStyle(investment.gain > 0 ? Color.appPrimary : investment.gain < 0 ? Color.appError : Color.appTextSecondary)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        label(L("Modal disetor")).font(.app(14))
                        Spacer(minLength: 8)
                        Text(money.full(investment.capital)).font(.app(14)).monospacedDigit()
                    }
                    HStack(alignment: .firstTextBaseline) {
                        label(L("Terakhir diperbarui")).font(.app(14))
                        Spacer(minLength: 8)
                        Text(investment.lastUpdated.map { StatistikMoney.dayLabel($0) } ?? "—").font(.app(14))
                    }
                }
                .padding(14)
                .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 12))
            }
            Divider().overlay(Color.appDivider)
            VStack(spacing: 12) {
                ForEach(assets.rows.indices, id: \.self) { index in
                    let row = assets.rows[index]
                    let color = Color.appText.opacity(shades[min(index, 3)])
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            HStack(spacing: 8) {
                                Circle().fill(color).frame(width: 8, height: 8)
                                Text(row.name).lineLimit(1)
                                Text("\(row.count)").font(.app(12)).foregroundStyle(Color.appTextTertiary)
                            }
                            Spacer(minLength: 8)
                            Text(money.full(row.amount)).monospacedDigit()
                        }
                        .font(.app(14))
                        ProgressTrack(fraction: topShare > 0 ? row.share / topShare : 0, color: color, shown: isShown)
                        label(L("%@ dari total aset", StatistikMoney.percent(row.share))).monospacedDigit()
                    }
                }
            }
            label(L("Saldo dompet aktif hari ini. Kartu kredit tidak dihitung."))
        }
    }

    private func gainText(_ investment: PeriodStatistics.InvestmentTotals) -> String {
        guard isVisible else { return "••••" }
        let sign = investment.gain > 0 ? "+" : investment.gain < 0 ? "−" : ""
        let rupiah = sign + abs(investment.gain).formattedAsCurrency()
        return investment.percent.map { rupiah + " · " + InvestmentSummary.percentText($0, signed: true) } ?? rupiah
    }

    // MARK: B. Kalender

    private var calendarCard: some View {
        let c = result.calendar
        return card(L("Kalender pengeluaran"), trailing: result.label) {
            SpendingCalendarGrid(calendar: c, money: money)
            Divider().overlay(Color.appDivider)
            HStack(alignment: .top, spacing: 12) {
                stat(L("Total periode"), money.full(c.total), bold: true).frame(maxWidth: .infinity, alignment: .leading)
                stat(L("Hari terboros"), c.peakDate.map { StatistikMoney.dayLabel($0) } ?? "—", sub: c.peakDate == nil ? nil : money.full(c.peakAmount), bold: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                stat(L("Tanpa pengeluaran"), L("%lld hari", c.zeroDays), bold: true).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: C. Tren

    private var trendCard: some View {
        let t = result.trend
        return card(L("Tren %lld periode", t.points.count)) {
            HStack(spacing: 10) {
                legend(L("Masuk"), color: .appPrimary)
                legend(L("Keluar"), color: .appTextTertiary)
                HStack(spacing: 4) { Rectangle().fill(Color.appText).frame(width: 10, height: 2); label(L("Net")).font(.app(11)) }
            }
            TrendChart(points: t.points, shown: isShown, animated: animated)
            Divider().overlay(Color.appDivider)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], alignment: .leading, spacing: 12) {
                if t.points.count > 1, let last = t.points.last {
                    stat(L("Keluar vs periode lalu"), StatistikMoney.signedPercent(t.expenseChange), color: (t.expenseChange ?? 0) > 0 ? .appWarning : .appPrimary,
                         sub: money.full(last.expense), bold: true)
                    stat(L("Net vs periode lalu"), StatistikMoney.signedPercent(t.netChange), color: (t.netChange ?? 0) >= 0 ? .appPrimary : .appWarning,
                         sub: money.full(last.net), bold: true)
                    stat(L("Rata-rata Masuk"), money.full(t.averageIncome), sub: L("%lld periode", t.points.count), bold: true)
                    stat(L("Rata-rata Keluar"), money.full(t.averageExpense), sub: L("%lld periode", t.points.count), bold: true)
                } else {
                    stat(L("Baru satu periode"), "—", color: .appTextSecondary, sub: L("Persentase muncul periode depan"), bold: true)
                    stat(L("Keluar sejauh ini"), money.full(result.summary.expense), sub: L("%lld hari", result.elapsedDays), bold: true)
                }
            }
        }
    }

    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8); label(title).font(.app(11)) }
    }

    // MARK: D. Pengeluaran per kategori

    private var expenseCard: some View {
        let slices = result.expenseSlices
        let shades: [Double] = [1, 0.7, 0.45, 0.25, 0.12]
        let topShare = slices.first?.share ?? 1
        return card(L("Pengeluaran per kategori")) {
            if slices.isEmpty {
                emptyLine(L("Belum ada pengeluaran di periode ini."))
            } else {
                HStack(spacing: 16) {
                    Donut(shares: slices.map(\.share), colors: slices.indices.map { Color.appText.opacity(shades[min($0, 4)]) }, size: 104, shown: isShown)
                        .overlay {
                            VStack(spacing: 0) {
                                label(L("Keluar")).font(.app(11))
                                Text(money.short(result.summary.expense)).font(.app(15, weight: .medium)).monospacedDigit()
                            }
                        }
                    (Text(L("Terbesar: ")) + Text(slices[0].name).fontWeight(.semibold).foregroundStyle(Color.appText)
                        + Text(" · " + L("%@ dari total", StatistikMoney.percent(slices[0].share))))
                        .font(.app(13)).foregroundStyle(Color.appTextSecondary)
                }
                VStack(spacing: 12) {
                    ForEach(slices.indices, id: \.self) { index in
                        let slice = slices[index]
                        let color = Color.appText.opacity(shades[min(index, 4)])
                        VStack(spacing: 6) {
                            HStack {
                                HStack(spacing: 8) { Circle().fill(color).frame(width: 8, height: 8); Text(slice.name).lineLimit(1) }
                                Spacer(minLength: 8)
                                Text(money.full(slice.amount)).monospacedDigit()
                            }
                            .font(.app(14))
                            HStack(spacing: 8) {
                                ProgressTrack(fraction: topShare > 0 ? slice.share / topShare : 0, color: color, shown: isShown)
                                label(StatistikMoney.percent(slice.share)).frame(width: 34, alignment: .trailing)
                                changeLabel(slice.change).frame(width: 56, alignment: .trailing)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func changeLabel(_ change: Double?) -> some View {
        if let change {
            if abs(change) < 0.01 {
                label(L("Sama"))
            } else {
                HStack(spacing: 2) {
                    Image(systemName: change > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill").font(.system(size: 7))
                    Text("\(Int((abs(change) * 100).rounded()))%")
                }
                .font(.app(12)).foregroundStyle(change > 0 ? Color.appWarning : Color.appPrimary).lineLimit(1)
            }
        } else {
            Color.clear.frame(height: 1)
        }
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text).font(.app(14)).foregroundStyle(Color.appTextSecondary)
    }

    // MARK: E. Pemasukan per kategori

    private var incomeCard: some View {
        let slices = result.incomeSlices
        let shades: [Double] = [1, 0.7, 0.45, 0.28]
        return card(L("Pemasukan per kategori")) {
            if slices.isEmpty {
                emptyLine(L("Belum ada pemasukan di periode ini."))
            } else {
                HStack(spacing: 16) {
                    Donut(shares: slices.map(\.share), colors: slices.indices.map { Color.appPrimary.opacity(shades[min($0, 3)]) }, size: 88, shown: isShown)
                        .overlay {
                            VStack(spacing: 0) {
                                label(L("Masuk")).font(.app(11))
                                Text(money.short(result.summary.income)).font(.app(14, weight: .medium)).monospacedDigit()
                            }
                        }
                    VStack(spacing: 10) {
                        ForEach(slices.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 0) {
                                HStack {
                                    HStack(spacing: 8) {
                                        Circle().fill(Color.appPrimary.opacity(shades[min(index, 3)])).frame(width: 8, height: 8)
                                        Text(slices[index].name).lineLimit(1)
                                    }
                                    Spacer(minLength: 6)
                                    Text(money.full(slices[index].amount)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                                }
                                .font(.app(14))
                                label(StatistikMoney.percent(slices[index].share)).padding(.leading, 16)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: F. Dompet

    private var walletCard: some View {
        let wallets = result.wallets
        let shades: [Double] = [1, 0.7, 0.45, 0.25, 0.12]
        let topShare = wallets.map(\.share).max() ?? 1
        return card(L("Komposisi dompet")) {
            if wallets.isEmpty {
                emptyLine(L("Belum ada transaksi di dompet mana pun."))
            } else {
                HStack(spacing: 16) {
                    Donut(shares: wallets.map(\.share), colors: wallets.indices.map { Color.appText.opacity(shades[min($0, 4)]) }, size: 88, shown: isShown)
                    if let used = result.mostUsedWallet {
                        VStack(alignment: .leading, spacing: 2) {
                            label(L("Paling sering dipakai"))
                            Text(used.name).font(.app(17, weight: .semibold)).lineLimit(1)
                            label(L("%lld transaksi", used.count))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                VStack(spacing: 12) {
                    ForEach(wallets.indices, id: \.self) { index in
                        let wallet = wallets[index]
                        let color = Color.appText.opacity(shades[min(index, 4)])
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                HStack(spacing: 8) { Circle().fill(color).frame(width: 8, height: 8); Text(wallet.name).lineLimit(1) }
                                Spacer(minLength: 8)
                                Text(money.full(wallet.expense)).monospacedDigit()
                            }
                            .font(.app(14))
                            ProgressTrack(fraction: topShare > 0 ? wallet.share / topShare : 0, color: color, shown: isShown)
                            label(L("Masuk %@ · %@ dari pengeluaran", money.full(wallet.income), StatistikMoney.percent(wallet.share))).monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    // MARK: G. Pola waktu

    private var timeCard: some View {
        let t = result.time
        let top = t.weekdays.map(\.average).max() ?? 0
        return card(L("Pola waktu")) {
            if t.peak == nil {
                emptyLine(L("Belum ada pengeluaran di periode ini."))
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(t.weekdays.indices, id: \.self) { index in
                        let isPeak = t.peak == index
                        VStack(spacing: 6) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isPeak ? Color.appText : Color.chartBar)
                                .frame(height: max(4, 100 * t.weekdays[index].average / max(top, 1)))
                                .scaleEffect(y: isShown ? 1 : 0, anchor: .bottom)
                                .animation(animated ? .settle(0.6) : nil, value: isShown)
                            Text(StatistikMoney.weekdays[index].short).font(.app(11, weight: isPeak ? .bold : .regular))
                                .foregroundStyle(isPeak ? Color.appText : Color.appTextSecondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 132)
                if let peak = t.peak {
                    (Text(L("Paling boros: ")) + Text(StatistikMoney.weekdays[peak].full).fontWeight(.semibold).foregroundStyle(Color.appText)
                        + Text(" · " + L("%@ rata-rata", money.full(t.weekdays[peak].average))))
                        .font(.app(13)).foregroundStyle(Color.appTextSecondary)
                }
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        label(L("3 hari puncak"))
                        ForEach(t.topDays.indices, id: \.self) { index in
                            HStack {
                                Text(StatistikMoney.dayLabel(t.topDays[index].date))
                                Spacer(minLength: 6)
                                Text(money.full(t.topDays[index].amount)).fontWeight(.semibold)
                            }
                            .font(.app(13)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        label(L("Hemat beruntun"))
                        Text("\(t.longestZeroStreak)").font(.app(28, weight: .light)).tracking(-0.6)
                        label(L("hari tanpa pengeluaran"))
                    }
                    .padding(12).frame(width: 124, alignment: .leading)
                    .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: H. Budget

    private var budgetCard: some View {
        card(L("Budget")) {
            if result.hasBudget {
                VStack(spacing: 14) {
                    ForEach(result.budgets.indices, id: \.self) { index in
                        let row = result.budgets[index]
                        let color: Color = row.ratio >= 1 ? .appError : row.ratio >= 0.8 ? .appWarning : .appPrimary
                        let filled = min(30, Int((row.ratio * 30).rounded()))
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(row.name).font(.app(14)).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(row.ratio >= 1 ? L("Lewat %@", money.full(row.spent - row.amount))
                                     : row.ratio >= 0.8 ? L("Hampir habis") : L("Sisa %@", money.full(row.amount - row.spent)))
                                    .font(.app(12)).monospacedDigit().foregroundStyle(row.ratio >= 0.8 ? color : Color.appTextSecondary)
                            }
                            HStack(spacing: 2) {
                                ForEach(0..<30, id: \.self) { tick in
                                    RoundedRectangle(cornerRadius: 1).fill(tick < filled ? color : Color.chartBar)
                                }
                            }
                            .frame(height: 12)
                            HStack {
                                label(L("%@ dari %@", money.full(row.spent), money.full(row.amount))).monospacedDigit()
                                Spacer()
                                label(StatistikMoney.percent(row.ratio))
                            }
                        }
                    }
                    Divider().overlay(Color.appDivider)
                    HStack(alignment: .firstTextBaseline) {
                        label(L("Sisa budget periode")).font(.app(13))
                        Spacer()
                        Text(money.full(result.budgetRemaining)).font(.app(20, weight: .light)).monospacedDigit().foregroundStyle(Color.appPrimary)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    emptyLine(L("Belum ada budget aktif. Atur batas per kategori supaya pengeluaranmu terpantau."))
                    Button(action: onOpenBudget) {
                        Text("Buat budget").font(.app(15, weight: .semibold)).foregroundStyle(Color.appPrimary)
                            .padding(.horizontal, 22).frame(height: 40).background(Color.appPrimary.opacity(0.12), in: Capsule())
                    }
                }
            }
        }
    }

    // MARK: I. Sorotan

    private var highlightsCard: some View {
        let h = result.highlights
        return card(L("Sorotan")) {
            VStack(alignment: .leading, spacing: 10) {
                label(L("Transaksi terbesar"))
                if h.biggest.isEmpty {
                    emptyLine(L("Belum ada pengeluaran di periode ini."))
                }
                ForEach(h.biggest.indices, id: \.self) { index in
                    HStack(spacing: 12) {
                        Text("\(index + 1)").font(.app(13)).foregroundStyle(Color.appTextTertiary).monospacedDigit().frame(width: 22, alignment: .leading)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(h.biggest[index].name).font(.app(14)).lineLimit(1)
                            label(StatistikMoney.dayLabel(h.biggest[index].date))
                        }
                        Spacer(minLength: 8)
                        Text(money.full(h.biggest[index].amount)).font(.app(14, weight: .medium)).monospacedDigit()
                    }
                }
            }
            if let frequent = h.frequent {
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        label(L("Kategori paling sering"))
                        Text(frequent.name).font(.app(15, weight: .semibold)).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(L("%lld transaksi", frequent.count)).font(.app(13)).foregroundStyle(Color.appTextSecondary)
                }
                .padding(12)
                .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 12))
            }
            Divider().overlay(Color.appDivider)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    label(L("Dibanding periode sama bulan lalu"))
                    Spacer(minLength: 8)
                    if let change = h.comparison?.change {
                        HStack(spacing: 2) {
                            Image(systemName: change > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill").font(.system(size: 8))
                            Text("\(Int((abs(change) * 100).rounded()))%")
                        }
                        .font(.app(13, weight: .semibold)).foregroundStyle(change > 0 ? Color.appWarning : Color.appPrimary)
                    }
                }
                if let comparison = h.comparison {
                    let longest = max(comparison.now, comparison.previous, 1)
                    compareBar(L("Periode ini"), money.full(comparison.now), fraction: comparison.now / longest, color: .appText, strong: true)
                    compareBar(comparison.label, money.full(comparison.previous), fraction: comparison.previous / longest, color: .appTextTertiary, strong: false)
                } else {
                    emptyLine(L("Perbandingan muncul setelah satu periode penuh tercatat."))
                }
            }
        }
    }

    private func compareBar(_ title: String, _ value: String, fraction: Double, color: Color, strong: Bool) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(title); Spacer(minLength: 8); Text(value).monospacedDigit()
            }
            .font(.app(13)).foregroundStyle(strong ? Color.appText : Color.appTextSecondary)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.chartBar)
                    Capsule().fill(color).frame(width: max(4, proxy.size.width * fraction))
                        .scaleEffect(x: isShown ? 1 : 0, anchor: .leading)
                        .animation(animated ? .settle(0.7) : nil, value: isShown)
                }
            }
            .frame(height: 10)
        }
    }
}

// MARK: - Charts

private extension Color {
    /// The empty part of a bar: pale in light mode, dark grey in dark mode.
    static let chartBar = Color(light: 0xD9D9DE, dark: 0x3A3A3C)
}

/// Remaining money across the days of the period: a line with a soft area under it.
private struct Sparkline: View {
    let values: [Double]
    let animated: Bool
    let shown: Bool

    var body: some View {
        GeometryReader { proxy in
            let points = self.points(in: proxy.size)
            ZStack {
                if points.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: proxy.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: points.last!.x, y: proxy.size.height))
                        path.closeSubpath()
                    }
                    .fill(Color.appPrimary.opacity(0.12))
                    .opacity(shown ? 1 : 0)
                    .animation(animated ? .easeOut(duration: 0.8).delay(0.2) : nil, value: shown)
                    Path { path in
                        path.move(to: points[0])
                        points.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .stroke(Color.appPrimary, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                if let last = points.last {
                    Circle().fill(Color.appPrimary).frame(width: 7, height: 7).position(last)
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard let low = values.min(), let high = values.max() else { return [] }
        let span = high - low > 0 ? high - low : 1
        let step = values.count > 1 ? size.width / CGFloat(values.count - 1) : 0
        return values.enumerated().map { index, value in
            CGPoint(x: step * CGFloat(index), y: size.height - 4 - CGFloat((value - low) / span) * (size.height - 8))
        }
    }
}

/// Grouped bars for money in and out, with the Net as a line over them.
private struct TrendChart: View {
    let points: [PeriodStatistics.TrendPoint]
    let shown: Bool
    let animated: Bool
    private let plotHeight: CGFloat = 104

    var body: some View {
        let peak = max(points.map { max($0.income, $0.expense) }.max() ?? 1, 1) * 1.08
        VStack(spacing: 6) {
            GeometryReader { proxy in
                let slot = proxy.size.width / CGFloat(max(points.count, 1))
                ZStack(alignment: .bottomLeading) {
                    Rectangle().fill(Color.appBorder).frame(height: 1).frame(maxHeight: .infinity, alignment: .bottom)
                    ForEach(points.indices, id: \.self) { index in
                        HStack(alignment: .bottom, spacing: 4) {
                            bar(points[index].income, peak: peak, color: .appPrimary, delay: 0)
                            bar(points[index].expense, peak: peak, color: .appTextTertiary, delay: 0.06)
                        }
                        .frame(width: slot)
                        .offset(x: slot * CGFloat(index))
                    }
                    Path { path in
                        for (index, point) in points.enumerated() {
                            let location = CGPoint(x: slot * (CGFloat(index) + 0.5), y: proxy.size.height - 1 - CGFloat(max(point.net, 0) / peak) * plotHeight)
                            index == 0 ? path.move(to: location) : path.addLine(to: location)
                        }
                    }
                    .stroke(Color.appText, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    ForEach(points.indices, id: \.self) { index in
                        Circle().fill(Color.appText).overlay(Circle().stroke(Color.appFill, lineWidth: 2)).frame(width: 8, height: 8)
                            .position(x: slot * (CGFloat(index) + 0.5), y: proxy.size.height - 1 - CGFloat(max(points[index].net, 0) / peak) * plotHeight)
                    }
                }
            }
            .frame(height: 120)
            HStack(spacing: 0) {
                ForEach(points.indices, id: \.self) { index in
                    Text(points[index].label + (points[index].isCurrent ? "*" : "")).font(.app(11)).foregroundStyle(Color.appTextSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func bar(_ value: Double, peak: Double, color: Color, delay: Double) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(color)
            .frame(width: 18, height: max(2, CGFloat(value / peak) * plotHeight))
            .scaleEffect(y: shown ? 1 : 0, anchor: .bottom)
            .animation(animated ? .settle(0.6).delay(delay) : nil, value: shown)
    }
}

/// A ring cut into shares, with a hair of gap between them.
private struct Donut: View {
    let shares: [Double]
    let colors: [Color]
    let size: CGFloat
    let shown: Bool

    var body: some View {
        let width = size * 0.14
        ZStack {
            Circle().stroke(Color.chartBar.opacity(0.25), lineWidth: width)
            ForEach(shares.indices, id: \.self) { index in
                let start = shares[..<index].reduce(0, +)
                Circle()
                    .trim(from: start, to: max(start, start + shares[index] - 0.006))
                    .stroke(colors[index], style: StrokeStyle(lineWidth: width, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(width / 2)
        .frame(width: size, height: size)
        .opacity(shown ? 1 : 0)
        .animation(.easeOut(duration: 0.6), value: shown)
    }
}

/// A horizontal bar that grows from the left.
private struct ProgressTrack: View {
    let fraction: Double
    let color: Color
    let shown: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.chartBar)
                Capsule().fill(color).frame(width: max(4, proxy.size.width * min(max(fraction, 0), 1)))
                    .scaleEffect(x: shown ? 1 : 0, anchor: .leading)
                    .animation(.settle(0.7), value: shown)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Formatting

/// Rupiah and percentages for the page, with the privacy switch applied: amounts become dots, percentages stay.
struct StatistikMoney {
    let isVisible: Bool

    func full(_ value: Double) -> String {
        isVisible ? (value < 0 ? "−Rp" : "Rp") + value.formattedAsDigits() : "Rp" + hiddenAmount
    }

    /// "12 jt", "45 rb".
    func short(_ value: Double) -> String { isVisible ? value.abbreviatedRupiah() : "Rp••••" }

    /// A calendar cell: "1,5jt" or "120k"; nothing while amounts are hidden (the cell then shows its heat only).
    func cell(_ value: Double) -> String {
        guard isVisible else { return "" }
        return value >= 1_000_000 ? String(format: "%.1f", value / 1_000_000).replacingOccurrences(of: ".", with: ",") + "jt"
                                   : "\(Int((value / 1000).rounded()))k"
    }

    static func percent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))%" }

    static func signedPercent(_ fraction: Double?) -> String {
        guard let fraction else { return "—" }
        let value = Int((fraction * 100).rounded())
        return (value > 0 ? "+" : value < 0 ? "−" : "") + "\(abs(value))%"
    }

    /// Monday first, like the calendar.
    static let weekdays: [(short: String, full: String)] = [
        (Lx("Sen", en: "Mon"), Lx("Senin", en: "Monday")), (Lx("Sel", en: "Tue"), Lx("Selasa", en: "Tuesday")),
        (Lx("Rab", en: "Wed"), Lx("Rabu", en: "Wednesday")), (Lx("Kam", en: "Thu"), Lx("Kamis", en: "Thursday")),
        (Lx("Jum", en: "Fri"), Lx("Jumat", en: "Friday")), (Lx("Sab", en: "Sat"), Lx("Sabtu", en: "Saturday")),
        (Lx("Min", en: "Sun"), Lx("Minggu", en: "Sunday")),
    ]

    /// "Jum, 2 Okt".
    static func dayLabel(_ date: Date) -> String {
        let format = DateFormatter()
        format.locale = AppLanguage.locale
        format.dateFormat = "EEE, d MMM"
        return format.string(from: date)
    }
}
