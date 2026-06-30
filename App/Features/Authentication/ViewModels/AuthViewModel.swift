import SwiftUI
import GoogleSignIn

enum AuthPresentationError: LocalizedError {
    case noWindowScene
    case noGoogleIdToken

    var errorDescription: String? {
        switch self {
        case .noWindowScene: return "Gagal memulai sign in"
        case .noGoogleIdToken: return "Tidak dapat memperoleh token Google"
        }
    }
}

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var isGoogleLoading = false
    @Published var isAppleLoading = false
    @Published var errorMessage: String?
    @Published var showSplash = false

    func signInWithGoogle() {
        isGoogleLoading = true
        errorMessage = nil
        Task { @MainActor in
            do {
                guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                      let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
                else {
                    throw AuthPresentationError.noWindowScene
                }

                let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)

                guard let idToken = result.user.idToken?.tokenString else {
                    throw AuthPresentationError.noGoogleIdToken
                }

                let accessToken = result.user.accessToken.tokenString
                let authResult = try await SupabaseSDK.signInWithGoogle(
                    idToken: idToken,
                    accessToken: accessToken
                )

                currentUser = User(
                    id: authResult.id,
                    email: authResult.email,
                    fullName: authResult.fullName
                )
                isAuthenticated = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isGoogleLoading = false
        }
    }

    func signInWithApple() {
        isAppleLoading = true
        errorMessage = nil
        Task { @MainActor in
            do {
                let authSession = try await SupabaseSDK.client.auth.signInWithOAuth(
                    provider: .apple
                ) { session in
                    session.prefersEphemeralWebBrowserSession = true
                }
                let supaUser = authSession.user
                currentUser = User(
                    id: supaUser.id.uuidString,
                    email: supaUser.email ?? "",
                    fullName: supaUser.userMetadata["full_name"]?.stringValue
                        ?? supaUser.userMetadata["name"]?.stringValue
                        ?? ""
                )
                isAuthenticated = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isAppleLoading = false
        }
    }

    func signInAsGuest(name: String) {
        currentUser = User(id: UUID().uuidString, email: "guest@sakuq.app", fullName: name)
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

    private let authService = AuthService.shared
}
