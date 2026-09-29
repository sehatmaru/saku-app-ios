import Foundation

/// A 0% installment: one card purchase billed in equal parts over `months` statements.
/// The purchase itself is an ordinary expense on the card; this only spreads its billing.
struct CardInstallment: Identifiable, Codable, Hashable {
    let id: String
    let accountId: String
    let transactionId: String
    let months: Int

    enum CodingKeys: String, CodingKey {
        case id
        case accountId = "account_id"
        case transactionId = "transaction_id"
        case months
    }
}
