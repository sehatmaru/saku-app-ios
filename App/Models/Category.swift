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

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case icon
        case color
        case type = "category_kind"
        case systemKey = "system_key"
    }
}
