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
        Category(id: "cat-1", name: "Makanan", icon: "fork.knife", color: "#FF6B6B", type: .expense),
        Category(id: "cat-2", name: "Gaji", icon: "dollarsign.circle", color: "#4ECDC4", type: .income),
        Category(id: "cat-3", name: "Minuman", icon: "cup.and.saucer", color: "#45B7D1", type: .expense),
        Category(id: "cat-4", name: "Transportasi", icon: "car", color: "#96CEB4", type: .expense),
        Category(id: "cat-5", name: "Tempat Tinggal", icon: "house", color: "#FFEAA7", type: .expense),
        Category(id: "cat-6", name: "Belanja", icon: "bag", color: "#DDA0DD", type: .expense),
        Category(id: "cat-7", name: "Hiburan", icon: "tv", color: "#98D8C8", type: .expense),
        Category(id: "cat-8", name: "Kesehatan", icon: "heart", color: "#F7DC6F", type: .expense),
        Category(id: "cat-9", name: "Listrik & Air", icon: "bolt.fill", color: "#FFD93D", type: .expense),
        Category(id: "cat-10", name: "Internet", icon: "wifi", color: "#6BCB77", type: .expense),
        Category(id: "cat-11", name: "Pendidikan", icon: "book.fill", color: "#4D96FF", type: .expense),
        Category(id: "cat-12", name: "Olahraga", icon: "figure.run", color: "#FF8C42", type: .expense),
    ]

    static var expenseCategories: [Category] {
        sample.filter { $0.type == .expense }
    }
}
