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

    var nextBillingDateAsDate: Date? {
        guard let nextBillingDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: nextBillingDate)
    }

    func rolledNextBillingDate(from date: Date) -> Date? {
        let calendar = Calendar.current
        switch frequency {
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date)
        }
    }

    var billingDateString: String {
        guard let date = nextBillingDateAsDate else { return "-" }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        formatter.locale = Locale(identifier: "id_ID")
        return formatter.string(from: date)
    }
}
