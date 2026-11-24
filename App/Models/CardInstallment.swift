import Foundation

/// A 0% installment: one card purchase billed in equal parts over `months` statements.
/// The purchase itself is an ordinary expense on the card; this only spreads its billing.
struct CardInstallment: Identifiable, Codable, Hashable {
    let id: String
    let accountId: String
    let transactionId: String
    let months: Int
    /// "yyyy-MM-dd". Set when the installment was arranged after the purchase was already on a closed statement: the
    /// conversion date is where the parts start. Nil = the purchase date.
    var startsFrom: String? = nil
    /// An early payoff (Enhancement "Cicilan setelah transaksi", C8): "yyyy-MM-dd" of the day, and how.
    var settledOn: String? = nil
    var settleMode: String? = nil
    /// The wallet-to-card transfer that paid it off (`settleMode == "paid"`); not a payment of the last bill.
    var settleTransferId: String? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case accountId = "account_id"
        case transactionId = "transaction_id"
        case months
        case startsFrom = "starts_from"
        case settledOn = "settled_on"
        case settleMode = "settle_mode"
        case settleTransferId = "settle_transfer_id"
    }

    enum SettleMode: String { case nextStatement = "next_statement", paid }

    static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// The date the parts are counted from: the conversion date, else the purchase date.
    func reference(purchaseDate: Date) -> Date {
        startsFrom.flatMap(Self.dateOnly.date(from:)) ?? purchaseDate
    }

    var settlement: (day: Date, mode: SettleMode)? {
        guard let day = settledOn.flatMap(Self.dateOnly.date(from:)), let raw = settleMode, let mode = SettleMode(rawValue: raw) else { return nil }
        return (day, mode)
    }

    /// One part's amount: parts 1...n-1 are the rounded share, the last takes what is left so the parts add up to `amount`.
    static func part(_ number: Int, of amount: Double, months: Int) -> Double {
        let share = (amount / Double(months)).rounded()
        return number >= months ? amount - share * Double(months - 1) : share
    }

    /// What is still to be billed after `billed` parts: S = A - round(A / n) x b.
    static func remaining(of amount: Double, months: Int, billed: Int) -> Double {
        guard billed < months else { return 0 }
        return amount - (amount / Double(months)).rounded() * Double(billed)
    }

    /// Turning it off or changing the tenor is only possible while no part has been billed (C4).
    func isUntouchedByBilling(billed: Int) -> Bool { billed == 0 && settledOn == nil }
}
