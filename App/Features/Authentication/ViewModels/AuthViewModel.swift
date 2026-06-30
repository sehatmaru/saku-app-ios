import SwiftUI

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = true
    @Published var currentUser: User? = User.default
    @Published var isLoading = false
    @Published var isGoogleLoading = false
    @Published var isAppleLoading = false
    @Published var errorMessage: String?
    @Published var showSplash = false

    private let authService = AuthService.shared

    func signInWithGoogle() {
        isGoogleLoading = true
        errorMessage = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            currentUser = User.default
            isAuthenticated = true
            isGoogleLoading = false
        }
    }

    func signInWithApple() {
        isAppleLoading = true
        errorMessage = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            currentUser = User.default
            isAuthenticated = true
            isAppleLoading = false
        }
    }

    func signInAsGuest() {
        currentUser = User(id: UUID().uuidString, email: "guest@sakuq.app", fullName: "Tamu")
        isAuthenticated = true
    }

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
