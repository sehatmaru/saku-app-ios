import SwiftUI
import GoogleSignIn
import Supabase

enum AuthPresentationError: LocalizedError {
    case noWindowScene
    case noGoogleIdToken

    var errorDescription: String? {
        switch self {
        case .noWindowScene: return L("Gagal memulai sign in")
        case .noGoogleIdToken: return L("Tidak dapat memperoleh token Google")
        }
    }
}

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    /// Decoded profile photo (nil = show initials). Tab items need a bitmap, so it is kept here.
    @Published var avatarImage: UIImage?
    @Published var isLoading = false
    @Published var isGoogleLoading = false
    @Published var isAppleLoading = false
    @Published var errorMessage: String?
    @Published var showSplash = true
    /// Just signed up with Google/Apple and nothing set up yet: RootView shows SetupOnboardingView.
    @Published var needsSetup = false
    /// Signed in on an account that is waiting to be deleted: RootView shows PendingDeletionView until the user
    /// cancels the deletion or signs out.
    @Published var pendingDeletion: Date?

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

    /// `createdAt` of the auth user when this is a fresh sign-in (not a restored session).
    /// `offersSetup: false` when setup was just done (guests do it before signing in).
    private func fetchProfileAndSetUser(authUserId: UUID, email: String, displayName: String?, createdAt: Date? = nil, offersSetup: Bool = true) async throws {
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
            defaultCurrencyCode: profile.defaultCurrencyCode,
            avatarURL: profile.avatarUrl
        )
        await loadAvatar()
        if let raw = profile.deletionScheduledFor, let date = AccountDeletion.parse(raw) {
            pendingDeletion = date
            needsSetup = false
            return
        }
        // Accounts made in the last 10 minutes count as a sign-up; existing users never see setup.
        let isNewAccount = createdAt.map { Date().timeIntervalSince($0) < 600 } ?? false
        if offersSetup, isNewAccount {
            let accounts = try? await SupabaseRepository.shared.fetchAccounts(userId: profile.id.uuidString)
            needsSetup = accounts?.isEmpty ?? false
        } else {
            needsSetup = false
        }
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
                try await fetchProfileAndSetUser(authUserId: authResponse.user.id, email: authResponse.user.email ?? "", displayName: name, createdAt: authResponse.user.createdAt)
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
                try await fetchProfileAndSetUser(authUserId: authResponse.user.id, email: authResponse.user.email ?? "", displayName: name, createdAt: authResponse.user.createdAt)
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
            isAppleLoading = false
        }
    }

    // MARK: - Guest

    /// Anonymous Supabase session plus everything picked during guest setup.
    /// Needs "Allow anonymous sign-ins" enabled on the Supabase project.
    func signInAsGuest(_ setup: OnboardingSetup) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            // Reuse the guest session from a failed earlier attempt instead of minting another user.
            let existing = try? await SupabaseSDK.client.auth.session
            let session = if let existing, existing.user.isAnonymous { existing } else { try await SupabaseSDK.client.auth.signInAnonymously() }
            // The on_auth_user_created trigger already inserts the profile; just name it.
            let profile: UserProfile
            if let created = try? await SupabaseSDK.fetchProfile(authUserId: session.user.id) {
                try await SupabaseSDK.updateProfile(id: created.id, displayName: setup.name)
                profile = created
            } else {
                profile = try await SupabaseSDK.upsertProfile(authUserId: session.user.id, displayName: setup.name)
            }
            try await applySetup(setup, profileId: profile.id)
            try await fetchProfileAndSetUser(authUserId: session.user.id, email: "", displayName: setup.name,
                                             createdAt: session.user.createdAt, offersSetup: false)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Google/Apple users set up right after signing up: same steps, applied to the account they have.
    func completeSetup(_ setup: OnboardingSetup) async {
        guard let profileId = currentUser.flatMap({ UUID(uuidString: $0.id) }) else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await SupabaseSDK.updateProfile(id: profileId, displayName: setup.name)
            try await applySetup(setup, profileId: profileId)
            currentUser?.displayName = setup.name
            withAnimation(.easeInOut(duration: 0.4)) { needsSetup = false }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Wallets first (the dashboard opens with them there), then the best-effort extras:
    /// a failed category or payday write is not worth blocking sign-up, both can be set in Profil.
    private func applySetup(_ setup: OnboardingSetup, profileId: UUID) async throws {
        let repo = SupabaseRepository.shared
        // A retry after a partial failure must not duplicate wallets.
        if try await repo.fetchAccounts(userId: profileId.uuidString).isEmpty {
            for (i, w) in setup.wallets.enumerated() {
                _ = try await repo.createAccount(
                    name: w.name, type: w.type, openingBalance: w.balance, icon: w.icon,
                    userId: profileId.uuidString, isDefault: i == 0
                )
            }
        }
        if !setup.hiddenCategoryKeys.isEmpty, let all = try? await repo.fetchCategories() {
            let ids = all.filter { $0.systemKey.map(setup.hiddenCategoryKeys.contains) ?? false }.map(\.id)
            try? await repo.hideCategories(ids: ids)
        }
        if let day = setup.paydayDay {
            try? await SupabaseSDK.updatePayday(day: day)
        }
    }

    // MARK: - Hapus akun

    /// Asks the server to delete this account in 30 days, then signs out everywhere and forgets what this device kept.
    /// False when the server refused (nothing changed).
    func requestDeletion(reason: AccountDeletion.Reason?, note: String) async -> Bool {
        do {
            _ = try await SupabaseSDK.requestAccountDeletion(reason: reason?.rawValue, note: reason == .other ? String(note.prefix(AccountDeletion.noteLimit)) : nil)
        } catch {
            // the server's own message is technical and in English; nothing was changed, so just say so
            errorMessage = L("Permintaan belum terkirim dan akunmu belum berubah. Coba lagi sebentar lagi.")
            return false
        }
        try? await SupabaseSDK.client.auth.signOut()
        GIDSignIn.sharedInstance.signOut()
        NotificationManager.shared.cancelAll()
        AppDataCache.shared.clearAll()
        PaydaySetting.day = nil
        PaydaySetting.schedule = []
        HomeBalanceSetting.mode = nil
        SmartTrackerConsent.isGranted = false
        SmartTrackerMemorySync.isGranted = false
        SmartTrackerMemorySync.declinedAt = nil
        DraftStore.shared.reset()
        for key in ["paydayCardDismissed", "hasSeenOnboarding", "memberSince", "billReminderSnoozedUntil"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        needsSetup = false
        currentUser = nil
        withAnimation(.easeInOut(duration: 0.4)) { isAuthenticated = false }
        return true
    }

    /// "Batalkan" on PendingDeletionView: the account is active again with its data intact.
    func cancelPendingDeletion() async -> Bool {
        do {
            try await SupabaseSDK.cancelAccountDeletion()
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
        await loadAvatar()
        withAnimation(.easeInOut(duration: 0.4)) {
            pendingDeletion = nil
            isAuthenticated = true
        }
        return true
    }

    // MARK: - Logout

    func logout() {
        Haptics.logout()
        Task {
            try? await SupabaseSDK.client.auth.signOut()
            // drafts and what Saku learned belong to this account, and so does the agreement
            SmartTrackerConsent.isGranted = false
            SmartTrackerMemorySync.isGranted = false
            SmartTrackerMemorySync.declinedAt = nil
            DraftStore.shared.reset()
            currentUser = nil
            pendingDeletion = nil
            withAnimation(.easeInOut(duration: 0.4)) {
                isAuthenticated = false
            }
        }
    }


    /// Fetches the photo behind `currentUser.avatarURL`; the URL changes on every upload, so caching is safe.
    func loadAvatar() async {
        guard let string = currentUser?.avatarURL, let url = URL(string: string),
              let (data, _) = try? await URLSession.shared.data(from: url) else {
            avatarImage = nil
            return
        }
        avatarImage = UIImage(data: data)
    }
}
