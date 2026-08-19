import Foundation

struct CardSubscription: Identifiable, Codable {
    let id: String
    let accountId: String
    let name: String
    let amount: Double
    let frequency: Frequency
    let nextBillingDate: String?
    let isActive: Bool
    let categoryId: String?
    let note: String?
    let createdAt: String?
    let updatedAt: String?

    enum Frequency: String, Codable {
        case monthly, yearly
    }

    enum CodingKeys: String, CodingKey {
        case id
        case accountId = "account_id"
        case name
        case amount
        case frequency
        case nextBillingDate = "next_billing_date"
        case isActive = "is_active"
        case categoryId = "category_id"
        case note
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var monthlyAmount: Double {
        switch frequency {
        case .monthly: amount
        case .yearly: amount / 12
        }
    }

    var yearlyAmount: Double {
        switch frequency {
        case .monthly: amount * 12
        case .yearly: amount
        }
    }
}
