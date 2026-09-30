import Foundation

struct User: Identifiable, Codable {
    let id: String
    let authUserId: String
    let email: String
    var displayName: String?
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
    /// Anonymous (guest) sessions carry no email.
    var isGuest: Bool { email.isEmpty }
}

extension User {
    /// Up to two initials from the display name, e.g. "Rina Pratama" -> "RP".
    var initials: String {
        let letters = fullName.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "U" : String(letters).uppercased()
    }
}
