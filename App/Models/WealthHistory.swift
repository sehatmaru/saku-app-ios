import Foundation

/// Total kekayaan over time for the Statistik page: what the active cash, bank, e-wallet and investment wallets held
/// at the end of each day that had a record, and how much of it was in investments. Worked backwards from today's
/// balances, so the last point always equals the total shown above the chart. Credit cards stay out, as on Dompet.
struct WealthHistory: Equatable {
    struct Point: Equatable {
        let date: Date
        let total: Double
        let invested: Double
    }

    /// Oldest first.
    let points: [Point]

    init(accounts: [Account], transactions: [Transaction], now: Date = Date(), calendar: Calendar = .current) {
        let held = accounts.filter { $0.isActive && !$0.isCreditCard }
        let investment = Set(held.filter(\.isInvestment).map(\.id))
        let cash = Set(held.filter { !$0.isInvestment }.map(\.id))
        var cashNow = held.filter { !$0.isInvestment }.reduce(0) { $0 + $1.balance }
        var investedNow = held.filter(\.isInvestment).reduce(0) { $0 + $1.balance }

        /// What a record did to (cash, investments).
        func effect(_ txn: Transaction) -> (cash: Double, invested: Double) {
            var result = (cash: 0.0, invested: 0.0)
            func add(_ id: String?, _ value: Double) {
                guard let id else { return }
                if cash.contains(id) { result.cash += value } else if investment.contains(id) { result.invested += value }
            }
            switch txn.type {
            case .income: add(txn.accountId, txn.amount)
            case .expense, .cardPayment: add(txn.accountId, -txn.amount)
            case .adjustment: add(txn.accountId, txn.delta ?? txn.amount)
            case .transfer:
                add(txn.accountId, -txn.amount)
                add(txn.counterpartyAccountId, txn.amount)
            }
            return result
        }

        let byDay = Dictionary(grouping: transactions) { calendar.startOfDay(for: $0.date) }
        var backwards: [Point] = []
        for day in byDay.keys.sorted(by: >) {
            backwards.append(Point(date: day, total: cashNow + investedNow, invested: investedNow))
            for txn in byDay[day] ?? [] {
                let e = effect(txn)
                cashNow -= e.cash
                investedNow -= e.invested
            }
        }
        var ordered = Array(backwards.reversed())
        // the line runs on to today at today's balances
        if let last = ordered.last, last.date < calendar.startOfDay(for: now) {
            let total = held.reduce(0) { $0 + $1.balance }
            ordered.append(Point(date: calendar.startOfDay(for: now), total: total, invested: held.filter(\.isInvestment).reduce(0) { $0 + $1.balance }))
        }
        points = ordered
    }

    /// The chart: total as the solid line, investments as the dashed one.
    func series(range: InvestmentSeries.Range, now: Date = Date()) -> InvestmentSeries {
        InvestmentSeries(all: points.map { .init(date: $0.date, value: $0.total, capital: $0.invested, isChange: true) }, range: range, now: now)
    }
}
