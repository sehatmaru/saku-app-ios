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

        var id: Kind { kind }
        var ratio: Double { Double(points) / Double(maxPoints) }
        var missing: Int { maxPoints - points }

        var title: String {
            switch kind {
            case .cashflow: "Arus kas"
            case .emergencyFund: "Dana darurat"
            case .debt: "Utang kartu kredit"
            case .budget: "Budget"
            case .habit: "Kebiasaan mencatat"
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

    let factors: [Factor]
    /// False until there is something to score; the UI then explains instead of showing 0.
    let isAvailable: Bool

    var score: Int { factors.reduce(0) { $0 + $1.points } }

    var label: String {
        switch score {
        case 80...: "Sehat"
        case 60..<80: "Cukup"
        case 40..<60: "Kurang"
        default: "Perlu perbaikan"
        }
    }

    var isHealthy: Bool { score >= 80 }

    /// Factors with a tip, the ones costing the most points first.
    var recommendations: [Factor] {
        factors.filter { $0.tip != nil }.sorted { $0.missing > $1.missing }
    }

    /// One line on Beranda: the factor costing the most points.
    var weakest: Factor? { recommendations.first }

    static let empty = FinancialHealth(factors: [], isAvailable: false)

    private init(factors: [Factor], isAvailable: Bool) {
        self.factors = factors
        self.isAvailable = isAvailable
    }

    init(_ input: Input) {
        isAvailable = input.hasTransactions
        factors = [
            Self.cashflow(input),
            Self.emergencyFund(input),
            Self.debt(input),
            Self.budget(input),
            Self.habit(input),
        ]
    }

    // MARK: Factors

    /// Share of income left after spending, over the months shown.
    private static func cashflow(_ input: Input) -> Factor {
        let income = input.monthlyIncome.reduce(0, +)
        let expense = input.monthlyExpense.reduce(0, +)
        let months = input.monthlyIncome.count
        guard income > 0 else {
            return Factor(kind: .cashflow, points: 0, maxPoints: 30,
                          summary: expense > 0 ? "Belum ada pemasukan tercatat, tapi ada pengeluaran." : "Belum ada pemasukan tercatat.",
                          tip: "Catat gaji dan pemasukan lain supaya kelihatan berapa yang bisa disisihkan.")
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
            ? "Kamu menyisihkan \(percent)% dari pemasukan \(months) bulan terakhir."
            : "Pengeluaranmu \(percent)% lebih besar dari pemasukan \(months) bulan terakhir."
        let tip: String? = switch rate {
        case 0.2...: nil
        case 0..<0.2: "Targetkan menyisihkan 20% pemasukan. Pindahkan ke tabungan begitu gajian, sebelum dipakai belanja."
        default: "Pengeluaran melebihi pemasukan. Kurangi pos terbesarmu"
            + (input.topExpenseCategory.map { ", \($0)," } ?? "") + " dan tunda belanja yang tidak mendesak."
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
                          summary: hasBalance ? "Belum ada pengeluaran untuk dibandingkan." : "Belum ada saldo tersimpan.",
                          tip: hasBalance ? nil : "Mulai sisihkan saldo untuk dana darurat, sekecil apa pun.")
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
            ? "Saldomu minus, belum ada dana darurat."
            : "Saldo cukup untuk \(months.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "id_ID")))) bulan pengeluaran."
        let target = averageExpense * 3
        let gap = target - max(input.liquidBalance, 0)
        let tip: String? = months >= 3 ? nil
            : "Kumpulkan dana darurat minimal 3 bulan pengeluaran, sekitar \(target.abbreviatedRupiahText). "
            + "Sisihkan \((gap / 12).abbreviatedRupiahText) per bulan untuk mencapainya dalam setahun."
        return Factor(kind: .emergencyFund, points: points, maxPoints: 25, summary: summary, tip: tip)
    }

    /// Credit card use against the limit, or against monthly income when no limit is set.
    private static func debt(_ input: Input) -> Factor {
        guard input.hasCreditCard, input.creditDebt > 0 else {
            return Factor(kind: .debt, points: 20, maxPoints: 20,
                          summary: input.hasCreditCard ? "Tagihan kartu kreditmu sudah lunas." : "Tidak ada utang kartu kredit.",
                          tip: nil)
        }
        let incomes = input.monthlyIncome.filter { $0 > 0 }
        let averageIncome = incomes.isEmpty ? 0 : incomes.reduce(0, +) / Double(incomes.count)
        let base = input.creditLimit > 0 ? input.creditLimit : averageIncome
        let use = base > 0 ? input.creditDebt / base : 1
        let points = switch use {
        case ..<0.1: 20
        case 0.1..<0.3: 15
        case 0.3..<0.5: 8
        case 0.5..<0.8: 3
        default: 0
        }
        let percent = Int((use * 100).rounded())
        let summary = input.creditLimit > 0
            ? "Terpakai \(percent)% dari limit kartu kredit."
            : "Utang kartu kredit setara \(percent)% pemasukan bulanan."
        let tip: String? = use < 0.3 ? nil
            : "Jaga pemakaian di bawah 30% limit dan bayar tagihan penuh tiap jatuh tempo supaya tidak kena bunga."
        return Factor(kind: .debt, points: points, maxPoints: 20, summary: summary, tip: tip)
    }

    /// Spending pace against the budget for the part of the month gone.
    private static func budget(_ input: Input) -> Factor {
        guard input.budgetTotal > 0 else {
            return Factor(kind: .budget, points: 0, maxPoints: 15,
                          summary: "Belum ada budget bulan ini.",
                          tip: "Buat budget"
                            + (input.topExpenseCategory.map { ", mulai dari \($0) yang paling besar pengeluarannya" } ?? " untuk kategori pengeluaran terbesarmu")
                            + ".")
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
        let summary = "Terpakai \(Int((used * 100).rounded()))% budget, "
            + "\(Int((input.monthProgress * 100).rounded()))% bulan sudah lewat."
        let tip: String? = points == 15 ? nil
            : used > 1 ? "Budget bulan ini sudah terlewati. Tahan pengeluaran yang tidak wajib sampai bulan depan."
            : "Belanjamu lebih cepat dari jadwal. Batasi ke \(((input.budgetTotal - input.budgetSpent) / max(1, (1 - input.monthProgress) * 30)).abbreviatedRupiahText) per hari supaya cukup sampai akhir bulan."
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
            : "Catat transaksi setiap hari, termasuk yang kecil, supaya skor dan saranmu akurat."
        return Factor(kind: .habit, points: points, maxPoints: 10,
                      summary: "Mencatat di \(input.activeDays) dari 30 hari terakhir.", tip: tip)
    }
}

private extension Double {
    /// "Rp1,5 jt" for tips; reuses the app's short format.
    var abbreviatedRupiahText: String { "Rp" + abbreviatedRupiah() }
}
