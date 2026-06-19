import Foundation

struct Category: Identifiable, Codable {
    let id: String
    let name: String
    let icon: String
    let color: String
}

extension Category {
    static let sample: [Category] = [
        Category(id: "cat-1", name: "Makanan", icon: "fork.knife", color: "#FF6B6B"),
        Category(id: "cat-2", name: "Gaji", icon: "dollarsign.circle", color: "#4ECDC4"),
        Category(id: "cat-3", name: "Minuman", icon: "cup.and.saucer", color: "#45B7D1"),
        Category(id: "cat-4", name: "Transportasi", icon: "car", color: "#96CEB4"),
        Category(id: "cat-5", name: "Tempat Tinggal", icon: "house", color: "#FFEAA7"),
        Category(id: "cat-6", name: "Belanja", icon: "bag", color: "#DDA0DD"),
        Category(id: "cat-7", name: "Hiburan", icon: "tv", color: "#98D8C8"),
        Category(id: "cat-8", name: "Kesehatan", icon: "heart", color: "#F7DC6F"),
    ]
}
