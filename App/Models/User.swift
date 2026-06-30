import Foundation

struct User: Identifiable, Codable {
    let id: String
    let authUserId: String
    let email: String
    let displayName: String?
    let defaultCurrencyCode: String

    enum CodingKeys: String, CodingKey {
        case id
        case authUserId = "auth_user_id"
        case email
        case displayName = "display_name"
        case defaultCurrencyCode = "default_currency_code"
    }
}

extension User {
    var fullName: String { displayName ?? "User" }
}
