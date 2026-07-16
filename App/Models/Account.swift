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
    let creditLimit: Double?
    let dueDate: String?

    var isActive: Bool { !isArchived }
    var isCreditCard: Bool { type == .credit }
    var balance: Double { currentBalance ?? openingBalance }
    var dueDay: Int? { dueDate.flatMap { Int($0) } }

    var availableCredit: Double? {
        isCreditCard ? creditLimit.map { $0 - (currentBalance ?? 0) } : nil
    }

    var creditUtilization: Double? {
        isCreditCard ? creditLimit.map { $0 > 0 ? (currentBalance ?? 0) / $0 : 0 } : nil
    }

    enum AccountType: String, Codable, CaseIterable {
        case cash = "Cash"
        case bank = "Bank"
        case ewallet = "E-Wallet"
        case credit = "Credit Card"
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
        case creditLimit = "credit_limit"
        case dueDate = "due_date"
    }
}
