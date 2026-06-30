import Foundation

enum CategoryType: String, Codable {
    case income
    case expense
}

struct Category: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let icon: String?
    let color: String?
    let type: CategoryType

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case icon
        case color
        case type = "category_kind"
    }
}
