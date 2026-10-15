import Foundation

/// One row of `budget_amount_changes`: a base amount from a date on, or a temporary amount for a window.
struct BudgetAmountChange: Codable, Equatable {
    let budgetId: String
    let kind: String
    let amount: Double
    let effectiveFrom: Date
    /// Exclusive; set for temporary changes only.
    let effectiveTo: Date?
    let isEstimate: Bool
    let createdAt: Date

    var isTemporary: Bool { kind == "temporary" }

    enum CodingKeys: String, CodingKey {
        case budgetId = "budget_id", kind, amount
        case effectiveFrom = "effective_from", effectiveTo = "effective_to"
        case isEstimate = "is_estimate", createdAt = "created_at"
    }

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func dayString(_ date: Date) -> String { dayFormat.string(from: date) }

    init(budgetId: String, kind: String, amount: Double, effectiveFrom: Date, effectiveTo: Date? = nil,
         isEstimate: Bool = false, createdAt: Date = .distantPast) {
        self.budgetId = budgetId; self.kind = kind; self.amount = amount
        self.effectiveFrom = effectiveFrom; self.effectiveTo = effectiveTo
        self.isEstimate = isEstimate; self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        budgetId = try c.decode(String.self, forKey: .budgetId)
        kind = try c.decode(String.self, forKey: .kind)
        amount = try c.decode(Double.self, forKey: .amount)
        effectiveFrom = Self.dayFormat.date(from: try c.decode(String.self, forKey: .effectiveFrom)) ?? .distantPast
        effectiveTo = try c.decodeIfPresent(String.self, forKey: .effectiveTo).flatMap { Self.dayFormat.date(from: $0) }
        isEstimate = try c.decode(Bool.self, forKey: .isEstimate)
        let stamp = try c.decode(String.self, forKey: .createdAt)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        createdAt = fractional.date(from: stamp) ?? ISO8601DateFormatter().date(from: stamp) ?? .distantPast
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(budgetId, forKey: .budgetId)
        try c.encode(kind, forKey: .kind)
        try c.encode(amount, forKey: .amount)
        try c.encode(Self.dayString(effectiveFrom), forKey: .effectiveFrom)
        try c.encodeIfPresent(effectiveTo.map(Self.dayString), forKey: .effectiveTo)
        try c.encode(isEstimate, forKey: .isEstimate)
        try c.encode(ISO8601DateFormatter().string(from: createdAt), forKey: .createdAt)
    }
}

/// The amount a budget has in one period: a temporary change that covers it, else the latest base
/// change on or before its start, else (no trace) today's amount, marked as an estimate.
struct ResolvedBudgetAmount: Equatable {
    enum Source { case base, temporary, estimate }
    let amount: Double
    let source: Source
    /// The temporary change behind `.temporary`.
    let temporary: BudgetAmountChange?

    static func resolve(base: Double, changes: [BudgetAmountChange], periodStart: Date,
                        calendar: Calendar = .current) -> ResolvedBudgetAmount {
        let day = calendar.startOfDay(for: periodStart)
        if let temp = changes
            .filter({ $0.isTemporary && $0.effectiveFrom <= day && day < ($0.effectiveTo ?? .distantPast) })
            .max(by: { $0.createdAt < $1.createdAt }) {
            return ResolvedBudgetAmount(amount: temp.amount, source: .temporary, temporary: temp)
        }
        if let row = changes.filter({ !$0.isTemporary && $0.effectiveFrom <= day }).max(by: { $0.effectiveFrom < $1.effectiveFrom }) {
            // An estimate row stands in for periods that began before it was written.
            let estimated = row.isEstimate && day < calendar.startOfDay(for: row.createdAt)
            return ResolvedBudgetAmount(amount: row.amount, source: estimated ? .estimate : .base, temporary: nil)
        }
        return ResolvedBudgetAmount(amount: base, source: .estimate, temporary: nil)
    }
}

/// How long a new budget amount applies: from now on, or for N periods starting with the running one.
enum BudgetAmountDuration: Equatable {
    case forever
    case periods(Int)
}
