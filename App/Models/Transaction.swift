import Foundation

struct Transaction: Identifiable, Codable {
    let id: String
    let accountId: String
    let counterpartyAccountId: String?
    let categoryId: String?
    let amount: Double
    let type: TransactionType
    let description: String?
    let note: String?
    let date: Date
    let delta: Double?
    /// The client operation id; recurring bills post as `sub_<subscription>_<date>`.
    var clientReferenceId: String? = nil

    enum TransactionType: String, Codable {
        case income = "income"
        case expense = "expense"
        case transfer = "transfer"
        case adjustment = "adjustment"
        /// A card bill paid from outside Saku: lowers the card's debt, moves no wallet.
        case cardPayment = "card_payment"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case accountId = "primary_account_id"
        case counterpartyAccountId = "counterparty_account_id"
        case categoryId = "category_id"
        case amount
        case type = "transaction_type"
        case description
        case note
        case date = "occurred_at"
        case delta
        case clientReferenceId = "client_reference_id"
    }

    /// Posted automatically from a recurring bill when its date arrived.
    var isRecurring: Bool { clientReferenceId?.hasPrefix("sub_") == true }

    /// "Spotify" out of the "Tagihan berulang: Spotify" note the auto-posting writes.
    var recurringName: String? {
        guard isRecurring, let note else { return nil }
        let prefix = "Tagihan berulang: "
        return note.hasPrefix(prefix) ? String(note.dropFirst(prefix.count)) : note
    }
}
