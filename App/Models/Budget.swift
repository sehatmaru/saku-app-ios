import Foundation

enum SpendingStatus: Comparable {
    case normal
    case warning
    case overbudget
}

struct Budget: Identifiable, Codable {
    let id: String
    let categoryId: String
    let amount: Double
    let spent: Double

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
}

extension Budget {
    static let sample: [Budget] = [
        Budget(id: "bud-1", categoryId: "cat-1", amount: 1_500_000, spent: 800_000),
        Budget(id: "bud-2", categoryId: "cat-4", amount: 500_000, spent: 20_000),
        Budget(id: "bud-3", categoryId: "cat-5", amount: 2_000_000, spent: 400_000),
        Budget(id: "bud-4", categoryId: "cat-7", amount: 500_000, spent: 80_000),
        Budget(id: "bud-5", categoryId: "cat-6", amount: 1_000_000, spent: 1_450_000),
        Budget(id: "bud-6", categoryId: "cat-8", amount: 300_000, spent: 20_000),
        Budget(id: "bud-7", categoryId: "cat-3", amount: 1_000_000, spent: 950_000),
    ]
}
