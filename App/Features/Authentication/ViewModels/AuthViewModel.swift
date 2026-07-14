import SwiftUI
import GoogleSignIn
import Supabase

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
    @Published var showSplash = true

    private var authListener: Any?

    init() {
        Task {
            await setupAuthListener()
        }
    }

    private func setupAuthListener() async {
        authListener = await SupabaseSDK.client.auth.onAuthStateChange { [weak self] event, _ in
            Task { @MainActor in
                if event == .signedOut {
                    self?.currentUser = nil
                    self?.isAuthenticated = false
                }
            }
        }
    }

    // MARK: - Session Check (called after splash)

    func checkSession() async {
        do {
            let session = try await SupabaseSDK.client.auth.session
            try await fetchProfileAndSetUser(authUserId: session.user.id, email: session.user.email ?? "", displayName: session.user.userMetadata["full_name"]?.stringValue ?? session.user.userMetadata["name"]?.stringValue)
        } catch is CancellationError {
            isAuthenticated = false
        } catch {
            isAuthenticated = false
        }
        withAnimation(.easeInOut(duration: 0.5)) {
            showSplash = false
        }
    }

    private func fetchProfileAndSetUser(authUserId: UUID, email: String, displayName: String?) async throws {
        var profile: UserProfile
        if let existing = try? await SupabaseSDK.fetchProfile(authUserId: authUserId) {
            if existing.displayName == nil, let displayName {
                try await SupabaseSDK.updateProfile(id: existing.id, displayName: displayName)
            }
            profile = existing
        } else {
            profile = try await SupabaseSDK.upsertProfile(authUserId: authUserId, displayName: displayName ?? email)
        }
        currentUser = User(
            id: profile.id.uuidString,
            authUserId: authUserId.uuidString,
            email: email,
            displayName: profile.displayName ?? displayName,
            defaultCurrencyCode: profile.defaultCurrencyCode
        )
        withAnimation(.easeInOut(duration: 0.4)) {
            isAuthenticated = true
        }
    }

    // MARK: - Google Sign-In

    func signInWithGoogle() {
        isGoogleLoading = true
        errorMessage = nil
        Task {
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
                let authResponse = try await SupabaseSDK.client.auth.signInWithIdToken(
                    credentials: OpenIDConnectCredentials(
                        provider: .google,
                        idToken: idToken,
                        accessToken: accessToken
                    )
                )

                let name = authResponse.user.userMetadata["full_name"]?.stringValue ?? authResponse.user.userMetadata["name"]?.stringValue
                try await fetchProfileAndSetUser(authUserId: authResponse.user.id, email: authResponse.user.email ?? "", displayName: name)
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
            isGoogleLoading = false
        }
    }

    // MARK: - Apple Sign-In (OAuth)

    func signInWithApple() {
        isAppleLoading = true
        errorMessage = nil
        Task {
            do {
                let authResponse = try await SupabaseSDK.client.auth.signInWithOAuth(
                    provider: .apple
                ) { session in
                    session.prefersEphemeralWebBrowserSession = true
                }

                let name = authResponse.user.userMetadata["full_name"]?.stringValue ?? authResponse.user.userMetadata["name"]?.stringValue
                try await fetchProfileAndSetUser(authUserId: authResponse.user.id, email: authResponse.user.email ?? "", displayName: name)
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
            isAppleLoading = false
        }
    }

    // MARK: - Guest (placeholder)

    func signInAsGuest(name: String) {}

    // MARK: - Logout

    func logout() {
        Task {
            try? await SupabaseSDK.client.auth.signOut()
            currentUser = nil
            withAnimation(.easeInOut(duration: 0.4)) {
                isAuthenticated = false
            }
        }
    }

}
