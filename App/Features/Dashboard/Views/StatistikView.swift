import SwiftUI

/// Statistik: one page that answers "am I doing better?". Every block has its own period and, if wanted, one other
/// period to compare with, chosen freely. Figures come from `StatistikBlocks`, worked out on the device.
struct StatistikView: View {
    /// "Buat budget": the Budget tab, with this page closed behind it.
    var onOpenBudget: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var data = ExportViewModel()
    @AppStorage("isBalanceVisible") private var isVisible = true
    @State private var periodIds: [StatBlock: String] = [:]
    @State private var compareIds: [StatBlock: String] = [:]
    @State private var pick: Pick?
    @State private var incomeTab = false
    @State private var showsAllCategories = false
    @State private var history: WealthHistory?
    @State private var showsAdd = false

    private var cycle: PaydayCycle { PaydayCycle.current }
    private var userId: String? { authViewModel.currentUser?.id }
    private var money: StatistikMoney { StatistikMoney(isVisible: isVisible) }
    @ObservedObject private var workspace = WorkspaceStore.shared
    @State private var recorderId: String?
    /// The transactions the blocks read: all of them, or only what one member recorded (K17).
    private var scoped: [Transaction] {
        guard let recorderId, workspace.showsAttribution else { return data.transactions }
        return data.transactions.filter { $0.recorderId == recorderId }
    }
    private var firstRecord: Date? { data.transactions.map(\.date).min() }

    struct Pick: Identifiable {
        let block: StatBlock
        var id: String { block.rawValue }
    }

    var body: some View {
        Group {
            if data.isReady {
                ScrollView {
                    page.padding(.bottom, 100)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
        .navigationTitle(L("Statistik"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            await data.load(userId: userId)
            history = PeriodStatistics.assets(accounts: data.accounts, transactions: data.transactions)?.history
        }
        .sheet(item: $pick) { item in
            StatPickSheet(title: item.block.title, isAssets: item.block == .assets,
                          periods: options(item.block, compare: false), selected: period(item.block).id,
                          compareOptions: item.block.allowsCompare ? options(item.block, compare: true) : nil,
                          compareSelected: compareId(item.block),
                          onPeriod: { choice in
                              withAnimation(.smooth) {
                                  periodIds[item.block] = choice.id
                                  if compareIds[item.block] == choice.id { compareIds[item.block] = nil }
                              }
                          },
                          onCompare: { choice in withAnimation(.smooth) { compareIds[item.block] = choice?.id ?? (item.block == .trend ? "" : nil) } },
                          onDone: { pick = nil })
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showsAdd) {
            if let userId {
                AddTransactionView(categories: data.categories, accounts: data.accounts, userId: userId, onSave: {})
            }
        }
    }

    // MARK: Periods

    private func options(_ block: StatBlock, compare: Bool) -> [StatPeriod] {
        let now = Date()
        if block == .assets {
            let current = cycle.period(offset: 0, from: now, calendar: .current)
            return [StatPeriod(id: "p0", title: L("Periode ini"), interval: current),
                    StatPeriod(id: "a3", title: L("3 periode terakhir"), interval: current),
                    StatPeriod(id: "a6", title: L("6 periode terakhir"), interval: current),
                    StatPeriod(id: "all", title: L("Semua periode"), interval: current)]
        }
        if block == .trend {
            let list = StatistikBlocks.singles(now: now, cycle: cycle, firstRecord: firstRecord)
            return compare ? list.filter { $0.id != period(block).id } : list
        }
        return compare ? StatistikBlocks.compareOptions(now: now, cycle: cycle, firstRecord: firstRecord, excluding: period(block).id)
                       : StatistikBlocks.periods(now: now, cycle: cycle) + StatistikBlocks.olderPeriods(now: now, cycle: cycle, firstRecord: firstRecord)
    }

    private func period(_ block: StatBlock) -> StatPeriod {
        let list = options(block, compare: false)
        return list.first { $0.id == (periodIds[block] ?? (block == .assets ? "all" : nil)) } ?? list[0]
    }

    /// Spending trend compares with the last period until the user says otherwise ("" = none chosen).
    private func compareId(_ block: StatBlock) -> String? {
        let id = compareIds[block] ?? (block == .trend ? "p1" : nil)
        return id == "" ? nil : id
    }

    private func compare(_ block: StatBlock) -> StatPeriod? {
        guard let id = compareId(block) else { return nil }
        return options(block, compare: true).first { $0.id == id }
    }

    // MARK: Page

    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            if data.transactions.isEmpty {
                emptyState
            } else {
                if workspace.showsAttribution {
                    HStack { MemberFilterMenu(members: workspace.activeMembers, selection: $recorderId); Spacer(minLength: 0) }
                        .padding(.horizontal, 24).padding(.top, 8)
                }
                section { assetsBlock }
                SectionDivider()
                section { flowBlock }
                SectionDivider()
                section { categoriesBlock }
                SectionDivider()
                section { trendBlock }
                SectionDivider()
                section { budgetBlock }
                SectionDivider()
                section { walletBlock }
                SectionDivider()
                section { habitBlock }
            }
        }
    }

    /// A block of the page: 24 at the sides and 28 above and below, like the sections of Beranda.
    private func section<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().padding(.horizontal, 24).padding(.vertical, 28).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("Belum ada transaksi").font(.app(20, weight: .semibold))
            Text("Pemasukan dan pengeluaran yang kamu catat akan muncul di sini.")
                .font(.app(15)).foregroundStyle(Color.appTextSecondary).multilineTextAlignment(.center)
            Button { showsAdd = true } label: {
                Text("Catat transaksi").font(.app(16, weight: .semibold)).foregroundStyle(Color.appBackground)
                    .padding(.horizontal, 24).frame(height: 48).background(Color.appText, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.top, 60)
    }

    // MARK: Block chrome

    /// Title and what it shows on the left, the period chip on the right. The comparison is chosen in the chip's sheet.
    private func header(_ block: StatBlock) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                SectionHeader(title: block.title)
                Text(block.subtitle).font(.app(13)).foregroundStyle(Color.appTextSecondary)
                if let other = compare(block) {
                    Text(L("vs %@", other.title)).font(.app(13, weight: .medium)).foregroundStyle(Color.appPrimary)
                }
            }
            Spacer(minLength: 0)
            Button { pick = Pick(block: block) } label: {
                HStack(spacing: 4) {
                    Text(period(block).title).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                }
                .font(.app(14)).foregroundStyle(Color.appText).padding(.leading, 14).padding(.trailing, 10).frame(height: 34)
                .background(Color.appFill, in: Capsule())
                .contentShape(Capsule())
            }
        }
        .padding(.bottom, 12)
    }

    private func label(_ text: String) -> some View { Text(text).font(.app(13)).foregroundStyle(Color.appTextSecondary) }

    private func noData(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Belum ada data untuk dibandingkan").font(.app(15))
            label(L("Belum ada transaksi di %@. Pilih periode lain.", title))
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.top, 8)
    }

    /// Spending going up is bad, income and assets going up is good.
    private func tone(_ value: Double, goodWhenUp: Bool) -> Color {
        value == 0 ? .appTextSecondary : (value > 0) == goodWhenUp ? .appPrimary : .appError
    }

    private func arrow(_ value: Double) -> String { value > 0 ? "↑" : value < 0 ? "↓" : "" }

    private func verb(_ value: Double) -> String { value > 0 ? L("naik") : value < 0 ? L("turun") : L("tetap") }

    // MARK: 1. Assets

    private var assetsBlock: some View {
        let calendar = Calendar.current
        let current = history.flatMap { StatistikBlocks.wealth(on: Date(), history: $0) }
        let format = DateFormatter(); format.locale = AppLanguage.locale; format.dateFormat = "MMM"
        var marks: [WealthArea.Mark] = []
        if let history {
            let id = period(.assets).id
            if id == "p0" {
                // one point per day of the running period
                let range = cycle.period(offset: 0, from: Date(), calendar: calendar)
                let days = max(calendar.dateComponents([.day], from: calendar.startOfDay(for: range.start), to: calendar.startOfDay(for: Date())).day ?? 0, 0)
                let day = DateFormatter(); day.locale = AppLanguage.locale; day.dateFormat = "d MMM"
                for offset in 0...days {
                    guard let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: range.start)),
                          let w = StatistikBlocks.wealth(on: date, history: history) else { continue }
                    let shown = offset == 0 || offset == days || (days >= 6 && offset % (days / 3) == 0 && days - offset >= days / 3)
                    marks.append(.init(label: shown ? (offset == days ? L("Hari ini") : day.string(from: date)) : "", total: w.total, invested: w.invested))
                }
            } else {
                // the balance at the end of each payday period, then today
                let count = id == "a3" ? 3 : id == "a6" ? 6 : 12
                for back in (1...count).reversed() {
                    let range = cycle.period(offset: -back, from: Date(), calendar: calendar)
                    if let firstRecord, range.end <= firstRecord { continue }
                    guard let end = calendar.date(byAdding: .day, value: -1, to: range.end),
                          let w = StatistikBlocks.wealth(on: end, history: history) else { continue }
                    marks.append(.init(label: format.string(from: end), total: w.total, invested: w.invested))
                }
                if let now = current { marks.append(.init(label: L("Hari ini"), total: now.total, invested: now.invested)) }
            }
        }
        return VStack(alignment: .leading, spacing: 0) {
            header(.assets)
            if let current {
                HStack(alignment: .top, spacing: 3) {
                    Text("Rp").font(.app(18)).foregroundStyle(Color.appTextSecondary).padding(.top, 8)
                    Text(isVisible ? current.total.formattedAsDigits() : hiddenAmount)
                        .font(.app(44, weight: .ultraLight)).tracking(-1.5).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                }
                .padding(.top, 6)
                if marks.count > 1 {
                    WealthArea(marks: marks).frame(height: 190).padding(.top, 16)
                }
            } else {
                label(L("Belum ada data di tanggal ini.")).padding(.top, 8)
            }
        }
    }

    private func compareBar(_ title: String, _ value: Double, top: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            label(title).lineLimit(1)
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 4).fill(color).frame(width: proxy.size.width * max(value, 0) / top)
            }
            .frame(height: 8)
            Text(money.full(value)).font(.app(14)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 2. Cash flow

    private var flowBlock: some View {
        let now = period(.flow), other = compare(.flow)
        let a = StatistikBlocks.flow(scoped, in: now.interval)
        let b = other.map { StatistikBlocks.flow(scoped, in: StatistikBlocks.comparable($0.interval, to: now.interval)) }
        let rate: (Double, Double) -> Double? = { income, expense in income > 0 ? (income - expense) / income : nil }
        return VStack(alignment: .leading, spacing: 0) {
            header(.flow)
            if let other, let b {
                if b.income == 0 && b.expense == 0 {
                    noData(other.title)
                } else {
                    let before = other.title
                    HStack(alignment: .top, spacing: 24) {
                        flowColumn(Lx("Masuk", en: "In"), a.income, b.income, before: before)
                        flowColumn(Lx("Keluar", en: "Out"), a.expense, b.expense, before: before)
                    }
                    .padding(.top, 6)
                    flowColumn(L("Net"), a.income - a.expense, b.income - b.expense, before: before, big: true).padding(.top, 16)
                    let netDelta = (a.income - a.expense) - (b.income - b.expense)
                    let spend = StatistikBlocks.change(a.expense, b.expense)
                    Text("\(arrow(netDelta)) " + L("Net %@ %@", verb(netDelta), money.full(abs(netDelta)))
                         + (spend.map { " · " + L("pengeluaran %@ %@", verb($0), StatistikMoney.percent(abs($0))) } ?? ""))
                        .font(.app(15)).foregroundStyle(tone(netDelta, goodWhenUp: true)).padding(.top, 14)
                }
            } else {
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 1) { label(Lx("Masuk", en: "In")); Text(money.full(a.income)).font(.app(20, weight: .light)).monospacedDigit() }
                    VStack(alignment: .leading, spacing: 1) { label(Lx("Keluar", en: "Out")); Text(money.full(a.expense)).font(.app(20, weight: .light)).monospacedDigit() }
                }
                .padding(.top, 6)
                label(L("Net")).padding(.top, 16)
                Text(money.full(a.income - a.expense)).font(.app(36, weight: .ultraLight)).tracking(-1).monospacedDigit()
                    .foregroundStyle((a.income - a.expense) < 0 ? Color.appError : (a.income - a.expense) > 0 ? Color.appPrimary : Color.appText).lineLimit(1).minimumScaleFactor(0.6)
                if let r = rate(a.income, a.expense) { label(L("Rasio tabungan %@", StatistikMoney.signedPercent(r))).padding(.top, 2) }
            }
        }
    }

    /// One figure of the cash flow with the compared period's figure small underneath.
    private func flowColumn(_ title: String, _ a: Double, _ b: Double, before: String, big: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            label(title)
            Text(money.full(a)).font(.app(big ? 36 : 20, weight: big ? .ultraLight : .light)).tracking(big ? -1 : 0).monospacedDigit()
                .foregroundStyle(a < 0 ? Color.appError : (big && a > 0 ? Color.appPrimary : Color.appText))
                .lineLimit(1).minimumScaleFactor(0.6)
            label(before + " " + money.full(b)).padding(.top, 2)
        }
    }

    // MARK: 3. Categories

    private var categoriesBlock: some View {
        let now = period(.categories), other = compare(.categories)
        let type: Transaction.TransactionType = incomeTab ? .income : .expense
        let a = StatistikBlocks.byCategory(scoped, categories: data.categories, type: type, in: now.interval)
        let b = other.map { StatistikBlocks.byCategory(scoped, categories: data.categories, type: type,
                                                       in: StatistikBlocks.comparable($0.interval, to: now.interval)) }
        let total = a.reduce(0) { $0 + $1.amount }
        let shown = showsAllCategories ? a : Array(a.prefix(5))
        return VStack(alignment: .leading, spacing: 0) {
            header(.categories)
            HStack(spacing: 0) {
                segment(Lx("Keluar", en: "Out"), selected: !incomeTab) { incomeTab = false }
                segment(Lx("Masuk", en: "In"), selected: incomeTab) { incomeTab = true }
            }
            .padding(2).background(Color.appFill, in: Capsule()).padding(.top, 2).padding(.bottom, 8)
            if a.isEmpty {
                label(L("Belum ada transaksi di periode ini.")).padding(.vertical, 8)
            } else {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, row in
                    let earlier = b?.first { $0.name == row.name }?.amount
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 12) {
                            Image(systemName: data.categories.first { $0.name == row.name }?.icon ?? "tag")
                                .font(.system(size: 20)).foregroundStyle(Color.appTextSecondary).frame(width: 30)
                            Text(row.name).font(.app(15)).lineLimit(1)
                            Spacer(minLength: 0)
                            Text(money.full(row.amount)).font(.app(15)).monospacedDigit()
                        }
                        GeometryReader { proxy in
                            Capsule().fill(Color.appFill)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(incomeTab ? Color.appPrimary : Color.appText)
                                        .frame(width: proxy.size.width * (a[0].amount > 0 ? row.amount / a[0].amount : 0))
                                }
                        }
                        .frame(height: 6).padding(.top, 8).padding(.bottom, 5)
                        HStack {
                            label(L("%@ dari total", StatistikMoney.percent(total > 0 ? row.amount / total : 0))).monospacedDigit()
                            Spacer()
                            if let b {
                                if let earlier, let change = StatistikBlocks.change(row.amount, earlier) {
                                    Text(StatistikMoney.signedPercent(change) + " " + L("vs %@", compare(.categories)?.title ?? ""))
                                        .font(.app(13)).foregroundStyle(tone(change, goodWhenUp: incomeTab))
                                } else if !b.isEmpty {
                                    Text(earlier == nil ? L("baru") : L("tetap")).font(.app(13)).foregroundStyle(Color.appTextSecondary)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 9)
                }
                if a.count > 5 {
                    Button { withAnimation(.smooth) { showsAllCategories.toggle() } } label: {
                        Text(showsAllCategories ? "Lihat lebih sedikit" : "Lihat semua").font(.app(15)).foregroundStyle(Color.appPrimary)
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }
                }
            }
        }
    }

    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.app(14)).foregroundStyle(selected ? Color.appBackground : Color.appTextSecondary)
                .padding(.horizontal, 16).frame(height: 32)
                .background(selected ? Color.appText : Color.clear, in: Capsule())
        }
    }

    // MARK: 4. Trend

    private var trendBlock: some View {
        let now = period(.trend), other = compare(.trend)
        let dailyA = StatistikBlocks.daily(scoped, in: now.interval)
        let elapsed = StatistikBlocks.elapsedDays(now.interval)
        let lineA = StatistikBlocks.cumulative(dailyA, through: elapsed)
        let lineB = other.map { StatistikBlocks.cumulative(StatistikBlocks.daily(scoped, in: $0.interval)) }
        let day = lineA.count
        let sameA = lineA.last ?? 0
        let sameB: Double? = lineB.flatMap { $0.isEmpty || day == 0 ? nil : $0[min(day, $0.count) - 1] }
        return VStack(alignment: .leading, spacing: 0) {
            header(.trend)
            Color.clear.frame(height: 10)
            legend(now.title, other?.title)
            TrendCurve(current: lineA, other: lineB, days: max(dailyA.count, lineB?.count ?? 0), money: money)
                .frame(height: 210).padding(.top, 12)
            if let other, let sameB, sameB > 0 {
                let change = (sameA - sameB) / sameB
                (Text(L("Kamu") + " ") + Text(L("%@ lebih %@", StatistikMoney.percent(abs(change)), change > 0 ? L("boros") : L("hemat")))
                    .foregroundColor(tone(change, goodWhenUp: false)) + Text(" " + L("dari %@ di titik yang sama (hari ke-%lld).", other.title, day)))
                    .font(.app(16)).padding(.top, 10)
            } else if other != nil {
                label(L("Belum ada data untuk dibandingkan")).padding(.top, 10)
            } else {
                Text("Pilih pembanding untuk melihat apakah kamu lebih hemat di titik yang sama.")
                    .font(.app(15)).foregroundStyle(Color.appTextSecondary).padding(.top, 10)
            }
        }
    }

    private func legend(_ now: String, _ other: String?) -> some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) { Circle().fill(Color.appText).frame(width: 8, height: 8); label(now) }
            if let other { HStack(spacing: 6) { Circle().fill(Color.appText.opacity(0.18)).frame(width: 8, height: 8); label(other) } }
        }
    }

    // MARK: 5. Budget

    private var budgetBlock: some View {
        let now = period(.budget)
        let ids = Set(data.categories.filter { $0.type == .expense }.map(\.id))
        let names = Dictionary(data.categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let rows = BudgetHistory.period(now.interval, budgets: data.historyBudgets, changes: data.amountChanges,
                                        transactions: scoped, shownCategoryIds: ids)?.rows ?? []
        let hot = rows.filter { $0.amount > 0 && $0.spent / $0.amount >= 0.7 }.sorted { $0.spent / $0.amount > $1.spent / $1.amount }.prefix(3)
        return VStack(alignment: .leading, spacing: 0) {
            header(.budget)
            if rows.isEmpty {
                Button(action: { onOpenBudget(); dismiss() }) {
                    Text("Buat budget").font(.app(15, weight: .semibold)).foregroundStyle(Color.appPrimary).frame(minHeight: 44)
                }
            } else if hot.isEmpty {
                label(L("Semua budget masih aman.")).padding(.vertical, 8)
            } else {
                ForEach(Array(hot.enumerated()), id: \.offset) { _, row in
                    let ratio = row.spent / row.amount
                    let color: Color = ratio > 1 ? .appError : .appWarning
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: data.categories.first { $0.id == row.categoryId }?.icon ?? "tag")
                                .font(.system(size: 20)).foregroundStyle(Color.appTextSecondary).frame(width: 30)
                            Text(names[row.categoryId] ?? L("Tanpa kategori")).font(.app(15)).lineLimit(1)
                            Spacer(minLength: 0)
                            Text(ratio > 1 ? L("Lewat %@", money.full(row.spent - row.amount)) : L("Sisa %@ · %@", money.full(row.amount - row.spent), StatistikMoney.percent(ratio)))
                                .font(.app(15)).monospacedDigit().foregroundStyle(color)
                        }
                        GeometryReader { proxy in
                            Capsule().fill(Color.appFill).overlay(alignment: .leading) {
                                Capsule().fill(color).frame(width: proxy.size.width * min(ratio, 1))
                            }
                        }
                        .frame(height: 8)
                    }
                    .padding(.vertical, 9)
                }
            }
        }
    }

    // MARK: 6. Wallets

    private var walletBlock: some View {
        let now = period(.wallet)
        let rows = StatistikBlocks.byWallet(scoped, accounts: data.accounts, in: now.interval)
        let total = rows.reduce(0) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: 0) {
            header(.wallet)
            if rows.isEmpty {
                label(L("Belum ada pengeluaran di periode ini.")).padding(.vertical, 8)
            }
            ForEach(Array(rows.prefix(4).enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        WalletSwatch(account: data.accounts.first { $0.name == row.name }, width: 30, height: 20)
                        Text(row.name).font(.app(15)).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(money.full(row.amount)).font(.app(15)).monospacedDigit()
                    }
                    GeometryReader { proxy in
                        Capsule().fill(Color.appFill).overlay(alignment: .leading) {
                            Capsule().fill(Color.appText).frame(width: proxy.size.width * (rows[0].amount > 0 ? row.amount / rows[0].amount : 0))
                        }
                    }
                    .frame(height: 6).padding(.top, 8).padding(.bottom, 5)
                    label(L("%@ dari pengeluaran", StatistikMoney.percent(total > 0 ? row.amount / total : 0))).monospacedDigit()
                }
                .padding(.vertical, 9)
            }
        }
    }

    // MARK: 7. Habit

    private var habitBlock: some View {
        let now = period(.habit)
        let daily = StatistikBlocks.daily(scoped, in: now.interval)
        let elapsed = StatistikBlocks.elapsedDays(now.interval)
        let spent = Array(daily.prefix(elapsed))
        let averages = StatistikBlocks.weekdayAverages(spent, start: now.interval.start)
        let peak = averages.enumerated().max { $0.element < $1.element }
        let top = max(averages.max() ?? 0, 1)
        let calendar = daily.count <= 35
            ? PeriodStatistics.spendingCalendar(daily: spent, totalDays: daily.count, startOfPeriod: Calendar.current.startOfDay(for: now.interval.start)) : nil
        return VStack(alignment: .leading, spacing: 0) {
            header(.habit)
            if let peak, peak.element > 0 {
                (Text(L("Paling boros tiap") + " ") + Text(StatistikMoney.weekdays[peak.offset].full).fontWeight(.semibold)
                 + Text(", " + L("rata-rata %@.", money.short(peak.element)))).font(.app(16)).padding(.bottom, 14)
                HStack(spacing: 8) {
                    ForEach(0..<7, id: \.self) { index in
                        VStack(spacing: 6) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(index == peak.offset ? Color.appText : Color.appBorder)
                                .frame(height: max(averages[index] / top * 72, 3))
                            label(StatistikMoney.weekdays[index].short)
                        }
                    }
                }
                .frame(height: 96)
            } else {
                label(L("Belum ada pengeluaran di periode ini.")).padding(.vertical, 8)
            }
            if let calendar {
                label(L("Pengeluaran per hari")).padding(.top, 22).padding(.bottom, 12)
                SpendingCalendarGrid(calendar: calendar, money: money)
            }
        }
    }
}

// MARK: - Blocks

enum StatBlock: String, CaseIterable {
    case assets, flow, categories, trend, budget, wallet, habit

    /// Budget, wallets and habits show one period only.
    var allowsCompare: Bool { self == .flow || self == .trend }

    var title: String {
        switch self {
        case .assets: L("Total aset")
        case .flow: L("Arus kas")
        case .categories: L("Kategori")
        case .trend: L("Tren pengeluaran")
        case .budget: L("Budget")
        case .wallet: L("Dompet")
        case .habit: L("Kebiasaan")
        }
    }

    var subtitle: String {
        switch self {
        case .assets: L("Total uang di semua dompetmu.")
        case .flow: L("Uang yang masuk dan keluar.")
        case .categories: L("Ke mana uangmu pergi.")
        case .trend: L("Apakah pengeluaranmu membaik atau memburuk.")
        case .budget: L("Budget yang hampir habis atau terlewat.")
        case .wallet: L("Dompet yang paling banyak dipakai.")
        case .habit: L("Hari dan tanggal kamu paling boros.")
        }
    }
}

/// The half sheet behind a block's chip: the period to show and, above it where it makes sense, a row that opens
/// a second sheet to pick the period to compare with.
private struct StatPickSheet: View {
    let title: String
    let isAssets: Bool
    let periods: [StatPeriod]
    let selected: String
    let compareOptions: [StatPeriod]?
    let compareSelected: String?
    let onPeriod: (StatPeriod) -> Void
    let onCompare: (StatPeriod?) -> Void
    let onDone: () -> Void
    @State private var showsCompare = false

    private var compareTitle: String {
        compareOptions?.first { $0.id == compareSelected }?.title ?? L("Tanpa pembanding")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.app(22, weight: .bold)).tracking(-0.3).padding(.top, 4).padding(.bottom, 8)
            if compareOptions != nil {
                Button { showsCompare = true } label: {
                    HStack(spacing: 6) {
                        Text("Bandingkan").font(.app(16, weight: .medium)).foregroundStyle(Color.appText)
                        Spacer()
                        Text(compareSelected == nil ? compareTitle : L("vs %@", compareTitle)).font(.app(15))
                            .foregroundStyle(compareSelected == nil ? Color.appTextSecondary : Color.appPrimary).lineLimit(1)
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
                    }
                    .frame(minHeight: 52).contentShape(Rectangle())
                }
            }
            Text(L("Periode")).font(.app(13, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
                .padding(.top, 12).padding(.bottom, 10)
            FlowLayout(spacing: 8) {
                ForEach(periods) { option in StatChip(title: option.title, isOn: option.id == selected) { onPeriod(option) } }
            }
            .padding(.bottom, 8)
        }
        .foregroundStyle(Color.appText)
        .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 12)
        .filterSheet { SmartSheetFooter(primary: L("Selesai"), onPrimary: onDone) }
        .background(Color.appBackground)
        .sheet(isPresented: $showsCompare) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Bandingkan dengan").font(.app(22, weight: .bold)).tracking(-0.3).padding(.top, 4).padding(.bottom, 12)
                FlowLayout(spacing: 8) {
                    Button { onCompare(nil); showsCompare = false } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                            Text(L("Tanpa pembanding")).font(.app(14)).lineLimit(1)
                        }
                        .foregroundStyle(compareSelected == nil ? Color.appPrimary : Color.appTextSecondary)
                        .padding(.horizontal, 14).frame(height: 36)
                        .overlay(Capsule().strokeBorder(compareSelected == nil ? Color.appPrimary : Color.appDivider, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    }
                    .accessibilityAddTraits(compareSelected == nil ? .isSelected : [])
                    ForEach(compareOptions ?? []) { option in
                        StatChip(title: option.title, isOn: option.id == compareSelected) { onCompare(option); showsCompare = false }
                    }
                }
                .padding(.bottom, 8)
            }
            .foregroundStyle(Color.appText)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 12)
            .background(Color.appBackground)
            .presentationDetents([.medium, .large])
        }
    }

}

/// A pill to pick from: dark when chosen. The dark sheet is itself 1C1C1E, so the idle fill is lighter, like the wallet picker's tiles.
private struct StatChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.app(14)).lineLimit(1)
                .foregroundStyle(isOn ? Color.appBackground : Color.appText)
                .padding(.horizontal, 14).frame(height: 36)
                .background(isOn ? Color.appText : Color(light: 0xF2F2F4, dark: 0x2C2C2E), in: Capsule())
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// What the wallets held in total over time, as one smooth area.
private struct WealthArea: View {
    struct Mark { let label: String; let total: Double; let invested: Double }
    let marks: [Mark]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { ctx, size in
            let bottom: CGFloat = 24, left: CGFloat = 44
            let plot = CGRect(x: left, y: 8, width: size.width - left, height: size.height - bottom - 8)
            let top = marks.map(\.total).max() ?? 1
            let low = marks.map(\.total).min() ?? 0
            let span = max(top - low, top * 0.04, 1)
            let raw = span * 1.5 / 4
            let mag = pow(10, floor(log10(raw)))
            let step = ([1, 2, 2.5, 5, 10].first { $0 * mag >= raw } ?? 10) * mag
            let lo = max(floor((low - span * 0.35) / step) * step, 0)
            let peak = max(ceil((top + span * 0.15) / step) * step, lo + step * 2)
            let ink = scheme == .dark ? Color.white : Color.black
            func x(_ i: Int) -> CGFloat { plot.minX + plot.width * CGFloat(i) / CGFloat(max(marks.count - 1, 1)) }
            func y(_ v: Double) -> CGFloat { plot.maxY - plot.height * CGFloat((v - lo) / (peak - lo)) }
            var tick = lo
            while tick <= peak + step / 2 {
                let gy = y(tick)
                var line = Path(); line.move(to: CGPoint(x: plot.minX, y: gy)); line.addLine(to: CGPoint(x: size.width, y: gy))
                ctx.stroke(line, with: .color(ink.opacity(0.06)), lineWidth: 1)
                ctx.draw(Text(StatistikMoney(isVisible: true).short(tick)).font(.app(11)).foregroundColor(.secondary),
                         at: CGPoint(x: plot.minX - 8, y: gy), anchor: .trailing)
                tick += step
            }
            func layer(_ values: [Double], _ color: Color, _ fill: Double) {
                let pts = values.enumerated().map { CGPoint(x: x($0.offset), y: y($0.element)) }
                let curve = TrendCurve.smooth(pts)
                var area = curve
                area.addLine(to: CGPoint(x: pts.last!.x, y: plot.maxY)); area.addLine(to: CGPoint(x: pts[0].x, y: plot.maxY)); area.closeSubpath()
                ctx.fill(area, with: .color(color.opacity(fill)))
                ctx.stroke(curve, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            layer(marks.map(\.total), .appPrimary, 0.28)
            for (i, mark) in marks.enumerated() where !mark.label.isEmpty {
                ctx.draw(Text(mark.label).font(.app(11)).foregroundColor(.secondary), at: CGPoint(x: x(i), y: size.height - 8),
                         anchor: i == 0 ? .leading : (i == marks.count - 1 ? .trailing : .center))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Grafik total aset"))
    }
}

/// Cumulative spending as soft curves: the running period filled underneath, the other one a lighter line, a dot at today.
private struct TrendCurve: View {
    let current: [Double]
    let other: [Double]?
    let days: Int
    let money: StatistikMoney
    /// False for a balance: the axis then starts near the lowest value so small moves show.
    var fromZero = true
    /// Words under the first and last point, instead of day numbers.
    var labels: (String, String)?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { ctx, size in
            let left: CGFloat = 40, bottom: CGFloat = 22, top: CGFloat = 8, right: CGFloat = 8
            let plot = CGRect(x: left, y: top, width: size.width - left - right, height: size.height - top - bottom)
            let all = current + (other ?? [])
            let hi = max(all.max() ?? 0, 1), lowest = fromZero ? 0 : (all.min() ?? 0)
            let raw = max((hi - lowest) * 1.15 / 3, 1)
            let mag = pow(10, floor(log10(raw)))
            let step = ([1, 2, 2.5, 5, 10].first { $0 * mag >= raw } ?? 10) * mag
            let lo = fromZero ? 0 : floor(lowest / step) * step - (fromZero ? 0 : 0)
            let peak = lo + step * 3
            let ink = scheme == .dark ? Color.white : Color.black
            func point(_ i: Int, _ v: Double) -> CGPoint {
                CGPoint(x: plot.minX + plot.width * CGFloat(i) / CGFloat(max(days - 1, 1)),
                        y: plot.maxY - plot.height * CGFloat((v - lo) / (peak - lo)))
            }
            for tick in 0...3 {
                let y = plot.maxY - plot.height * CGFloat(tick) / 3
                var line = Path(); line.move(to: CGPoint(x: plot.minX, y: y)); line.addLine(to: CGPoint(x: plot.maxX, y: y))
                ctx.stroke(line, with: .color(ink.opacity(0.06)), lineWidth: 1)
                ctx.draw(Text(tick == 0 && fromZero ? "0" : money.short(lo + step * Double(tick))).font(.app(11)).foregroundColor(.secondary),
                         at: CGPoint(x: plot.minX - 8, y: y), anchor: .trailing)
            }
            let marks: [(Int, String)] = labels.map { [(0, $0.0), (max(days - 1, 0), $0.1)] }
                ?? [(0, "1"), (max(days - 1, 0) / 2, "\(max(days - 1, 0) / 2 + 1)"), (max(days - 1, 0), "\(days)")]
            for (i, label) in marks {
                ctx.draw(Text(label).font(.app(11)).foregroundColor(.secondary),
                         at: CGPoint(x: point(i, 0).x, y: size.height - 8), anchor: i == 0 ? .leading : (i == days - 1 ? .trailing : .center))
            }
            if let other, other.count > 1 {
                let line = Self.smooth(other.enumerated().map { point($0.offset, $0.element) })
                var area = line
                area.addLine(to: CGPoint(x: point(other.count - 1, 0).x, y: plot.maxY)); area.addLine(to: CGPoint(x: plot.minX, y: plot.maxY)); area.closeSubpath()
                ctx.fill(area, with: .color(ink.opacity(0.05)))
                ctx.stroke(line, with: .color(ink.opacity(0.3)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            guard current.count > 1 else { return }
            let pts = current.enumerated().map { point($0.offset, $0.element) }
            let curve = Self.smooth(pts)
            var area = curve
            area.addLine(to: CGPoint(x: pts.last!.x, y: plot.maxY)); area.addLine(to: CGPoint(x: pts[0].x, y: plot.maxY)); area.closeSubpath()
            ctx.fill(area, with: .color(ink.opacity(0.14)))
            ctx.stroke(curve, with: .color(ink), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            let end = pts.last!
            ctx.fill(Path(ellipseIn: CGRect(x: end.x - 9, y: end.y - 9, width: 18, height: 18)), with: .color(ink.opacity(0.12)))
            ctx.fill(Path(ellipseIn: CGRect(x: end.x - 4.5, y: end.y - 4.5, width: 9, height: 9)), with: .color(ink))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Grafik pengeluaran kumulatif"))
    }

    /// Monotone cubic through the points: smooth, and never dips below or above them.
    fileprivate static func smooth(_ p: [CGPoint]) -> Path {
        var path = Path()
        guard p.count > 1 else { return path }
        let n = p.count
        var d = [CGFloat](repeating: 0, count: n - 1), m = [CGFloat](repeating: 0, count: n)
        for i in 0..<n - 1 { d[i] = (p[i + 1].y - p[i].y) / max(p[i + 1].x - p[i].x, 0.001) }
        m[0] = d[0]; m[n - 1] = d[n - 2]
        for i in 1..<n - 1 { m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2 }
        for i in 0..<n - 1 where d[i] == 0 { m[i] = 0; m[i + 1] = 0 }
        for i in 0..<n - 1 {
            let a = m[i] / d[i], b = m[i + 1] / d[i]
            if d[i] != 0, a * a + b * b > 9 { let t = 3 / (a * a + b * b).squareRoot(); m[i] = t * a * d[i]; m[i + 1] = t * b * d[i] }
        }
        path.move(to: p[0])
        for i in 0..<n - 1 {
            let h = p[i + 1].x - p[i].x
            path.addCurve(to: p[i + 1], control1: CGPoint(x: p[i].x + h / 3, y: p[i].y + m[i] * h / 3),
                          control2: CGPoint(x: p[i + 1].x - h / 3, y: p[i + 1].y - m[i + 1] * h / 3))
        }
        return path
    }
}

// MARK: - Formatting

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
