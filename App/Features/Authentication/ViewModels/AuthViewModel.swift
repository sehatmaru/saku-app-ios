import SwiftUI

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = true
    @Published var currentUser: User? = User.default
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showSplash = true

    private let authService = AuthService.shared

    func login(email: String, password: String) {
        isLoading = true
        errorMessage = nil

        do {
            let user = try authService.login(email: email, password: password)
            currentUser = user
            isAuthenticated = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func register(email: String, password: String, fullName: String) {
        isLoading = true
        errorMessage = nil

        do {
            let user = try authService.register(email: email, password: password, fullName: fullName)
            currentUser = user
            isAuthenticated = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func logout() {
        currentUser = nil
        isAuthenticated = false
    }

    func dismissSplash() {
        withAnimation(.easeInOut(duration: 0.5)) {
            showSplash = false
        }
    }
}
