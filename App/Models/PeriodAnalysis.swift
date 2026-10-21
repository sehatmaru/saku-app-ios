import Foundation

/// The period analysis (Fitur 7), worked out on the device from rules and templates: no AI and no data
/// leaves the phone. Pure, so the numbers can be tested without drawing anything.
enum PeriodAnalysis {
    /// One sentence on how the period went. The gap between In and Out is "Net" or what is left of the
    /// period, never "menyisihkan" (that word only fits money moved to savings).
    static func headline(income: Double, expense: Double) -> String {
        let net = income - expense
        if net == 0 { return L("Net seimbang. Pemasukan dan pengeluaran periode ini sama besar.") }
        let amount = abs(net).formattedAsCurrency()
        guard income > 0 else {
            return L("Net negatif -%@. Belum ada pemasukan tercatat di periode ini.", amount)
        }
        let percent = Int((abs(net) / income * 100).rounded())
        return net > 0
            ? L("Net positif +%@. Sisa periode ini %lld%% dari pemasukan.", amount, percent)
            : L("Net negatif -%@. Pengeluaran periode ini %lld%% dari pemasukan. Yuk cari pos yang bisa ditekan.", amount, Int((expense / income * 100).rounded()))
    }

    /// The score if every change in `edits` were made together: they are applied to one copy of the data and
    /// FinancialHealth is worked out again, so overlapping advice is not counted twice. At most 100.
    static func projectedScore(_ input: FinancialHealth.Input, applying edits: [(inout FinancialHealth.Input) -> Void]) -> Int {
        var hypothetical = input
        for edit in edits { edit(&hypothetical) }
        return min(100, FinancialHealth(hypothetical).score)
    }
}
