import Foundation

/// The three findings of the period analysis (Fitur 7 US2): one against the previous periods, one on
/// what holds the score back, one on a spending pattern. Pure, like the rest of PeriodAnalysis.
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

    struct Finding: Equatable {
        enum Group { case comparison, holdingBack, pattern }
        struct Bar: Equatable {
            let label: String
            let value: Double
        }

        let group: Group
        let kicker: String
        let title: String
        /// The number that proves it, e.g. "+13 poin" or "Rp629.000".
        let evidence: String
        let caption: String
        /// Two bars to compare: this period against its reference.
        let bars: [Bar]
        let body: String
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
    }

    /// Up to three findings, in the order comparison, holding back, pattern; a group without a candidate is left out.
    static func findings(current: Totals, previous: [Totals], health: FinancialHealth,
                         budgets: [ReportModel.BudgetLine], charges: [Charge], billsTotal: Double) -> [Finding] {
        [comparison(current: current, previous: previous),
         holdingBack(health: health, budgets: budgets),
         pattern(current: current, charges: charges, billsTotal: billsTotal)].compactMap { $0 }
    }

    // MARK: Against the previous periods

    /// The strongest shift against the average of the three periods before: Net ratio, income, expense or a
    /// category spike, each measured against its own threshold so they can be ranked.
    static func comparison(current: Totals, previous: [Totals]) -> Finding? {
        // Fewer than three periods is the edge case of US4.
        guard previous.count >= Rule.comparedPeriods else { return nil }
        let before = Array(previous.prefix(Rule.comparedPeriods))
        let kicker = L("Dibanding 3 periode sebelumnya")
        let thisPeriod = L("Periode ini"), average = L("Rata-rata 3 periode")
        var best: (strength: Double, finding: Finding)?
        func offer(_ strength: Double, _ finding: Finding) {
            if best == nil || strength > best!.strength { best = (strength, finding) }
        }
        func mean(_ values: [Double]) -> Double { values.reduce(0, +) / Double(max(values.count, 1)) }

        let ratios = before.compactMap(\.netRatio)
        if let now = current.netRatio, !ratios.isEmpty {
            let avg = mean(ratios), shift = now - avg
            if abs(shift) >= Rule.netRatioShift - 1e-9 {
                let points = Int((abs(shift) * 100).rounded()), nowPercent = percent(now), avgPercent = percent(avg)
                offer(abs(shift) / Rule.netRatioShift, Finding(
                    group: .comparison, kicker: kicker,
                    title: shift > 0 ? L("Sisa periode naik") : L("Sisa periode turun"),
                    evidence: (shift > 0 ? "+" : "−") + L("%lld poin", points),
                    caption: L("Sisa periode %lld%% dari pemasukan, rata-rata 3 periode %lld%%.", nowPercent, avgPercent),
                    bars: [.init(label: thisPeriod, value: now * 100), .init(label: average, value: avg * 100)],
                    body: shift > 0
                        ? L("Sisa periode ini naik %lld poin persentase, dari rata-rata %lld%% menjadi %lld%% dari pemasukan.", points, avgPercent, nowPercent)
                        : L("Sisa periode ini turun %lld poin persentase, dari rata-rata %lld%% menjadi %lld%% dari pemasukan.", points, avgPercent, nowPercent),
                    highlights: ["\(points)", "\(avgPercent)%", "\(nowPercent)%"]))
            }
        }

        for (subject, now, values) in [(L("Pemasukan"), current.income, before.map(\.income)),
                                       (L("Pengeluaran"), current.expense, before.map(\.expense))] {
            let avg = mean(values)
            guard avg > 0 else { continue }
            let change = (now - avg) / avg
            guard abs(change) >= Rule.flowShift - 1e-9 else { continue }
            let up = change > 0, changePercent = Int((abs(change) * 100).rounded())
            offer(abs(change) / Rule.flowShift, Finding(
                group: .comparison, kicker: kicker,
                title: "\(subject) \(up ? L("naik") : L("turun"))",
                evidence: (up ? "+" : "−") + "\(changePercent)%",
                caption: L("%@ dibanding rata-rata 3 periode %@.", now.formattedAsCurrency(), avg.formattedAsCurrency()),
                bars: [.init(label: thisPeriod, value: now), .init(label: average, value: avg)],
                body: L("%@ periode ini %@, %@ %lld%% dari rata-rata 3 periode sebelumnya (%@).",
                        subject, now.formattedAsCurrency(), up ? L("naik") : L("turun"), changePercent, avg.formattedAsCurrency()),
                highlights: [now.formattedAsCurrency(), "\(changePercent)%", avg.formattedAsCurrency()]))
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
                caption: L("%@ dibanding rata-rata 3 periode %@.", now.formattedAsCurrency(), avg.formattedAsCurrency()),
                bars: [.init(label: thisPeriod, value: now), .init(label: average, value: avg)],
                body: L("Pengeluaran %@ naik %lld%% dibanding rata-rata 3 periode sebelumnya, dari %@ menjadi %@.",
                        name, risePercent, avg.formattedAsCurrency(), now.formattedAsCurrency()),
                highlights: ["\(risePercent)%", avg.formattedAsCurrency(), now.formattedAsCurrency()]))
        }
        return best?.finding
    }

    // MARK: What holds the score back

    /// The factor costing the most points. When that is the budget and a category went over it, the finding
    /// names the category that went furthest over.
    static func holdingBack(health: FinancialHealth, budgets: [ReportModel.BudgetLine]) -> Finding? {
        guard health.isAvailable, let weakest = health.weakest else { return nil }
        let kicker = L("Yang menahan skor")
        if weakest.kind == .budget,
           let over = budgets.filter({ $0.spent > $0.amount }).max(by: { $0.spent - $0.amount < $1.spent - $1.amount }) {
            let excess = (over.spent - over.amount).formattedAsCurrency(), amount = over.amount.formattedAsCurrency()
            return Finding(
                group: .holdingBack, kicker: kicker,
                title: L("%@ melewati budget", over.name),
                evidence: "+" + excess,
                caption: L("Terpakai %@ dari budget %@.", over.spent.formattedAsCurrency(), amount),
                bars: [.init(label: L("Terpakai"), value: over.spent), .init(label: L("Budget"), value: over.amount)],
                body: L("%@ melewati budget, %@ di atas %@.", over.name, excess, amount),
                highlights: [excess, amount])
        }
        return Finding(
            group: .holdingBack, kicker: kicker, title: weakest.title,
            evidence: "−" + L("%lld poin", weakest.missing),
            caption: weakest.summary,
            bars: [.init(label: L("Poin didapat"), value: Double(weakest.points)), .init(label: L("Poin penuh"), value: Double(weakest.maxPoints))],
            body: weakest.tip ?? weakest.summary,
            highlights: [])
    }

    // MARK: Spending pattern

    /// Names that tell a streaming subscription apart from other bills.
    private static let streamingNames = ["netflix", "spotify", "disney", "vidio", "youtube", "viu", "hbo", "prime video",
                                         "apple tv", "apple music", "wetv", "iqiyi", "joox", "catchplay", "genflix"]

    /// Several subscriptions of one kind piling up (streaming) inside "Tagihan & Langganan"; when none are found,
    /// the biggest expense category instead.
    static func pattern(current: Totals, charges: [Charge], billsTotal: Double) -> Finding? {
        let kicker = L("Pola pengeluaran")
        let streaming = charges.filter { charge in streamingNames.contains { charge.name.lowercased().contains($0) } }
        if streaming.count >= 2, billsTotal > 0 {
            let sum = streaming.reduce(0) { $0 + $1.amount }
            let share = min(100, Int((sum / billsTotal * 100).rounded()))
            return Finding(
                group: .pattern, kicker: kicker,
                title: L("Langganan streaming menumpuk"),
                evidence: sum.formattedAsCurrency(),
                caption: L("%lld%% dari Tagihan & Langganan", share),
                bars: [.init(label: L("Streaming"), value: sum), .init(label: L("Tagihan & Langganan"), value: billsTotal)],
                body: L("%lld langganan streaming berjumlah %@, %lld%% dari Tagihan & Langganan %@.",
                        streaming.count, sum.formattedAsCurrency(), share, billsTotal.formattedAsCurrency()),
                highlights: [sum.formattedAsCurrency(), "\(share)%", billsTotal.formattedAsCurrency()])
        }
        guard current.expense > 0,
              let top = current.categories.sorted(by: { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }).first
        else { return nil }
        let share = Int((top.value / current.expense * 100).rounded())
        return Finding(
            group: .pattern, kicker: kicker,
            title: L("%@ pos terbesar", top.key),
            evidence: "\(share)%",
            caption: top.value.formattedAsCurrency(),
            bars: [.init(label: top.key, value: top.value), .init(label: L("Pengeluaran"), value: current.expense)],
            body: L("%@ memakai %lld%% pengeluaranmu periode ini, sebesar %@.", top.key, share, top.value.formattedAsCurrency()),
            highlights: ["\(share)%", top.value.formattedAsCurrency()])
    }

    private static func percent(_ fraction: Double) -> Int { Int((fraction * 100).rounded()) }
}
