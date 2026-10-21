import Foundation

/// The period analysis (Fitur 7), worked out on the device from rules and templates: no AI and no data
/// leaves the phone, and every number comes from the same figures as the rest of the app. Pure, so it can
/// be tested without drawing anything.
enum PeriodAnalysis {
    static var disclaimer: String { L("Analisis otomatis dari catatanmu. Bukan nasihat keuangan profesional.") }
    static var comparisonNote: String { L("Perbandingan butuh minimal 3 periode. Analisis ini memakai data periode ini saja.") }
    static var noDataMessage: String { L("Belum ada catatan di periode ini, jadi analisis belum bisa dibuat.") }

    /// What the report shows under "Analisis".
    struct Analysis: Equatable {
        struct Score: Equatable {
            let value: Int
            /// nil while the score is still provisional (less than three months of history).
            let label: String?
            /// With all three suggestions followed together.
            let projected: Int
        }

        /// nil when the score is not available yet: the section is left out and the findings use what exists.
        let score: Score?
        /// Set when fewer than three periods were available to compare with.
        let note: String?
        let findings: [Finding]
        let suggestions: [Suggestion]
        let hasBudgets: Bool
    }

    /// nil when nothing was recorded in the period: no analysis is made, the report says so.
    static func make(_ input: Input) -> Analysis? {
        guard input.current.income > 0 || input.current.expense > 0 else { return nil }
        let health = FinancialHealth(input.health)
        let plan = advice(input)
        return Analysis(
            score: health.isAvailable ? .init(value: health.score, label: health.label, projected: plan.projectedScore) : nil,
            note: input.previous.count < Rule.comparedPeriods ? comparisonNote : nil,
            findings: findings(input),
            suggestions: plan.suggestions,
            hasBudgets: !input.budgets.isEmpty)
    }

    /// One sentence on how the period went, as runs so the amounts and percentages can be coloured. The gap
    /// between In and Out is "Net" or what is left of the period, never "menyisihkan" (that word only fits money
    /// moved to savings).
    static func headlineRuns(income: Double, expense: Double, isPrivate: Bool = false) -> [ReportModel.Run] {
        let net = income - expense
        if net == 0 { return [.init(text: L("Net seimbang. Pemasukan dan pengeluaran periode ini sama besar."), tone: .neutral)] }
        let amount = money(net, sign: true, isPrivate: isPrivate)
        guard income > 0 else {
            return [.init(text: L("Net negatif "), tone: .neutral), .init(text: amount, tone: .danger),
                    .init(text: L(". Belum ada pemasukan tercatat di periode ini."), tone: .neutral)]
        }
        if net > 0 {
            return [.init(text: L("Net positif "), tone: .neutral), .init(text: amount, tone: .positive),
                    .init(text: L(". Sisa periode ini "), tone: .neutral),
                    .init(text: ReportModel.percent(net / income), tone: .positive),
                    .init(text: L(" dari pemasukan."), tone: .neutral)]
        }
        return [.init(text: L("Net negatif "), tone: .neutral), .init(text: amount, tone: .danger),
                .init(text: L(". Pengeluaran periode ini "), tone: .neutral),
                .init(text: ReportModel.percent(expense / income), tone: .danger),
                .init(text: L(" dari pemasukan. Yuk cari pos yang bisa ditekan."), tone: .neutral)]
    }

    static func headline(income: Double, expense: Double, isPrivate: Bool = false) -> String {
        headlineRuns(income: income, expense: expense, isPrivate: isPrivate).map(\.text).joined()
    }

    /// The score if every change in `edits` were made together: they are applied to one copy of the data and
    /// FinancialHealth is worked out again, so overlapping advice is not counted twice. At most 100.
    static func projectedScore(_ input: FinancialHealth.Input, applying edits: [(inout FinancialHealth.Input) -> Void]) -> Int {
        var hypothetical = input
        for edit in edits { edit(&hypothetical) }
        return min(100, FinancialHealth(hypothetical).score)
    }
}
