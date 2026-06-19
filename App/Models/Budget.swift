import Foundation

struct Budget: Identifiable, Codable {
    let id: String
    let categoryId: String
    let amount: Double
    let spent: Double

    var remaining: Double { amount - spent }
    var progress: Double { amount > 0 ? min(spent / amount, 1.0) : 0 }
}

extension Budget {
    static let sample: [Budget] = [
        Budget(id: "bud-1", categoryId: "cat-1", amount: 1_500_000, spent: 875_000),
        Budget(id: "bud-2", categoryId: "cat-4", amount: 500_000, spent: 320_000),
        Budget(id: "bud-3", categoryId: "cat-5", amount: 2_000_000, spent: 1_500_000),
        Budget(id: "bud-4", categoryId: "cat-7", amount: 500_000, spent: 150_000),
    ]
}
