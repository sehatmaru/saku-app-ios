import Foundation

/// How the total of the investment wallets splits between them (Fitur 7 US2): only numbers, never advice.
struct InvestmentAllocation: Equatable {
    struct Slice: Equatable, Identifiable {
        let id: String
        let name: String
        let value: Double
        /// 0...1 of the total.
        let fraction: Double
    }

    /// Biggest first.
    let slices: [Slice]
    let total: Double

    /// Two active investment wallets or more, and something in them to split; archived wallets do not count.
    init?(accounts: [Account]) {
        let active = accounts.filter { $0.isInvestment && $0.isActive }
        let total = active.reduce(0) { $0 + max($1.balance, 0) }
        guard active.count >= 2, total > 0 else { return nil }
        self.total = total
        slices = active
            .map { Slice(id: $0.id, name: $0.name, value: $0.balance, fraction: max($0.balance, 0) / total) }
            .sorted { $0.value > $1.value }
    }
}
