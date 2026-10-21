import Foundation

/// The three findings of the period analysis (Fitur 7 US2, edge cases US4): one against the previous periods, one on
/// what holds the score back, one on a spending pattern. Always three: a group without a real candidate falls back to a
/// plainer finding. Pure, like the rest of PeriodAnalysis.
extension PeriodAnalysis {
    /// Money and spending of one payday period.
    struct Totals {
        var income: Double
        var expense: Double
        /// Expense per category name.
        var categories: [String: Double] = [:]

        /// Share of income left over; nil without income.
        var netRatio: Double? { income > 0 ? (income - expense) / income : nil }
    }

    /// A bill or subscription paid in the period.
    struct Charge {
        let name: String
        let amount: Double
    }

    /// Everything the analysis is worked out from.
    struct Input {
        var current: Totals
        /// The periods before, most recent first.
        var previous: [Totals]
        var health: FinancialHealth.Input
        var budgets: [ReportModel.BudgetLine]
        var charges: [Charge]
        /// What was paid under "Tagihan & Langganan" in the period.
        var billsTotal: Double
        /// Category names that are discretionary (can wait), for the advice.
        var flexibleCategories: Set<String>
        /// Hides every rupiah amount and keeps wallet names and balances out of the text.
        var isPrivate: Bool
    }

    struct Finding: Equatable {
        enum Group { case comparison, holdingBack, pattern }
        struct Bar: Equatable {
            let label: String
            /// As shown next to the label, e.g. "34%" or "Rp7.900.000".
            let text: String
            /// 0...1, against the longer of the two.
            let fraction: Double
        }

        let group: Group
        let kicker: String
        let title: String
        /// The number that proves it, e.g. "+13 poin" or "Rp629.000".
        let evidence: String
        let tone: ReportModel.Tone
        let caption: String
        /// Two bars to compare: this period against its reference.
        let bars: [Bar]
        let body: String
        /// Used when `body` does not fit: the font is never shrunk.
        let shortBody: String
        /// Numbers inside `body` to show highlighted.
        let highlights: [String]
    }

    /// Thresholds in one place: the product still has to validate them with real data.
    enum Rule {
        static let comparedPeriods = 3
        /// Net ratio moves at least this many points (0.05 = 5 percentage points) against the average.
        static let netRatioShift = 0.05
        /// Income or expense moves at least this much against the average.
        static let flowShift = 0.15
        /// A category rises at least this much, and at least `categoryRiseMin` rupiah, against the average.
        static let categoryRise = 0.30
        static let categoryRiseMin = 100_000.0
        /// The reference Net ratio when there are fewer than three periods to compare with.
        static let healthyNetRatio = 0.20
    }

    /// Exactly three findings, in the order comparison, holding back, pattern.
    static func findings(_ input: Input) -> [Finding] {
        let health = FinancialHealth(input.health)
        let private_ = input.isPrivate
        return [
            comparison(current: input.current, previous: input.previous, isPrivate: private_)
                ?? comparisonFallback(current: input.current, previous: input.previous),
            holdingBack(health: health, budgets: input.budgets, isPrivate: private_)
                ?? holdingBackFallback(health: health, input: input),
            pattern(current: input.current, charges: input.charges, billsTotal: input.billsTotal, isPrivate: private_)
                ?? patternFallback(isPrivate: private_),
        ]
    }

    static func money(_ value: Double, sign: Bool = false, isPrivate: Bool) -> String {
        ReportModel.rupiah(value, sign: sign, hidden: isPrivate)
    }

    private static func percent(_ fraction: Double) -> Int { Int((fraction * 100).rounded()) }

    private static func bars(_ first: (String, Double, String), _ second: (String, Double, String)) -> [Finding.Bar] {
        let longest = max(abs(first.1), abs(second.1), 0.0001)
        return [.init(label: first.0, text: first.2, fraction: min(1, abs(first.1) / longest)),
                .init(label: second.0, text: second.2, fraction: min(1, abs(second.1) / longest))]
    }

    // MARK: Against the previous periods

    /// The strongest shift against the average of the three periods before: Net ratio, income, expense or a
    /// category spike, each measured against its own threshold so they can be ranked. nil when nothing moved enough.
    static func comparison(current: Totals, previous: [Totals], isPrivate: Bool = false) -> Finding? {
        guard previous.count >= Rule.comparedPeriods else { return nil }
        let before = Array(previous.prefix(Rule.comparedPeriods))
        let kicker = L("Dibanding 3 periode sebelumnya")
        let thisPeriod = L("Periode ini"), average = L("Rata-rata 3 periode")
        var best: (strength: Double, finding: Finding)?
        func offer(_ strength: Double, _ finding: Finding) {
            if best == nil || strength > best!.strength { best = (strength, finding) }
        }
        func mean(_ values: [Double]) -> Double { values.reduce(0, +) / Double(max(values.count, 1)) }
        func rp(_ value: Double) -> String { money(value, isPrivate: isPrivate) }

        let ratios = before.compactMap(\.netRatio)
        if let now = current.netRatio, !ratios.isEmpty {
            let avg = mean(ratios), shift = now - avg
            if abs(shift) >= Rule.netRatioShift - 1e-9 {
                let points = Int((abs(shift) * 100).rounded()), nowPercent = percent(now), avgPercent = percent(avg)
                offer(abs(shift) / Rule.netRatioShift, Finding(
                    group: .comparison, kicker: kicker,
                    title: shift > 0 ? L("Sisa periode naik") : L("Sisa periode turun"),
                    evidence: (shift > 0 ? "+" : "−") + L("%lld poin", points),
                    tone: shift > 0 ? .positive : .warning,
                    caption: L("Sisa periode %lld%% dari pemasukan, rata-rata 3 periode %lld%%.", nowPercent, avgPercent),
                    bars: bars((thisPeriod, now, "\(nowPercent)%"), (average, avg, "\(avgPercent)%")),
                    body: shift > 0
                        ? L("Sisa periode ini naik %lld poin persentase, dari rata-rata %lld%% menjadi %lld%% dari pemasukan.", points, avgPercent, nowPercent)
                        : L("Sisa periode ini turun %lld poin persentase, dari rata-rata %lld%% menjadi %lld%% dari pemasukan.", points, avgPercent, nowPercent),
                    shortBody: shift > 0
                        ? L("Sisa periode naik %lld poin, dari %lld%% ke %lld%%.", points, avgPercent, nowPercent)
                        : L("Sisa periode turun %lld poin, dari %lld%% ke %lld%%.", points, avgPercent, nowPercent),
                    highlights: ["\(points)", "\(avgPercent)%", "\(nowPercent)%"]))
            }
        }

        for (subject, now, values, goodWhenUp) in [(L("Pemasukan"), current.income, before.map(\.income), true),
                                                   (L("Pengeluaran"), current.expense, before.map(\.expense), false)] {
            let avg = mean(values)
            guard avg > 0 else { continue }
            let change = (now - avg) / avg
            guard abs(change) >= Rule.flowShift - 1e-9 else { continue }
            let up = change > 0, changePercent = Int((abs(change) * 100).rounded())
            let verb = up ? L("naik") : L("turun")
            offer(abs(change) / Rule.flowShift, Finding(
                group: .comparison, kicker: kicker,
                title: "\(subject) \(verb)",
                evidence: (up ? "+" : "−") + "\(changePercent)%",
                tone: up == goodWhenUp ? .positive : .warning,
                caption: L("%@ dibanding rata-rata 3 periode %@.", rp(now), rp(avg)),
                bars: bars((thisPeriod, now, rp(now)), (average, avg, rp(avg))),
                body: L("%@ periode ini %@, %@ %lld%% dari rata-rata 3 periode sebelumnya (%@).", subject, rp(now), verb, changePercent, rp(avg)),
                shortBody: L("%@ %@ %lld%% dari rata-rata 3 periode.", subject, verb, changePercent),
                highlights: [rp(now), "\(changePercent)%", rp(avg)]))
        }

        for name in current.categories.keys.sorted() {
            let now = current.categories[name] ?? 0
            let avg = mean(before.map { $0.categories[name] ?? 0 })
            // A category with no history has nothing to rise from.
            guard avg > 0, now - avg >= Rule.categoryRiseMin else { continue }
            let rise = (now - avg) / avg
            guard rise >= Rule.categoryRise - 1e-9 else { continue }
            let risePercent = Int((rise * 100).rounded())
            offer(rise / Rule.categoryRise, Finding(
                group: .comparison, kicker: kicker,
                title: L("%@ melonjak", name),
                evidence: "+\(risePercent)%",
                tone: .warning,
                caption: L("%@ dibanding rata-rata 3 periode %@.", rp(now), rp(avg)),
                bars: bars((thisPeriod, now, rp(now)), (average, avg, rp(avg))),
                body: L("Pengeluaran %@ naik %lld%% dibanding rata-rata 3 periode sebelumnya, dari %@ menjadi %@.", name, risePercent, rp(avg), rp(now)),
                shortBody: L("%@ naik %lld%% dari rata-rata 3 periode.", name, risePercent),
                highlights: ["\(risePercent)%", rp(avg), rp(now)]))
        }
        return best?.finding
    }

    /// Fewer than three periods: the healthy reference (Net 20%) stands in for the comparison. Enough periods but
    /// nothing moved: say it is steady.
    static func comparisonFallback(current: Totals, previous: [Totals]) -> Finding {
        let kicker = L("Periode ini")
        guard let now = current.netRatio else {
            return Finding(group: .comparison, kicker: kicker, title: L("Belum ada pemasukan"), evidence: "—", tone: .neutral,
                           caption: L("Pemasukan belum tercatat."), bars: bars((L("Periode ini"), 0, "0%"), (L("Acuan sehat"), Rule.healthyNetRatio, "\(percent(Rule.healthyNetRatio))%")),
                           body: L("Catat pemasukan supaya sisa periode bisa dibandingkan."),
                           shortBody: L("Catat pemasukan supaya bisa dibandingkan."), highlights: [])
        }
        let nowPercent = percent(now)
        if previous.count >= Rule.comparedPeriods {
            let ratios = previous.prefix(Rule.comparedPeriods).compactMap(\.netRatio)
            let avg = ratios.isEmpty ? 0 : ratios.reduce(0, +) / Double(ratios.count)
            return Finding(group: .comparison, kicker: L("Dibanding 3 periode sebelumnya"), title: L("Sisa periode stabil"),
                           evidence: "\(nowPercent)%", tone: .neutral,
                           caption: L("Rata-rata 3 periode %lld%%.", percent(avg)),
                           bars: bars((L("Periode ini"), now, "\(nowPercent)%"), (L("Rata-rata 3 periode"), avg, "\(percent(avg))%")),
                           body: L("Sisa periode %lld%% dari pemasukan, mendekati rata-rata %lld%% di 3 periode sebelumnya.", nowPercent, percent(avg)),
                           shortBody: L("Sisa periode %lld%%, mendekati rata-rata %lld%%.", nowPercent, percent(avg)),
                           highlights: ["\(nowPercent)%", "\(percent(avg))%"])
        }
        let reference = percent(Rule.healthyNetRatio)
        return Finding(group: .comparison, kicker: kicker,
                       title: now >= Rule.healthyNetRatio ? L("Di atas acuan sehat") : L("Di bawah acuan sehat"),
                       evidence: "\(nowPercent)%", tone: now >= Rule.healthyNetRatio ? .positive : .warning,
                       caption: L("Sisa periode dari pemasukan."),
                       bars: bars((L("Periode ini"), now, "\(nowPercent)%"), (L("Acuan sehat"), Rule.healthyNetRatio, "\(reference)%")),
                       body: L("Sisa periode %lld%% dari pemasukan, acuan sehat %lld%%. Perbandingan dengan periodemu sendiri muncul setelah 3 periode penuh.", nowPercent, reference),
                       shortBody: L("Sisa periode %lld%%, acuan sehat %lld%%.", nowPercent, reference),
                       highlights: ["\(nowPercent)%", "\(reference)%"])
    }

    // MARK: What holds the score back

    /// The factor costing the most points. When that is the budget and a category went over it, the finding
    /// names the category that went furthest over. nil when nothing holds the score back.
    static func holdingBack(health: FinancialHealth, budgets: [ReportModel.BudgetLine], isPrivate: Bool = false) -> Finding? {
        // No budget at all: the fallback invites the user to make one, whatever else costs points.
        guard !budgets.isEmpty, health.isAvailable, let weakest = health.weakest else { return nil }
        let kicker = L("Yang menahan skor")
        if weakest.kind == .budget,
           let over = budgets.filter({ $0.spent > $0.amount }).max(by: { $0.spent - $0.amount < $1.spent - $1.amount }) {
            let excess = money(over.spent - over.amount, isPrivate: isPrivate), amount = money(over.amount, isPrivate: isPrivate)
            return Finding(
                group: .holdingBack, kicker: kicker,
                title: L("%@ melewati budget", over.name),
                evidence: "+" + excess, tone: .danger,
                caption: L("Terpakai %@ dari budget %@.", money(over.spent, isPrivate: isPrivate), amount),
                bars: bars((L("Terpakai"), over.spent, money(over.spent, isPrivate: isPrivate)), (L("Budget"), over.amount, amount)),
                body: L("%@ melewati budget, %@ di atas %@.", over.name, excess, amount),
                shortBody: L("%@ lewat %@ dari budget %@.", over.name, excess, amount),
                highlights: [excess, amount])
        }
        // The factors' own sentences may name a card or an amount: private mode keeps to a plain one.
        let body = isPrivate ? privateAdvice(weakest.kind) : (weakest.tip ?? weakest.summary)
        return Finding(
            group: .holdingBack, kicker: kicker, title: weakest.title,
            evidence: "−" + L("%lld poin", weakest.missing), tone: .warning,
            caption: isPrivate ? L("%lld dari %lld poin.", weakest.points, weakest.maxPoints) : weakest.summary,
            bars: bars((L("Poin didapat"), Double(weakest.points), "\(weakest.points)"), (L("Poin penuh"), Double(weakest.maxPoints), "\(weakest.maxPoints)")),
            body: body, shortBody: isPrivate ? body : weakest.summary, highlights: [])
    }

    private static func privateAdvice(_ kind: FinancialHealth.Kind) -> String {
        switch kind {
        case .cashflow: L("Sisihkan sebagian pemasukan begitu gajian, sebelum dipakai belanja.")
        case .emergencyFund: L("Tambah tabungan secara rutin, sekecil apa pun.")
        case .debt: L("Pastikan tagihan kartu kredit terbayar tepat waktu.")
        case .budget: L("Tahan pengeluaran yang tidak wajib supaya budget cukup sampai akhir periode.")
        case .habit: L("Catat transaksi setiap hari supaya skor dan saranmu akurat.")
        }
    }

    /// No budget (the score cannot judge category control), or nothing holds the score back.
    static func holdingBackFallback(health: FinancialHealth, input: Input) -> Finding {
        let kicker = L("Yang menahan skor")
        let top = input.current.categories.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.first?.key
        if input.budgets.isEmpty {
            return Finding(
                group: .holdingBack, kicker: kicker, title: L("Belum ada budget untuk dibandingkan"),
                evidence: L("Belum ada"), tone: .warning, caption: L("budget periode ini."),
                bars: bars((L("Pengeluaran"), input.current.expense, money(input.current.expense, isPrivate: input.isPrivate)), (L("Budget"), 0, "—")),
                body: top.map { L("Tanpa budget, skor belum bisa menilai kendali per kategori. Mulai dari %@, pos terbesarmu periode ini.", $0) }
                    ?? L("Tanpa budget, skor belum bisa menilai kendali per kategori. Buat budget untuk kategori terbesarmu."),
                shortBody: L("Tanpa budget, skor belum menilai kendali per kategori."), highlights: top.map { [$0] } ?? [])
        }
        let score = health.isAvailable ? health.score : nil
        return Finding(
            group: .holdingBack, kicker: kicker, title: L("Tidak ada yang menahan skor"),
            evidence: score.map { L("%lld/100", $0) } ?? "—", tone: .positive, caption: L("Semua faktor skor terpenuhi."),
            bars: bars((L("Poin didapat"), Double(score ?? 0), "\(score ?? 0)"), (L("Poin penuh"), 100, "100")),
            body: L("Semua faktor skormu sudah baik. Pertahankan kebiasaan ini di periode berikutnya."),
            shortBody: L("Semua faktor skormu sudah baik."), highlights: [])
    }

    // MARK: Spending pattern

    /// Names that tell a streaming subscription apart from other bills.
    private static let streamingNames = ["netflix", "spotify", "disney", "vidio", "youtube", "viu", "hbo", "prime video",
                                         "apple tv", "apple music", "wetv", "iqiyi", "joox", "catchplay", "genflix"]

    static func streamingCharges(_ charges: [Charge]) -> [Charge] {
        charges.filter { charge in streamingNames.contains { charge.name.lowercased().contains($0) } }
    }

    /// Several subscriptions of one kind piling up (streaming) inside "Tagihan & Langganan"; when none are found,
    /// the biggest expense category instead.
    static func pattern(current: Totals, charges: [Charge], billsTotal: Double, isPrivate: Bool = false) -> Finding? {
        let kicker = L("Pola pengeluaran")
        func rp(_ value: Double) -> String { money(value, isPrivate: isPrivate) }
        let streaming = streamingCharges(charges)
        if streaming.count >= 2, billsTotal > 0 {
            let sum = streaming.reduce(0) { $0 + $1.amount }
            let share = min(100, Int((sum / billsTotal * 100).rounded()))
            return Finding(
                group: .pattern, kicker: kicker,
                title: L("Langganan streaming menumpuk"),
                evidence: rp(sum), tone: .neutral,
                caption: L("%lld%% dari Tagihan & Langganan", share),
                bars: bars((L("Streaming"), sum, rp(sum)), (L("Tagihan & Langganan"), billsTotal, rp(billsTotal))),
                body: L("%lld langganan streaming berjumlah %@, %lld%% dari Tagihan & Langganan %@.", streaming.count, rp(sum), share, rp(billsTotal)),
                shortBody: L("%lld langganan streaming, %@ (%lld%%).", streaming.count, rp(sum), share),
                highlights: [rp(sum), "\(share)%", rp(billsTotal)])
        }
        guard current.expense > 0,
              let top = current.categories.sorted(by: { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }).first
        else { return nil }
        let share = Int((top.value / current.expense * 100).rounded())
        return Finding(
            group: .pattern, kicker: kicker,
            title: L("%@ pos terbesar", top.key),
            evidence: "\(share)%", tone: .neutral,
            caption: rp(top.value),
            bars: bars((top.key, top.value, rp(top.value)), (L("Pengeluaran"), current.expense, rp(current.expense))),
            body: L("%@ memakai %lld%% pengeluaranmu periode ini, sebesar %@.", top.key, share, rp(top.value)),
            shortBody: L("%@ memakai %lld%% pengeluaran.", top.key, share),
            highlights: ["\(share)%", rp(top.value)])
    }

    static func patternFallback(isPrivate: Bool) -> Finding {
        Finding(group: .pattern, kicker: L("Pola pengeluaran"), title: L("Belum ada pengeluaran"),
                evidence: money(0, isPrivate: isPrivate), tone: .neutral, caption: L("tercatat di periode ini."),
                bars: bars((L("Pengeluaran"), 0, money(0, isPrivate: isPrivate)), (L("Pemasukan"), 0, "—")),
                body: L("Belum ada pengeluaran tercatat di periode ini, jadi belum ada pola yang bisa dibaca."),
                shortBody: L("Belum ada pola yang bisa dibaca."), highlights: [])
    }
}
