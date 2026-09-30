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
    }
}
