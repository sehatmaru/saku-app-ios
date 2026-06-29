import Foundation

enum CategoryType: String, Codable {
    case income
    case expense
}

struct Category: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let icon: String
    let color: String
    let type: CategoryType
}

extension Category {
    static let sample: [Category] = [
        Category(id: "cat-exp-1", name: "Makanan Sehari-hari", icon: "fork.knife", color: "#FF6B6B", type: .expense),
        Category(id: "cat-2", name: "Gaji", icon: "dollarsign.circle", color: "#4ECDC4", type: .income),
        Category(id: "cat-exp-2", name: "Jajan & Kopi", icon: "cup.and.saucer", color: "#45B7D1", type: .expense),
        Category(id: "cat-exp-3", name: "Restoran & Makan di Mall", icon: "building.columns.fill", color: "#96CEB4", type: .expense),
        Category(id: "cat-exp-4", name: "Belanja Pribadi", icon: "bag", color: "#DDA0DD", type: .expense),
        Category(id: "cat-exp-5", name: "Hiburan", icon: "tv", color: "#98D8C8", type: .expense),
        Category(id: "cat-exp-6", name: "Sembako & Rumah Tangga", icon: "basket", color: "#FFEAA7", type: .expense),
        Category(id: "cat-exp-7", name: "Transportasi", icon: "car", color: "#4ECDC4", type: .expense),
        Category(id: "cat-exp-8", name: "Perawatan & Kesehatan", icon: "heart", color: "#F7DC6F", type: .expense),
        Category(id: "cat-exp-9", name: "Sosial & Donasi", icon: "hand.raised.fill", color: "#6BCB77", type: .expense),
        Category(id: "cat-exp-10", name: "Olahraga & Fitness", icon: "figure.run", color: "#FF8C42", type: .expense),
        Category(id: "cat-exp-11", name: "Lainnya", icon: "ellipsis", color: "#A0A0A0", type: .expense),
    ]

    static var expenseCategories: [Category] {
        sample.filter { $0.type == .expense }
    }
}
