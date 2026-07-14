import Foundation

enum CategoryType: String, Codable {
    case income
    case expense
    case adjustment
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
