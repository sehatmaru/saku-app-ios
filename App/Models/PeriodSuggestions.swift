import Foundation

/// The three suggestions of the period analysis (Fitur 7 US3), chosen from a fixed catalogue. Each one's effect on the score
/// is worked out for real: FinancialHealth is recomputed on the data as it would be after following it. No advice on an
/// emergency fund, no card interest figures, no investment products.
extension PeriodAnalysis {
    struct Suggestion: Equatable {
        enum Kind: CaseIterable {
            case limitOverBudget, setAsideOnPayday, reviewSubscriptions, delayFlexible, payCardInFull
            case createBudget, recordRegularly, logIncome
        }

        let kind: Kind
        let action: String
        let reason: String
        /// Used when the long text does not fit: the font is never shrunk.
        let shortAction: String
        let shortReason: String
        /// "±Rp150.000" for an estimate, "Rp2.400.000" when exact, "" when no rupiah figure applies.
        let impact: String
        /// Points on the 0–100 score; shown only from 1 up.
        let scoreImpact: Int
    }

    struct Advice: Equatable {
        /// Three, most effective first.
        let suggestions: [Suggestion]
        /// The score with all three followed together (recomputed as one, not summed), at most 100.
        let projectedScore: Int
    }

    private typealias Edit = (inout FinancialHealth.Input) -> Void
    private struct Candidate {
        let kind: Suggestion.Kind
        let action: String, reason: String, shortAction: String, shortReason: String
        let amount: Double?
        let isEstimate: Bool
        let edit: Edit
    }

    /// Estimates are rounded so they do not pretend to be exact.
    static func rounded(_ value: Double) -> Double {
        let step = value >= 1_000_000 ? 50_000.0 : 10_000.0
        return max((value / step).rounded() * step, step)
    }

    private static func spendLess(_ amount: Double) -> Edit {
        { input in
            guard let last = input.monthlyExpense.indices.last else { return }
            input.monthlyExpense[last] = max(0, input.monthlyExpense[last] - amount)
        }
    }

    static func advice(_ input: Input) -> Advice {
        let isPrivate = input.isPrivate
        let income = input.current.income, expense = input.current.expense
        var found: [Candidate] = []

        if let over = input.budgets.filter({ $0.spent > $0.amount }).max(by: { $0.spent - $0.amount < $1.spent - $1.amount }) {
            let excess = over.spent - over.amount
            found.append(Candidate(
                kind: .limitOverBudget,
                action: L("Batasi %@ agar tidak melewati budget", over.name),
                reason: L("Periode ini %@ melewati budget %@.", over.name, money(excess, isPrivate: isPrivate)),
                shortAction: L("Batasi %@", over.name),
                shortReason: L("Lewat budget %@.", money(excess, isPrivate: isPrivate)),
                amount: rounded(excess), isEstimate: true,
                edit: { $0.budgetSpent = max(0, $0.budgetSpent - excess) }))
        }

        if income > 0 {
            let target = min(max(Rule.healthyNetRatio - (input.current.netRatio ?? 0), 0.05), Rule.healthyNetRatio)
            let amount = income * target
            found.append(Candidate(
                kind: .setAsideOnPayday,
                action: L("Sisihkan sebagian pemasukan di hari gajian"),
                reason: L("Pindahkan ke tabungan atau investasi begitu gajian masuk, sebelum dipakai belanja."),
                shortAction: L("Sisihkan di hari gajian"), shortReason: L("Pindahkan begitu gajian masuk."),
                amount: rounded(amount), isEstimate: true, edit: spendLess(amount)))
        } else {
            found.append(Candidate(
                kind: .logIncome,
                action: L("Catat pemasukanmu supaya sisa periode terhitung"),
                reason: L("Tanpa pemasukan, analisis belum bisa membandingkan periode ini dengan yang lain."),
                shortAction: L("Catat pemasukan"), shortReason: L("Supaya sisa periode terhitung."),
                amount: nil, isEstimate: false, edit: { _ in }))
        }

        let streaming = streamingCharges(input.charges)
        if streaming.count >= 2, let cheapest = streaming.map(\.amount).min() {
            let sum = streaming.reduce(0) { $0 + $1.amount }
            found.append(Candidate(
                kind: .reviewSubscriptions,
                action: L("Tinjau langganan streaming yang sejenis"),
                reason: L("%lld langganan streaming berjumlah %@. Pertahankan yang paling sering dipakai.", streaming.count, money(sum, isPrivate: isPrivate)),
                shortAction: L("Tinjau langganan streaming"),
                shortReason: L("%lld langganan, %@.", streaming.count, money(sum, isPrivate: isPrivate)),
                amount: rounded(cheapest), isEstimate: true, edit: spendLess(cheapest)))
        }

        let flexible = input.current.categories.filter { input.flexibleCategories.contains($0.key) }.values.reduce(0, +)
        // Without a known discretionary category, ease off the biggest one a little.
        let delayBase = flexible > 0 ? flexible : (input.current.categories.values.max() ?? 0)
        if delayBase > 0 {
            let amount = delayBase * (flexible > 0 ? 0.2 : 0.1)
            found.append(Candidate(
                kind: .delayFlexible,
                action: L("Tunda belanja yang tidak mendesak"),
                reason: L("Pengeluaran fleksibel periode ini %@. Menundanya sebagian memberi ruang di periode berikutnya.", money(delayBase, isPrivate: isPrivate)),
                shortAction: L("Tunda belanja tidak mendesak"),
                shortReason: L("Fleksibel: %@ periode ini.", money(delayBase, isPrivate: isPrivate)),
                amount: rounded(amount), isEstimate: true, edit: spendLess(amount)))
        }

        let health = input.health
        if health.creditDebt > 0, health.liquidBalance >= health.creditDebt {
            let debt = health.creditDebt
            found.append(Candidate(
                kind: .payCardInFull,
                action: L("Bayar penuh tagihan kartu kredit"),
                reason: L("Kasmu cukup untuk melunasinya sekarang, jadi tagihan tidak menumpuk."),
                shortAction: L("Bayar penuh tagihan kartu"), shortReason: L("Kas cukup untuk melunasi."),
                amount: debt, isEstimate: false,
                edit: { $0.creditDebt = 0; $0.liquidBalance -= debt; $0.overdueBills = [] }))
        }

        if health.budgetTotal <= 0 {
            found.append(Candidate(
                kind: .createBudget,
                action: L("Buat budget untuk kategori terbesarmu"),
                reason: L("Dengan budget, skor bisa menilai kendali pengeluaran tiap kategori."),
                shortAction: L("Buat budget"), shortReason: L("Skor jadi bisa menilai kendali kategori."),
                amount: nil, isEstimate: false,
                edit: { input in
                    // A budget sized to the spending, followed on pace.
                    input.budgetTotal = max(expense * 1.1, 1)
                    input.budgetSpent = input.budgetTotal * max(input.monthProgress, 0.2) * 0.95
                }))
        }

        found.append(Candidate(
            kind: .recordRegularly,
            action: L("Catat transaksi lebih rutin"),
            reason: L("Mencatat setiap hari membuat skor dan analisis lebih akurat."),
            shortAction: L("Catat lebih rutin"), shortReason: L("Skor dan analisis jadi lebih akurat."),
            amount: nil, isEstimate: false, edit: { $0.activeDays = max($0.activeDays, 20) }))

        let current = FinancialHealth(health).score
        let ranked = found.enumerated().map { index, candidate -> (index: Int, candidate: Candidate, gain: Int) in
            (index, candidate, max(0, projectedScore(health, applying: [candidate.edit]) - current))
        }.sorted {
            if $0.gain != $1.gain { return $0.gain > $1.gain }
            let (a, b) = ($0.candidate.amount ?? 0, $1.candidate.amount ?? 0)
            return a != b ? a > b : $0.index < $1.index
        }.prefix(3)

        let suggestions = ranked.map { item -> Suggestion in
            let c = item.candidate
            let impact = c.amount.map { (c.isEstimate ? "±" : "") + money($0, isPrivate: isPrivate) } ?? ""
            return Suggestion(kind: c.kind, action: c.action, reason: c.reason, shortAction: c.shortAction,
                              shortReason: c.shortReason, impact: impact, scoreImpact: item.gain)
        }
        return Advice(suggestions: suggestions,
                      projectedScore: projectedScore(health, applying: ranked.map(\.candidate.edit)))
    }
}
