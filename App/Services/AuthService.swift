import Foundation

enum AuthError: LocalizedError {
    case invalidCredentials
    case emailAlreadyRegistered
    case invalidEmail
    case weakPassword

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "Email atau password salah"
        case .emailAlreadyRegistered: return "Email sudah terdaftar"
        case .invalidEmail: return "Format email tidak valid"
        case .weakPassword: return "Password minimal 6 karakter"
        }
    }
}

final class AuthService: @unchecked Sendable {
    static let shared = AuthService()

    private let staticEmail = "demo@sakuq.app"
    private let staticPassword = "demo1234"
    private var registeredEmails: Set<String> = ["demo@sakuq.app"]

    private init() {}

    func login(email: String, password: String) throws -> User {
        guard email.lowercased() == staticEmail, password == staticPassword else {
            throw AuthError.invalidCredentials
        }
        return User.default
    }

    func register(email: String, password: String, fullName: String) throws -> User {
        guard email.contains("@"), email.contains(".") else {
            throw AuthError.invalidEmail
        }
        guard password.count >= 6 else {
            throw AuthError.weakPassword
        }
        guard !registeredEmails.contains(email.lowercased()) else {
            throw AuthError.emailAlreadyRegistered
        }
        registeredEmails.insert(email.lowercased())
        return User(id: UUID().uuidString, email: email, fullName: fullName)
    }
}
