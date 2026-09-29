import Foundation

enum CategoryType: String, Codable {
    case income
    case expense

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = CategoryType(rawValue: rawValue) ?? .expense
    }
}

struct Category: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let icon: String?
    let color: String?
    let type: CategoryType
    let systemKey: String?
    /// "system" for the built-in ones everybody shares, "user" for the user's own.
    var ownerType: String? = nil

    /// Built-in: can be hidden, not renamed or deleted.
    var isBuiltIn: Bool { ownerType != "user" }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case icon
        case color
        case type = "category_kind"
        case systemKey = "system_key"
        case ownerType = "owner_type"
    }
}

/// The user's own settings for a category (built-in ones included): hidden from pickers
/// and its place in the list. No row means shown, in default order.
struct CategoryPreference: Codable, Hashable {
    let categoryId: String
    var isHidden: Bool
    var sortOrder: Int?

    enum CodingKeys: String, CodingKey {
        case categoryId = "category_id"
        case isHidden = "is_hidden"
        case sortOrder = "sort_order"
    }
}

extension Array where Element == Category {
    /// Splits categories into the ones to offer and the hidden ones, each in the user's order
    /// (custom order first, then by name). Hidden ones still resolve in history.
    func arranged(by preferences: [CategoryPreference]) -> (shown: [Category], hidden: [Category]) {
        let byId = Dictionary(preferences.map { ($0.categoryId, $0) }, uniquingKeysWith: { _, last in last })
        let sorted = self.sorted { a, b in
            switch (byId[a.id]?.sortOrder, byId[b.id]?.sortOrder) {
            case let (x?, y?) where x != y: x < y
            case (_?, nil): true
            case (nil, _?): false
            default: a.name.localizedCompare(b.name) == .orderedAscending
            }
        }
        let hidden = Set(preferences.filter(\.isHidden).map(\.categoryId))
        return (sorted.filter { !hidden.contains($0.id) }, sorted.filter { hidden.contains($0.id) })
    }
}
