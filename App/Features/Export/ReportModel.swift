import Foundation

/// Everything the PDF report (design "Laporan Keuangan v3", Fitur 8 US3) shows, worked out before drawing:
/// one payday period, its flow, categories, budgets and wallets. Pure, so the numbers and the privacy mode can be
/// tested without drawing anything. The analysis and the three suggestions (Fitur 7) are worked out in PeriodAnalysis and carried here.
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
    /// The free preview: same page, with the analysis detail hidden.
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

    // MARK: Analysis

    /// The automatic analysis and the three suggestions (Fitur 7); nil when nothing was recorded in the period.
    let analysis: PeriodAnalysis.Analysis?
    /// Free preview: the page keeps the headline, the score and the finding titles; the rest is hidden, not drawn.
    var hidesAnalysisDetail: Bool { isPreview }

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

    /// The headline under the period: net and what is left of it, or nothing to say yet.
    var headline: [Run] {
        guard income > 0 || expense > 0 else { return [Run(text: L("Belum ada pemasukan atau pengeluaran di periode ini."), tone: .neutral)] }
        return PeriodAnalysis.headlineRuns(income: income, expense: expense, isPrivate: isPrivate)
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

        let analysis = PeriodAnalysis.make(analysisInput(
            interval: interval, cycle: cycle, transactions: transactions, accounts: accounts, categories: categories,
            lines: lines, topCategory: all.first?.name, isPrivate: isPrivate, now: now))

        return ReportModel(
            userName: userName, createdAt: now, interval: interval, periodKind: periodKind(cycle),
            isPrivate: isPrivate, isPreview: isPreview,
            income: rows.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }, expense: totalExpense,
            slices: slices, allSlices: all, budgets: lines, wallets: wallets, hasEstimate: period?.hasEstimate ?? false,
            analysis: analysis)
    }

    /// Built-in categories that can wait; an account on the older category set has none of these keys and the advice
    /// then eases off its biggest category instead.
    private static let flexibleCategoryKeys: Set<String> = ["expense_snack_coffee", "expense_groceries_household", "expense_etc"]

    /// What the analysis is worked out from: this period, up to three before it, and the score's inputs as they stood
    /// then. Balances are today's (the app keeps no balance history).
    private static func analysisInput(interval: DateInterval, cycle: PaydayCycle, transactions: [Transaction], accounts: [Account],
                                      categories: [Category], lines: [BudgetLine], topCategory: String?, isPrivate: Bool,
                                      now: Date) -> PeriodAnalysis.Input {
        let calendar = Calendar.current
        let names = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let keys = Dictionary(categories.map { ($0.id, $0.systemKey) }, uniquingKeysWith: { first, _ in first })
        let counted = transactions.filter { $0.type == .income || $0.type == .expense }
        func totals(_ range: DateInterval) -> PeriodAnalysis.Totals {
            var result = PeriodAnalysis.Totals(income: 0, expense: 0)
            for txn in counted where txn.date >= range.start && txn.date < range.end {
                if txn.type == .income {
                    result.income += txn.amount
                } else {
                    result.expense += txn.amount
                    result.categories[txn.categoryId.flatMap { names[$0] } ?? L("Tanpa kategori"), default: 0] += txn.amount
                }
            }
            return result
        }
        let first = counted.map(\.date).min()
        // A period before the first transaction has nothing to compare with.
        let previous = [1, 2, 3].map { cycle.period(offset: -$0, from: interval.start, calendar: calendar) }
            .filter { period in first.map { $0 < period.end } ?? false }.map(totals)
        let current = totals(interval)

        let bills = counted.filter { $0.type == .expense && $0.date >= interval.start && $0.date < interval.end
            && $0.categoryId.flatMap { keys[$0] } == "expense_bills_subscriptions" }
        let charges = bills.map { PeriodAnalysis.Charge(name: $0.description ?? $0.note ?? "", amount: $0.amount) }
        let flexible = Set(categories.filter { $0.systemKey.map(flexibleCategoryKeys.contains) ?? false }.map(\.name))

        let end = min(now, interval.end)
        let since = calendar.date(byAdding: .day, value: -30, to: end) ?? end
        let real = transactions.filter { $0.type != .adjustment }
        let cards = accounts.filter { $0.isActive && $0.isCreditCard }
        let cashflow = previous.isEmpty ? [current] : Array(previous.reversed())
        let health = FinancialHealth.Input(
            monthlyIncome: cashflow.map(\.income), monthlyExpense: cashflow.map(\.expense),
            liquidBalance: accounts.filter { $0.isActive && !$0.isCreditCard && $0.type != .investment }.reduce(0) { $0 + $1.balance },
            creditDebt: max(cards.reduce(0) { $0 + $1.balance }, 0),
            creditLimit: cards.reduce(0) { $0 + ($1.creditLimit ?? 0) },
            hasCreditCard: !cards.isEmpty,
            budgetTotal: lines.reduce(0) { $0 + $1.amount }, budgetSpent: lines.reduce(0) { $0 + $1.spent },
            monthProgress: interval.contains(now) ? FinancialHealth.cycleProgress(cycle, on: now, calendar: calendar) : 1,
            activeDays: Set(real.filter { $0.date >= since && $0.date < end }.map { calendar.startOfDay(for: $0.date) }).count,
            topExpenseCategory: topCategory, hasTransactions: !counted.isEmpty,
            daysOfData: real.map(\.date).min().map { calendar.dateComponents([.day], from: calendar.startOfDay(for: $0), to: end).day ?? 0 } ?? 0)
        return PeriodAnalysis.Input(current: current, previous: previous, health: health, budgets: lines, charges: charges,
                                    billsTotal: charges.reduce(0) { $0 + $1.amount }, flexibleCategories: flexible, isPrivate: isPrivate)
    }

    private static func periodKind(_ cycle: PaydayCycle) -> String {
        cycle.day == 1 ? L("Periode bulanan") : L("Periode gajian · gajian tanggal %lld", cycle.day)
    }
}
