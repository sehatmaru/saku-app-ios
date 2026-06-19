import Foundation

struct User: Identifiable, Codable {
    let id: String
    let email: String
    let fullName: String

    static let `default` = User(
        id: "static-user-001",
        email: "demo@sakuq.app",
        fullName: "Demo User"
    )
}
