import Foundation

extension Account {
    var isInvestment: Bool { type == .investment }
}

/// Which wallet may sit on which side of a transaction. Investment wallets hold value, not spending money:
/// they only ever move through a transfer with a non-investment wallet, or a value update.
enum WalletRules {
    /// Wallets an expense or income can be recorded on.
    static func spendingSources(_ accounts: [Account]) -> [Account] {
        accounts.filter { $0.isActive && !$0.isInvestment }
    }

    /// Wallets money can be sent to from `source` (nil: no source picked yet). A card can't receive a
    /// transfer, and two investment wallets can't trade with each other.
    static func transferTargets(from source: Account?, in accounts: [Account]) -> [Account] {
        accounts.filter { $0.isActive && !$0.isCreditCard && $0.id != source?.id && !(source?.isInvestment == true && $0.isInvestment) }
    }

    static func canTransfer(from source: Account, to target: Account) -> Bool {
        source.id != target.id && !target.isCreditCard && !(source.isInvestment && target.isInvestment)
    }

    /// Money moved from a cash wallet into an investment wallet.
    static func isDeposit(_ txn: Transaction, accounts: [Account]) -> Bool {
        guard txn.type == .transfer, let counterparty = txn.counterpartyAccountId else { return false }
        return accounts.first { $0.id == counterparty }?.isInvestment == true
    }

    /// Money moved from an investment wallet back to a cash wallet.
    static func isWithdrawal(_ txn: Transaction, accounts: [Account]) -> Bool {
        txn.type == .transfer && accounts.first { $0.id == txn.accountId }?.isInvestment == true
    }
}

/// Cash, investment assets and the two together, over the active wallets. Credit cards stay out of both,
/// as they do in the cash balance today.
struct WealthSummary: Equatable {
    let cash: Double
    let assets: Double
    var total: Double { cash + assets }

    init(accounts: [Account]) {
        let active = accounts.filter(\.isActive)
        cash = active.filter { !$0.isCreditCard && !$0.isInvestment }.reduce(0) { $0 + $1.balance }
        assets = active.filter(\.isInvestment).reduce(0) { $0 + $1.balance }
    }
}

/// What an investment wallet is worth, what was put in, and the difference.
struct InvestmentSummary: Equatable {
    let value: Double
    /// Starting value plus deposits minus withdrawals. Needs the wallet's opening balance to stay untouched.
    let capital: Double
    let lastUpdated: Date?

    var gain: Double { value - capital }
    /// Nil while nothing has been put in, so there is no percentage to show.
    var percent: Double? { capital > 0 ? gain / capital : nil }

    init(account: Account, transactions: [Transaction]) {
        value = account.balance
        var capital = account.openingBalance
        var updated: Date?
        for txn in transactions {
            switch txn.type {
            case .transfer:
                if txn.counterpartyAccountId == account.id { capital += txn.amount }
                if txn.accountId == account.id { capital -= txn.amount }
            case .adjustment where txn.accountId == account.id:
                updated = max(updated ?? txn.date, txn.date)
            default: break
            }
        }
        self.capital = capital
        lastUpdated = updated
    }
}

extension InvestmentSummary {
    /// "4%" or "4,5%": at most one decimal in the app's language; `signed` adds + or −.
    static func percentText(_ fraction: Double, signed: Bool = false) -> String {
        let f = NumberFormatter()
        f.locale = AppLanguage.locale
        f.maximumFractionDigits = 1
        f.minimumFractionDigits = 0
        let body = (f.string(from: NSNumber(value: abs(fraction * 100))) ?? "0") + "%"
        guard signed else { return body }
        return (fraction > 0.0004 ? "+" : fraction < -0.0004 ? "−" : "") + body
    }
}

extension Account {
    var openedDate: Date? {
        guard let openedAt else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: openedAt) ?? ISO8601DateFormatter().date(from: openedAt)
    }
}

/// An investment wallet's history, grouped by month: what it was worth at the month's end, the capital then,
/// and the month's value updates. Deposits and withdrawals are transfers touching the wallet.
struct InvestmentHistory {
    struct Row: Identifiable {
        enum Kind { case value, deposit, withdrawal, opening }
        let id: String
        let kind: Kind
        let date: Date
        /// Where the money came from or went to, for deposits and withdrawals.
        let otherName: String?
        let amount: Double
        /// Value before and after, for a value update.
        let from: Double
        let to: Double
        let note: String?
    }

    struct Month: Identifiable {
        let id: String
        let start: Date
        let endValue: Double
        let capital: Double
        /// The month's value updates added up; nil when there were none.
        let change: Double?
        let rows: [Row]
    }

    /// Months newest first.
    static func months(account: Account, transactions: [Transaction], accounts: [Account], calendar: Calendar = .current) -> [Month] {
        var rows: [Row] = []
        var value = account.openingBalance
        var capital = account.openingBalance
        var cursor: [(date: Date, value: Double, capital: Double)] = []
        let names = Dictionary(accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

        let ordered = transactions
            .filter { $0.accountId == account.id || $0.counterpartyAccountId == account.id }
            .filter { $0.type == .transfer || ($0.type == .adjustment && $0.accountId == account.id) }
            .sorted { $0.date < $1.date }

        if account.openingBalance > 0 {
            let opened = account.openedDate ?? ordered.first?.date ?? Date()
            rows.append(Row(id: "opening", kind: .opening, date: opened, otherName: nil, amount: account.openingBalance,
                            from: 0, to: account.openingBalance, note: nil))
            cursor.append((opened, value, capital))
        }
        for txn in ordered {
            switch txn.type {
            case .transfer where txn.counterpartyAccountId == account.id:
                value += txn.amount; capital += txn.amount
                rows.append(Row(id: txn.id, kind: .deposit, date: txn.date, otherName: names[txn.accountId], amount: txn.amount, from: 0, to: 0, note: nil))
            case .transfer:
                value -= txn.amount; capital -= txn.amount
                rows.append(Row(id: txn.id, kind: .withdrawal, date: txn.date, otherName: txn.counterpartyAccountId.flatMap { names[$0] }, amount: txn.amount, from: 0, to: 0, note: nil))
            default:
                let delta = txn.delta ?? txn.amount
                let note = txn.description.flatMap { $0 == "Perbarui nilai" || $0.hasPrefix("Penyesuaian Saldo") ? nil : $0 }
                rows.append(Row(id: txn.id, kind: .value, date: txn.date, otherName: nil, amount: delta, from: value, to: value + delta, note: note))
                value += delta
            }
            cursor.append((txn.date, value, capital))
        }

        var months: [Month] = []
        let grouped = Dictionary(grouping: rows) { calendar.dateInterval(of: .month, for: $0.date)?.start ?? $0.date }
        for start in grouped.keys.sorted(by: >) {
            let monthRows = (grouped[start] ?? []).sorted { $0.date > $1.date }
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            let state = cursor.last { $0.date < end } ?? (account.openedDate ?? start, account.openingBalance, account.openingBalance)
            let updates = monthRows.filter { $0.kind == .value }
            months.append(Month(id: ISO8601DateFormatter().string(from: start), start: start, endValue: state.value, capital: state.capital,
                                change: updates.isEmpty ? nil : updates.reduce(0) { $0 + $1.amount }, rows: monthRows))
        }
        return months
    }
}
