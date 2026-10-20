import Foundation

/// Everything the PDF report (design "Laporan Keuangan v3", Fitur 8 US3) shows, worked out before drawing:
/// one payday period, its flow, categories, budgets and wallets. Pure, so the numbers and the privacy mode can be
/// tested without drawing anything. The analysis and the three suggestions come with Analisis Periode (Fitur 7).
struct ReportModel {
    enum Tone { case neutral, positive, warning, danger }
    struct Run { let text: String; let tone: Tone }

    struct Slice {
        let name: String
        let amount: Double
        let share: Double
        /// 0...4: the report's own palette (green, navy, gold, purple, grey for "Lainnya").
        let colorIndex: Int
    }

    enum BudgetStatus { case safe, near, over }

    struct BudgetLine {
        let name: String
        let spent: Double
        let amount: Double
        let isProvisional: Bool
        var progress: Double { amount > 0 ? spent / amount : 0 }
        var status: BudgetStatus { progress >= 1 ? .over : progress >= 0.8 ? .near : .safe }
    }

    struct WalletLine {
        let name: String
        let balance: Double
        let isInvestment: Bool
    }

    // MARK: Header

    let userName: String
    let createdAt: Date
    let interval: DateInterval
    /// "Periode gajian · gajian tanggal 25"
    let periodKind: String
    /// Hides every rupiah amount, the wallets and their names.
    let isPrivate: Bool
    /// The free preview: same page, with the analysis blurred (not drawn here).
    let isPreview: Bool

    // MARK: Flow

    let income: Double
    let expense: Double
    var net: Double { income - expense }
    /// Share of income left over; nil without income.
    var savingsRate: Double? { income > 0 ? net / income : nil }

    // MARK: Lists

    /// The four biggest expense categories and "Lainnya" for the rest.
    let slices: [Slice]
    /// Every expense category, biggest first, for page 2.
    let allSlices: [Slice]
    /// Heaviest status first (Lewat, Mendekati, Aman), then the biggest budget.
    let budgets: [BudgetLine]
    let wallets: [WalletLine]
    /// Some budget amounts are estimates because their history is not complete (TC 54).
    let hasEstimate: Bool

    static let budgetsOnFirstPage = 5
    static let walletsOnFirstPage = 6

    var hasBudgets: Bool { !budgets.isEmpty }
    var showsWallets: Bool { !isPrivate }
    /// Page 2 carries the full tables when page 1 had to cut them (design "Halaman kedua").
    var needsSecondPage: Bool {
        budgets.count > Self.budgetsOnFirstPage || (showsWallets && wallets.count > Self.walletsOnFirstPage)
            || allSlices.count > 5
    }
    var pageCount: Int { needsSecondPage ? 2 : 1 }

    var totalBudget: Double { budgets.reduce(0) { $0 + $1.amount } }
    var totalSpent: Double { budgets.reduce(0) { $0 + $1.spent } }
    var totalWallets: Double { wallets.reduce(0) { $0 + $1.balance } }

    // MARK: Text

    /// "25 Sep – 24 Okt 2026" (the last day, not the day the next period starts).
    var periodTitle: String { Self.title(for: interval) }

    /// The headline under the period: surplus, deficit or nothing to say yet.
    var headline: [Run] {
        guard income > 0 || expense > 0 else { return [Run(text: L("Belum ada pemasukan atau pengeluaran di periode ini."), tone: .neutral)] }
        if net < 0 {
            return [Run(text: L("Pengeluaran melebihi pemasukan "), tone: .neutral),
                    Run(text: Self.rupiah(-net, hidden: isPrivate), tone: .danger), Run(text: ".", tone: .neutral)]
        }
        if let rate = savingsRate, net > 0 {
            return [Run(text: L("Net positif "), tone: .neutral),
                    Run(text: Self.rupiah(net, sign: true, hidden: isPrivate), tone: .positive),
                    Run(text: L(". Kamu menyisihkan "), tone: .neutral),
                    Run(text: Self.percent(rate), tone: .positive), Run(text: L(" dari pemasukan."), tone: .neutral)]
        }
        return [Run(text: L("Pemasukan dan pengeluaran seimbang."), tone: .neutral)]
    }

    /// What the footnote says: the Net formula, and that some numbers are estimates when they are.
    var footnote: String {
        var text = L(isPrivate ? "Net = pemasukan − pengeluaran. Transfer antar akun dan pembayaran kartu tidak dihitung."
                               : "Net = pemasukan − pengeluaran. Transfer antar dompet dan pembayaran kartu tidak dihitung.")
        if hasEstimate { text += " " + L("Sebagian angka pada periode ini merupakan perkiraan karena riwayat nominal budget belum lengkap.") }
        return text
    }

    /// File name with the period in it: saku-laporan-2026-09-25_2026-10-24.pdf
    var fileName: String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd"
        let last = Calendar.current.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        return "saku-laporan-\(format.string(from: interval.start))_\(format.string(from: last)).pdf"
    }

    // MARK: Format

    /// "Rp5.160.000", "+Rp5.160.000", "−Rp1.100.000"; hidden: "Rp••••••" with the sign kept.
    static func rupiah(_ value: Double, sign: Bool = false, hidden: Bool = false) -> String {
        let mark = value < 0 ? "−" : (sign && value > 0 ? "+" : "")
        if hidden { return mark + "Rp••••••" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "id_ID")
        formatter.maximumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        return mark + "Rp" + (formatter.string(from: NSNumber(value: abs(value).rounded())) ?? "0")
    }

    static func percent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))%" }

    static func title(for interval: DateInterval, calendar: Calendar = .current) -> String {
        let last = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        let sameYear = calendar.component(.year, from: interval.start) == calendar.component(.year, from: last)
        let short = DateFormatter(), full = DateFormatter()
        short.locale = AppLanguage.locale; full.locale = AppLanguage.locale
        short.dateFormat = sameYear ? "d MMM" : "d MMM yyyy"
        full.dateFormat = "d MMM yyyy"
        return "\(short.string(from: interval.start)) – \(full.string(from: last))"
    }

    // MARK: Build

    /// `period` is the budget view of the same interval (amounts as they were then, estimates marked); nil when no
    /// budget was alive in it. Transfers, card payments and balance corrections stay out of the flow, as on Beranda.
    static func make(interval: DateInterval, cycle: PaydayCycle, userName: String, transactions: [Transaction],
                     accounts: [Account], categories: [Category], period: BudgetHistoryPeriod?,
                     isPrivate: Bool, isPreview: Bool = false, now: Date = Date()) -> ReportModel {
        let rows = transactions.filter { $0.date >= interval.start && $0.date < interval.end }
        let names = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let expense = rows.filter { $0.type == .expense }
        var totals: [String: Double] = [:]
        for txn in expense { totals[txn.categoryId.flatMap { names[$0] } ?? L("Tanpa kategori"), default: 0] += txn.amount }
        let totalExpense = totals.values.reduce(0, +)
        let sorted = totals.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        func slice(_ name: String, _ amount: Double, _ index: Int) -> Slice {
            Slice(name: name, amount: amount, share: totalExpense > 0 ? amount / totalExpense : 0, colorIndex: index)
        }
        let all = sorted.enumerated().map { slice($0.element.key, $0.element.value, min($0.offset, 4)) }
        var slices = Array(all.prefix(4))
        if all.count > 4 { slices.append(slice(L("Lainnya"), all.dropFirst(4).reduce(0) { $0 + $1.amount }, 4)) }

        let lines: [BudgetLine] = (period?.rows ?? []).map {
            BudgetLine(name: names[$0.categoryId] ?? L("Tanpa kategori"), spent: $0.spent, amount: $0.amount,
                       isProvisional: $0.source == .temporary)
        }.sorted {
            let order: (BudgetStatus) -> Int = { $0 == .over ? 0 : $0 == .near ? 1 : 2 }
            return order($0.status) == order($1.status) ? $0.amount > $1.amount : order($0.status) < order($1.status)
        }

        let wallets = accounts.filter { $0.isActive }.map { WalletLine(name: $0.name, balance: $0.balance, isInvestment: $0.type == .investment) }

        return ReportModel(
            userName: userName, createdAt: now, interval: interval, periodKind: periodKind(cycle),
            isPrivate: isPrivate, isPreview: isPreview,
            income: rows.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }, expense: totalExpense,
            slices: slices, allSlices: all, budgets: lines, wallets: wallets, hasEstimate: period?.hasEstimate ?? false)
    }

    private static func periodKind(_ cycle: PaydayCycle) -> String {
        cycle.day == 1 ? L("Periode bulanan") : L("Periode gajian · gajian tanggal %lld", cycle.day)
    }
}
