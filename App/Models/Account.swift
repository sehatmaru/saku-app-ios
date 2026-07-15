import Foundation

struct Account: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let type: AccountType
    let icon: String?
    let isArchived: Bool
    let isDefault: Bool
    let openingBalance: Double
    var currentBalance: Double? = nil

    var isActive: Bool { !isArchived }
    var balance: Double { currentBalance ?? openingBalance }

    enum AccountType: String, Codable, CaseIterable {
        case cash = "Cash"
        case bank = "Bank"
        case ewallet = "E-Wallet"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case type = "account_type"
        case icon
        case isArchived = "is_archived"
        case isDefault = "is_default"
        case openingBalance = "opening_balance"
        case currentBalance = "current_balance"
    }
}
