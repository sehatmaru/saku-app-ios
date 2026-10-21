import Foundation

/// The 0–100 financial health score: five factors, each worth a fixed share, plus a tip
/// for every factor that is holding the score back.
struct FinancialHealth {
    struct Input {
        /// Income and expense per month, oldest first; the last entry is the current month.
        var monthlyIncome: [Double]
        var monthlyExpense: [Double]
        /// Cash, bank and e-wallet balances; credit cards excluded.
        var liquidBalance: Double
        var creditDebt: Double
        /// Sum of the credit cards' limits; 0 when no card has one.
        var creditLimit: Double
        var hasCreditCard: Bool
        var budgetTotal: Double
        var budgetSpent: Double
        /// Share of the current month already gone, 0...1.
        var monthProgress: Double
        /// Days in the last 30 with at least one transaction.
        var activeDays: Int
        var topExpenseCategory: String?
        var hasTransactions: Bool
        /// Days between the first real transaction and today. The score needs `minDays` of it.
        var daysOfData: Int = FinancialHealth.minDays
        /// Card statements still owed past their due date.
        var overdueBills: [OverdueBill] = []
    }

    struct OverdueBill: Equatable {
        let cardName: String
        let amount: Double
        let daysLate: Int
    }

    enum Kind: CaseIterable {
        case cashflow, emergencyFund, debt, budget, habit
    }

    struct Factor: Identifiable {
        let kind: Kind
        let points: Int
        let maxPoints: Int
        /// What was measured, e.g. "Saldo cukup untuk 2,4 bulan pengeluaran."
        let summary: String
        /// What to do about it; nil when the factor is fine.
        let tip: String?
        /// Needs three months of history, so it is left out of the score for now.
        var isPending = false

        var id: Kind { kind }
        var ratio: Double { isPending ? 0 : Double(points) / Double(maxPoints) }
        var missing: Int { maxPoints - points }

        var title: String {
            switch kind {
            case .cashflow: L("Arus kas")
            case .emergencyFund: L("Dana darurat")
            case .debt: L("Utang kartu kredit")
            case .budget: L("Budget")
            case .habit: L("Kebiasaan mencatat")
            }
        }

        var icon: String {
            switch kind {
            case .cashflow: "arrow.left.arrow.right"
            case .emergencyFund: "shield"
            case .debt: "creditcard"
            case .budget: "chart.pie"
            case .habit: "calendar"
            }
        }
    }

    /// Cash flow and emergency fund compare months, so they wait for this much history.
    static let minDays = 90

    let factors: [Factor]
    /// False until there is something to score; the UI then explains instead of showing 0.
    let isAvailable: Bool
    /// Some factors still wait for `minDays` of history; the score covers the others only.
    var isPartial: Bool { factors.contains(where: \.isPending) }

    /// Points earned out of the points the rated factors are worth, on a 0–100 scale.
    var score: Int {
        let rated = factors.filter { !$0.isPending }
        let possible = rated.reduce(0) { $0 + $1.maxPoints }
        guard possible > 0 else { return 0 }
        return Int((Double(rated.reduce(0) { $0 + $1.points }) * 100 / Double(possible)).rounded())
    }

    /// Still missing history for some factors (`isPartial`): the score shows, the rating does not.
    var isProvisional: Bool { isPartial }

    /// nil while provisional: a rating from partial data would mislead.
    var label: String? {
        if isProvisional { return nil }
        return switch score {
        case 80...: L("Sehat")
        case 60..<80: L("Cukup sehat")
        case 40..<60: L("Perlu perhatian")
        default: L("Perlu perbaikan")
        }
    }

    var isHealthy: Bool { !isProvisional && score >= 80 }

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
        let young = input.daysOfData < Self.minDays
        factors = [
            young ? Self.pending(.cashflow, 30, input) : Self.cashflow(input),
            young ? Self.pending(.emergencyFund, 25, input) : Self.emergencyFund(input),
            Self.debt(input),
            Self.budget(input),
            Self.habit(input),
        ]
    }

    // MARK: Factors

    private static func pending(_ kind: Kind, _ maxPoints: Int, _ input: Input) -> Factor {
        Factor(kind: kind, points: 0, maxPoints: maxPoints,
               summary: L("Butuh 3 bulan data supaya bisa dinilai. Tinggal %lld hari lagi.", max(0, minDays - input.daysOfData)),
               tip: nil, isPending: true)
    }

    /// Share of income left after spending, over the months shown.
    private static func cashflow(_ input: Input) -> Factor {
        let income = input.monthlyIncome.reduce(0, +)
        let expense = input.monthlyExpense.reduce(0, +)
        let months = input.monthlyIncome.count
        guard income > 0 else {
            return Factor(kind: .cashflow, points: 0, maxPoints: 30,
                          summary: expense > 0 ? L("Belum ada pemasukan tercatat, tapi ada pengeluaran.") : L("Belum ada pemasukan tercatat."),
                          tip: L("Catat gaji dan pemasukan lain supaya kelihatan berapa yang bisa disisihkan."))
        }
        let rate = (income - expense) / income
        let points = switch rate {
        case 0.2...: 30
        case 0.1..<0.2: 24
        case 0..<0.1: 15
        case -0.1..<0: 6
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
        return Factor(kind: .cashflow, points: points, maxPoints: 30, summary: summary, tip: tip)
    }

    /// Months of spending the liquid balance covers.
    private static func emergencyFund(_ input: Input) -> Factor {
        let active = zip(input.monthlyIncome, input.monthlyExpense).filter { $0 + $1 > 0 }.map(\.1)
        let averageExpense = active.isEmpty ? 0 : active.reduce(0, +) / Double(active.count)
        guard averageExpense > 0 else {
            let hasBalance = input.liquidBalance > 0
            return Factor(kind: .emergencyFund, points: hasBalance ? 25 : 0, maxPoints: 25,
                          summary: hasBalance ? L("Belum ada pengeluaran untuk dibandingkan.") : L("Belum ada saldo tersimpan."),
                          tip: hasBalance ? nil : L("Mulai sisihkan saldo untuk dana darurat, sekecil apa pun."))
        }
        let months = max(input.liquidBalance, 0) / averageExpense
        let points = switch months {
        case 6...: 25
        case 3..<6: 18
        case 1..<3: 10
        case 0.01..<1: 4
        default: 0
        }
        let summary = input.liquidBalance <= 0
            ? L("Saldomu minus, belum ada dana darurat.")
            : L("Saldo cukup untuk %@ bulan pengeluaran.", months.formatted(.number.precision(.fractionLength(1)).locale(AppLanguage.locale)))
        let target = averageExpense * 3
        let gap = target - max(input.liquidBalance, 0)
        let tip: String? = months >= 3 ? nil
            : L("Kumpulkan dana darurat minimal 3 bulan pengeluaran, sekitar %@. Sisihkan %@ per bulan untuk mencapainya dalam setahun.",
                target.abbreviatedRupiahText, (gap / 12).abbreviatedRupiahText)
        return Factor(kind: .emergencyFund, points: points, maxPoints: 25, summary: summary, tip: tip)
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

    /// Spending pace against the budget for the part of the month gone.
    private static func budget(_ input: Input) -> Factor {
        guard input.budgetTotal > 0 else {
            return Factor(kind: .budget, points: 0, maxPoints: 15,
                          summary: L("Belum ada budget bulan ini."),
                          tip: input.topExpenseCategory.map { L("Buat budget, mulai dari %@ yang paling besar pengeluarannya.", $0) }
                            ?? L("Buat budget untuk kategori pengeluaran terbesarmu."))
        }
        let used = input.budgetSpent / input.budgetTotal
        // The first days carry little signal, so the pace never expects less than a fifth.
        let pace = input.budgetSpent / (input.budgetTotal * max(input.monthProgress, 0.2))
        let points = switch (used > 1, pace) {
        case (true, _): 0
        case (false, ..<1.0001): 15
        case (false, ..<1.1): 10
        case (false, ..<1.25): 5
        default: 0
        }
        let summary = L("Terpakai %lld%% budget, %lld%% bulan sudah lewat.",
                        Int((used * 100).rounded()), Int((input.monthProgress * 100).rounded()))
        let tip: String? = points == 15 ? nil
            : used > 1 ? L("Budget bulan ini sudah terlewati. Tahan pengeluaran yang tidak wajib sampai bulan depan.")
            : L("Belanjamu lebih cepat dari jadwal. Batasi ke %@ per hari supaya cukup sampai akhir bulan.", ((input.budgetTotal - input.budgetSpent) / max(1, (1 - input.monthProgress) * 30)).abbreviatedRupiahText)
        return Factor(kind: .budget, points: points, maxPoints: 15, summary: summary, tip: tip)
    }

    /// Days with at least one transaction in the last 30.
    private static func habit(_ input: Input) -> Factor {
        let points = switch input.activeDays {
        case 20...: 10
        case 12..<20: 7
        case 5..<12: 4
        case 1..<5: 2
        default: 0
        }
        let tip: String? = input.activeDays >= 12 ? nil
            : L("Catat transaksi setiap hari, termasuk yang kecil, supaya skor dan saranmu akurat.")
        return Factor(kind: .habit, points: points, maxPoints: 10,
                      summary: L("Mencatat di %lld dari 30 hari terakhir.", input.activeDays), tip: tip)
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
                               calendar: Calendar = .current) -> (income: [Double], expense: [Double]) {
        let counted = transactions.filter { $0.type == .income || $0.type == .expense }
        let first = counted.map(\.date).min()
        var periods = [3, 2, 1].map { cycle.period(offset: -$0, from: now, calendar: calendar) }
            .filter { period in first.map { $0 < period.end } ?? false }
        if periods.isEmpty { periods = [cycle.period(containing: now, calendar: calendar)] }
        func total(_ type: Transaction.TransactionType, in period: DateInterval) -> Double {
            counted.filter { $0.type == type && $0.date >= period.start && $0.date < period.end }.reduce(0) { $0 + $1.amount }
        }
        return (periods.map { total(.income, in: $0) }, periods.map { total(.expense, in: $0) })
    }
}

