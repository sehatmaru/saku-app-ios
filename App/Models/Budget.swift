import Foundation

enum SpendingStatus: Comparable {
    case normal
    case warning
    case overbudget
}

struct Budget: Identifiable, Codable {
    let id: String
    let categoryId: String
    let name: String
    let amount: Double
    let periodUnit: String
    let periodInterval: Int
    let startDate: String
    let endDate: String?
    let isActive: Bool
    var spent: Double = 0

    var remaining: Double { amount - spent }
    var progress: Double { amount > 0 ? spent / amount : 0 }

    var daysInMonth: Int {
        Calendar.current.range(of: .day, in: .month, for: Date())?.count ?? 30
    }

    var currentDay: Int {
        Calendar.current.component(.day, from: Date())
    }

    var daysRemaining: Int {
        max(daysInMonth - currentDay, 0)
    }

    var idealDailyBudget: Double {
        amount / Double(daysInMonth)
    }

    var dailyRemaining: Double {
        daysRemaining > 0 ? remaining / Double(daysRemaining) : remaining
    }

    var spendingStatus: SpendingStatus {
        if spent >= amount { return .overbudget }
        guard daysRemaining > 0 else { return .normal }
        if dailyRemaining < idealDailyBudget * 0.5 { return .warning }
        return .normal
    }

    enum CodingKeys: String, CodingKey {
        case id, name, amount
        case categoryId = "category_id"
        case periodUnit = "period_unit"
        case periodInterval = "period_interval"
        case startDate = "start_date"
        case endDate = "end_date"
        case isActive = "is_active"
    }
}
