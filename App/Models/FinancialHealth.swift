import Foundation

/// The 0–100 financial health score: up to five factors, each worth a fixed share, plus a tip for every
/// factor that is holding the score back. A factor that cannot be rated yet (no budget, no income recorded,
/// too little data) or does not apply (no credit card) is left out, and the score is worked out from the rest.
struct FinancialHealth {
    struct Input {
        /// Income and expense per payday cycle, oldest first. The last entry is the running cycle when `cyclesAreRunning`.
        var monthlyIncome: [Double]
        var monthlyExpense: [Double]
        /// Cash, bank and e-wallet balances; credit cards and investments excluded. What pays a card bill off.
        var liquidBalance: Double
        var creditDebt: Double
        /// Sum of the credit cards' limits; 0 when no card has one.
        var creditLimit: Double
        var hasCreditCard: Bool
        var budgetTotal: Double
        var budgetSpent: Double
        /// Share of the current cycle already gone, 0...1.
        var monthProgress: Double
        var topExpenseCategory: String?
        var hasTransactions: Bool
        /// Days between the first real transaction and today. The emergency fund needs `minDays` of it.
        var daysOfData: Int = FinancialHealth.minDays
        /// Card statements still owed past their due date.
        var overdueBills: [OverdueBill] = []
        /// Every wallet's balance, investments included, cards excluded: what the emergency fund counts. Falls back to `liquidBalance`.
        var totalBalance: Double? = nil
        /// What Beranda calls "Bisa dipakai"; nil when it is not known (past periods in reports), which leaves that factor out.
        var safeToSpend: Double? = nil
        /// Days left in the cycle, today counted.
        var daysLeft: Int = 1
        /// True when only the running cycle exists, so its spending is projected to a whole cycle.
        var cyclesAreRunning = false

        /// Spending in one cycle, on average over the cycles shown; the running cycle is projected.
        var averageMonthlyExpense: Double {
            if cyclesAreRunning { return (monthlyExpense.last ?? 0) / max(monthProgress, 0.2) }
            let active = zip(monthlyIncome, monthlyExpense).filter { $0 + $1 > 0 }.map(\.1)
            return active.isEmpty ? 0 : active.reduce(0, +) / Double(active.count)
        }
    }

    struct OverdueBill: Equatable {
        let cardName: String
        let amount: Double
        let daysLate: Int
    }

    enum Kind: CaseIterable {
        case spendable, cashflow, emergencyFund, debt, budget
    }

    struct Factor: Identifiable {
        let kind: Kind
        let points: Int
        let maxPoints: Int
        /// What was measured, e.g. "Saldo cukup untuk 2,4 bulan pengeluaran."
        let summary: String
        /// What to do about it; nil when the factor is fine.
        let tip: String?
        /// Not rated yet: shown with a dash and left out of the score.
        var isPending = false

        var id: Kind { kind }
        var ratio: Double { isPending ? 0 : Double(points) / Double(maxPoints) }
        var missing: Int { isPending ? 0 : maxPoints - points }

        var title: String {
            switch kind {
            case .spendable: L("Bisa dipakai")
            case .cashflow: L("Arus kas")
            case .emergencyFund: L("Dana darurat")
            case .debt: L("Utang kartu kredit")
            case .budget: L("Budget")
            }
        }

        var icon: String {
            switch kind {
            case .spendable: "checkmark.shield"
            case .cashflow: "arrow.left.arrow.right"
            case .emergencyFund: "shield"
            case .debt: "creditcard"
            case .budget: "chart.pie"
            }
        }
    }

    /// The emergency fund compares against what you spend, so it waits for this many days of history.
    static let minDays = 14

    let factors: [Factor]
    /// False until there is something to score; the UI then explains instead of showing 0.
    let isAvailable: Bool

    /// Points earned out of the points the rated factors are worth, on a 0–100 scale.
    var score: Int {
        let rated = factors.filter { !$0.isPending }
        let possible = rated.reduce(0) { $0 + $1.maxPoints }
        guard possible > 0 else { return 0 }
        return Int((Double(rated.reduce(0) { $0 + $1.points }) * 100 / Double(possible)).rounded())
    }

    /// The same cut-offs as the ring on Beranda: green from 80, amber from 60, red below.
    var label: String {
        switch score {
        case 80...: L("Sehat")
        case 60..<80: L("Cukup sehat")
        case 40..<60: L("Perlu perhatian")
        default: L("Perlu perbaikan")
        }
    }

    var isHealthy: Bool { score >= 80 }

    /// Factors with a tip, the ones costing the most points first.
    var recommendations: [Factor] {
        factors.filter { $0.tip != nil }.sorted { $0.missing > $1.missing }
    }

    /// One line on Beranda: the factor costing the most points.
    var weakest: Factor? { recommendations.first { $0.missing > 0 } }

    static let empty = FinancialHealth(factors: [], isAvailable: false)

    private init(factors: [Factor], isAvailable: Bool) {
        self.factors = factors
        self.isAvailable = isAvailable
    }

    init(_ input: Input) {
        isAvailable = input.hasTransactions
        var list: [Factor] = []
        if let safe = input.safeToSpend { list.append(Self.spendable(input, safe: safe)) }
        list.append(Self.cashflow(input))
        list.append(Self.emergencyFund(input))
        if input.hasCreditCard { list.append(Self.debt(input)) }
        list.append(Self.budget(input))
        factors = list
    }

    // MARK: Factors

    /// A factor that cannot be rated yet: shown with a dash, left out of the score, still free to carry a tip.
    private static func pending(_ kind: Kind, _ maxPoints: Int, summary: String, tip: String? = nil) -> Factor {
        Factor(kind: kind, points: 0, maxPoints: maxPoints, summary: summary, tip: tip, isPending: true)
    }

    /// Straight lines between the given (x, points) marks; flat beyond the last one.
    private static func interpolate(_ x: Double, _ marks: [(Double, Double)]) -> Int {
        guard let last = marks.last else { return 0 }
        if x >= last.0 { return Int(last.1.rounded()) }
        for (low, high) in zip(marks, marks.dropFirst()) where x < high.0 {
            let share = (x - low.0) / (high.0 - low.0)
            return Int((low.1 + (high.1 - low.1) * share).rounded())
        }
        return 0
    }

    /// "Bisa dipakai" per day against what you usually spend per day.
    private static func spendable(_ input: Input, safe: Double) -> Factor {
        guard safe > 0 else {
            return Factor(kind: .spendable, points: 0, maxPoints: 30,
                          summary: safe < 0 ? L("Saldo belum cukup menutup tagihan, kurang %@.", abs(safe).formattedAsCurrency())
                                            : L("Seluruh saldo sudah terpakai untuk tagihan."),
                          tip: L("Tunda pengeluaran yang tidak mendesak sampai saldo menutup tagihan."))
        }
        let perDay = safe / Double(max(input.daysLeft, 1))
        let daily = input.averageMonthlyExpense / 30
        guard daily > 0 else {
            return Factor(kind: .spendable, points: 30, maxPoints: 30,
                          summary: L("Bisa dipakai %@ per hari.", perDay.formattedAsCurrency()), tip: nil)
        }
        let ratio = perDay / daily
        let points = switch ratio {
        case 1...: 30
        case 0.75..<1: 25
        case 0.5..<0.75: 18
        case 0.25..<0.5: 10
        default: 5
        }
        return Factor(kind: .spendable, points: points, maxPoints: 30,
                      summary: L("Bisa dipakai %@ per hari, rata-rata belanjamu %@ per hari.", perDay.formattedAsCurrency(), daily.formattedAsCurrency()),
                      tip: points == 30 ? nil : L("Uang yang bisa dipakai per hari lebih kecil dari kebiasaan belanjamu. Tahan pengeluaran yang tidak wajib sampai akhir periode."))
    }

    /// Share of income left after spending, over the cycles shown.
    private static func cashflow(_ input: Input) -> Factor {
        let income = input.monthlyIncome.reduce(0, +)
        let expense = input.monthlyExpense.reduce(0, +)
        let months = input.monthlyIncome.count
        guard income > 0 else {
            return pending(.cashflow, 20,
                           summary: expense > 0 ? L("Belum ada pemasukan tercatat, tapi ada pengeluaran.") : L("Belum ada pemasukan tercatat."),
                           tip: L("Catat gaji dan pemasukan lain supaya kelihatan berapa yang bisa disisihkan."))
        }
        let rate = (income - expense) / income
        let points = switch rate {
        case 0.2...: 20
        case 0.1..<0.2: 16
        case 0..<0.1: 10
        case -0.1..<0: 4
        default: 0
        }
        let percent = Int((abs(rate) * 100).rounded())
        let summary = rate >= 0
            ? L("Kamu menyisihkan %lld%% dari pemasukan %lld bulan terakhir.", percent, months)
            : L("Pengeluaranmu %lld%% lebih besar dari pemasukan %lld bulan terakhir.", percent, months)
        let tip: String? = switch rate {
        case 0.2...: nil
        case 0..<0.2: L("Targetkan menyisihkan 20% pemasukan. Pindahkan ke tabungan begitu gajian, sebelum dipakai belanja.")
        default: input.topExpenseCategory.map { L("Pengeluaran melebihi pemasukan. Kurangi pos terbesarmu, %@, dan tunda belanja yang tidak mendesak.", $0) }
            ?? L("Pengeluaran melebihi pemasukan. Kurangi pos terbesarmu dan tunda belanja yang tidak mendesak.")
        }
        return Factor(kind: .cashflow, points: points, maxPoints: 20, summary: summary, tip: tip)
    }

    /// Months of spending all the wallets (investments included) cover: 1 month is 6 points, 3 are 14, 6 or more are 20.
    private static func emergencyFund(_ input: Input) -> Factor {
        guard input.daysOfData >= minDays else {
            return pending(.emergencyFund, 20, summary: L("Butuh %lld hari data supaya bisa dinilai. Tinggal %lld hari lagi.", minDays, max(0, minDays - input.daysOfData)))
        }
        let funds = max(input.totalBalance ?? input.liquidBalance, 0)
        let averageExpense = input.averageMonthlyExpense
        guard averageExpense > 0 else {
            let hasBalance = funds > 0
            return Factor(kind: .emergencyFund, points: hasBalance ? 20 : 0, maxPoints: 20,
                          summary: hasBalance ? L("Belum ada pengeluaran untuk dibandingkan.") : L("Belum ada saldo tersimpan."),
                          tip: hasBalance ? nil : L("Mulai sisihkan saldo untuk dana darurat, sekecil apa pun."))
        }
        let months = funds / averageExpense
        let points = interpolate(months, [(0, 0), (1, 6), (3, 14), (6, 20)])
        let summary = funds <= 0
            ? L("Saldomu minus, belum ada dana darurat.")
            : L("Saldo cukup untuk %@ bulan pengeluaran.", months.formatted(.number.precision(.fractionLength(1)).locale(AppLanguage.locale)))
        let target = averageExpense * 3
        let gap = target - funds
        let tip: String? = months >= 3 ? nil
            : L("Kumpulkan dana darurat minimal 3 bulan pengeluaran, sekitar %@. Sisihkan %@ per bulan untuk mencapainya dalam setahun.",
                target.abbreviatedRupiahText, (gap / 12).abbreviatedRupiahText)
        return Factor(kind: .emergencyFund, points: points, maxPoints: 20, summary: summary, tip: tip)
    }

    /// Credit card use, capped while a bill is overdue: a week late still earns 8 of 20, later earns none.
    private static func debt(_ input: Input) -> Factor {
        let usage = debtUsage(input)
        guard let worst = input.overdueBills.max(by: { $0.daysLate < $1.daysLate }) else { return usage }
        let points = min(usage.points, worst.daysLate > 7 ? 0 : 8)
        let summary = input.overdueBills.count == 1
            ? L("Tagihan %@ %@ lewat jatuh tempo %lld hari.", worst.cardName, worst.amount.formattedAsCurrency(), worst.daysLate)
            : L("%lld tagihan kartu kredit lewat jatuh tempo, total %@.", input.overdueBills.count, input.overdueBills.reduce(0) { $0 + $1.amount }.formattedAsCurrency())
        return Factor(kind: .debt, points: points, maxPoints: 20, summary: summary,
                      tip: L("Bayar tagihannya, atau catat pembayarannya kalau sudah kamu bayar, supaya skor pulih dan tidak kena bunga."))
    }

    /// Debt risk, not card use: can the cash on hand pay the card off? Heavy use alone costs nothing
    /// (someone who pays in full every month is fine); it only earns a gentle tip.
    private static func debtUsage(_ input: Input) -> Factor {
        guard input.hasCreditCard, input.creditDebt > 0 else {
            return Factor(kind: .debt, points: 20, maxPoints: 20,
                          summary: input.hasCreditCard ? L("Tagihan kartu kreditmu sudah lunas.") : L("Tidak ada utang kartu kredit."),
                          tip: nil)
        }
        let coverage = max(input.liquidBalance, 0) / input.creditDebt
        let points = coverage >= 1 ? 20 : coverage >= 0.5 ? 15 : 8
        let status = coverage >= 1 ? L("kas cukup untuk melunasi")
            : coverage >= 0.5 ? L("kas baru cukup melunasi sebagian")
            : L("kas belum cukup untuk melunasi")

        let incomes = input.monthlyIncome.filter { $0 > 0 }
        let averageIncome = incomes.isEmpty ? 0 : incomes.reduce(0, +) / Double(incomes.count)
        let base = input.creditLimit > 0 ? input.creditLimit : averageIncome
        let use = base > 0 ? input.creditDebt / base : 1
        let percent = Int((use * 100).rounded())
        let summary = input.creditLimit > 0
            ? L("Terpakai %lld%% dari limit, %@.", percent, status)
            : L("Utang kartu kredit setara %lld%% pemasukan bulanan, %@.", percent, status)
        let tip: String? = use >= 0.8
            ? L("Pemakaian kartu tinggi. Pastikan kas cukup untuk melunasi sebelum jatuh tempo.")
            : nil
        return Factor(kind: .debt, points: points, maxPoints: 20, summary: summary, tip: tip)
    }

    /// Spending pace against the budget for the part of the cycle gone. Left out when there is no budget.
    private static func budget(_ input: Input) -> Factor {
        guard input.budgetTotal > 0 else {
            return pending(.budget, 10, summary: L("Belum ada budget bulan ini."),
                           tip: input.topExpenseCategory.map { L("Buat budget, mulai dari %@ yang paling besar pengeluarannya.", $0) }
                            ?? L("Buat budget untuk kategori pengeluaran terbesarmu."))
        }
        let used = input.budgetSpent / input.budgetTotal
        // The first days carry little signal, so the pace never expects less than a fifth.
        let pace = input.budgetSpent / (input.budgetTotal * max(input.monthProgress, 0.2))
        let points = switch (used > 1, pace) {
        case (true, _): 0
        case (false, ..<1.0001): 10
        case (false, ..<1.1): 7
        case (false, ..<1.25): 3
        default: 0
        }
        let summary = L("Terpakai %lld%% budget, %lld%% bulan sudah lewat.",
                        Int((used * 100).rounded()), Int((input.monthProgress * 100).rounded()))
        let tip: String? = points == 10 ? nil
            : used > 1 ? L("Budget bulan ini sudah terlewati. Tahan pengeluaran yang tidak wajib sampai bulan depan.")
            : L("Belanjamu lebih cepat dari jadwal. Batasi ke %@ per hari supaya cukup sampai akhir bulan.", ((input.budgetTotal - input.budgetSpent) / max(1, (1 - input.monthProgress) * 30)).abbreviatedRupiahText)
        return Factor(kind: .budget, points: points, maxPoints: 10, summary: summary, tip: tip)
    }
}

private extension Double {
    /// "Rp1,5 jt" for tips; reuses the app's short format.
    var abbreviatedRupiahText: String { "Rp" + abbreviatedRupiah() }
}

// MARK: - Payday-cycle inputs

extension FinancialHealth {
    /// Share of the payday cycle gone today (today counted), so the budget pace follows the
    /// cycle budgets run on instead of the calendar month.
    static func cycleProgress(_ cycle: PaydayCycle, on date: Date = Date(), calendar: Calendar = .current) -> Double {
        let days = cycle.days(on: date, calendar: calendar)
        return Double(days.total - days.left) / Double(max(days.total, 1))
    }

    /// Income and expense of the last three finished payday cycles, oldest first. A cycle before the
    /// first transaction is left out; with no finished cycle yet it falls back to the running one.
    static func cashflowCycles(_ transactions: [Transaction], cycle: PaydayCycle, now: Date = Date(),
                               calendar: Calendar = .current) -> (income: [Double], expense: [Double], isRunning: Bool) {
        let counted = transactions.filter { $0.type == .income || $0.type == .expense }
        let first = counted.map(\.date).min()
        var periods = [3, 2, 1].map { cycle.period(offset: -$0, from: now, calendar: calendar) }
            .filter { period in first.map { $0 < period.end } ?? false }
        let isRunning = periods.isEmpty
        if isRunning { periods = [cycle.period(containing: now, calendar: calendar)] }
        func total(_ type: Transaction.TransactionType, in period: DateInterval) -> Double {
            counted.filter { $0.type == type && $0.date >= period.start && $0.date < period.end }.reduce(0) { $0 + $1.amount }
        }
        return (periods.map { total(.income, in: $0) }, periods.map { total(.expense, in: $0) }, isRunning)
    }
}

