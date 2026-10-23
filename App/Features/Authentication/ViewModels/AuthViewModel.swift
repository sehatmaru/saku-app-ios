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

/// What the guest-upgrade sheet shows (Enhancement 3): the question about an account that already exists, the
/// second warning, the wait, or a failure that leaves the guest account as it was.
enum GuestLinkStep: Equatable {
    case none
    /// "Simpan datamu ke akun ini?": shown before the Google sign-in opens, the same for every account.
    case beforeLogin
    /// The provider says the email is not verified; nothing was linked.
    case emailUnverified
    /// "Akun Google ini sudah terdaftar. Mau beralih ke akun itu?"
    case askSwitch
    /// "Data tamu di iPhone ini tidak akan ikut dan tidak bisa dipulihkan."
    case confirmSwitch
    case working(String)
    case failed(String)
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
    /// Set when setup has just been saved: RootView shows the welcome screen over Beranda until "Buka Sakumu".
    @Published var welcome: SetupWelcome?
    /// Just signed up with Google/Apple and nothing set up yet: RootView shows SetupOnboardingView.
    @Published var needsSetup = false
    /// Signed in on an account that is waiting to be deleted: RootView shows PendingDeletionView until the user
    /// cancels the deletion or signs out.
    @Published var pendingDeletion: Date?
    /// Guest upgrade (Enhancement 3): where the "this Google account already exists" question stands.
    @Published var guestLinkStep: GuestLinkStep = .none
    @Published var isLinking = false
    /// "Akun tertaut": the toast after a guest saved their account.
    @Published var linkSucceeded = false
    private enum LinkAction { case link, switchAccount }
    private var lastLinkAction = LinkAction.link
    /// The Google address of the account the guest would switch to, partly hidden, for the question's text.
    @Published var switchTargetEmail: String?
    /// What the guest would leave behind; nil when it could not be read ("Ringkasan data tamu belum tersedia").
    @Published var switchSummary: (wallets: Int, transactions: Int)?

    private var authListener: Any?
    /// The Google sign-in that was refused as already registered; kept to sign in to that account if the guest agrees.
    private var pendingGoogleCredentials: OpenIDConnectCredentials?

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

    // MARK: - Session Check (runs while the splash animates)

    private var sessionCheckStarted = false
    private var sessionChecked = false
    private var splashAnimationDone = false

    /// The splash leaves once both its animation and the session check are done, so the two overlap
    /// instead of adding up.
    private func dismissSplashIfReady() {
        guard sessionChecked, splashAnimationDone else { return }
        withAnimation(.easeInOut(duration: 0.5)) {
            showSplash = false
        }
    }

    func splashAnimationFinished() {
        splashAnimationDone = true
        dismissSplashIfReady()
    }

    func checkSession() async {
        // RootView's .task can run again (e.g. language change re-creates the view): check only once.
        guard !sessionCheckStarted else { return }
        sessionCheckStarted = true
        do {
            let session = try await SupabaseSDK.client.auth.session
            try await fetchProfileAndSetUser(authUserId: session.user.id, email: session.user.email ?? "", displayName: session.user.userMetadata["full_name"]?.stringValue ?? session.user.userMetadata["name"]?.stringValue)
        } catch is CancellationError {
            isAuthenticated = false
        } catch {
            isAuthenticated = false
        }
        sessionChecked = true
        dismissSplashIfReady()
    }

    /// Turns an auth user into the app's user: profile, avatar, deletion state, and whether setup is needed.
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
            defaultCurrencyCode: profile.defaultCurrencyCode,
            avatarURL: profile.avatarUrl
        )
        await loadAvatar()
        await clearAbandonedMarkIfGuest()
        if let raw = profile.deletionScheduledFor, let date = AccountDeletion.parse(raw) {
            pendingDeletion = date
            needsSetup = false
            return
        }
        await resolveSetupState(authUserId: authUserId, profileId: profile.id)
        withAnimation(.easeInOut(duration: 0.4)) {
            isAuthenticated = true
        }
    }

    /// Setup is the last step before a new account has any data. When the app is closed
    /// mid-onboarding the restored session still has a profile but no wallets, so show
    /// setup again instead of opening an empty app (BUG-43).
    private func resolveSetupState(authUserId: UUID, profileId: UUID) async {
        if OnboardingProgress.isComplete(authUserId: authUserId) {
            needsSetup = false
            return
        }
        let accounts = try? await SupabaseRepository.shared.fetchAccounts(userId: profileId.uuidString)
        if accounts?.isEmpty == false {
            // An existing account on a new device has wallets: setup already happened.
            OnboardingProgress.markComplete(authUserId: authUserId)
        }
        needsSetup = OnboardingProgress.needsSetup(markedComplete: false, accountCount: accounts?.count)
    }

    // MARK: - Google Sign-In

    /// Google's own sign-in sheet, turned into the credentials Supabase understands.
    private func googleCredentials() async throws -> OpenIDConnectCredentials {
        try await googleLogin().credentials
    }

    private func googleLogin() async throws -> (credentials: OpenIDConnectCredentials, email: String?) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else {
            throw AuthPresentationError.noWindowScene
        }
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthPresentationError.noGoogleIdToken
        }
        let credentials = OpenIDConnectCredentials(provider: .google, idToken: idToken, accessToken: result.user.accessToken.tokenString)
        return (credentials, result.user.profile?.email)
    }

    func signInWithGoogle() {
        isGoogleLoading = true
        errorMessage = nil
        Task {
            do {
                let authResponse = try await SupabaseSDK.client.auth.signInWithIdToken(credentials: try await googleCredentials())
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
            let summary = try await applySetup(setup, profileId: profile.id, isGuest: true)
            try await fetchProfileAndSetUser(authUserId: session.user.id, email: "", displayName: setup.name)
            welcome = summary
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Google/Apple users set up right after signing up: same steps, applied to the account they have.
    func completeSetup(_ setup: OnboardingSetup) async {
        guard let user = currentUser,
              let profileId = UUID(uuidString: user.id),
              let authUserId = UUID(uuidString: user.authUserId) else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await SupabaseSDK.updateProfile(id: profileId, displayName: setup.name)
            let summary = try await applySetup(setup, profileId: profileId, isGuest: false)
            currentUser?.displayName = setup.name
            OnboardingProgress.markComplete(authUserId: authUserId)
            welcome = summary
            withAnimation(.easeInOut(duration: 0.4)) { needsSetup = false }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Wallets first (the dashboard opens with them there), then the best-effort extras:
    /// a failed category, payday, budget, agreement or trial write is not worth blocking sign-up, all of them
    /// can be done later in the app. Returns what the welcome screen shows.
    private func applySetup(_ setup: OnboardingSetup, profileId: UUID, isGuest: Bool) async throws -> SetupWelcome {
        let repo = SupabaseRepository.shared
        // A retry after a partial failure must not duplicate wallets.
        if try await repo.fetchAccounts(userId: profileId.uuidString).isEmpty {
            // The main wallet is the first one that holds money: not a card, not an investment.
            let mainIndex = setup.wallets.firstIndex { $0.type != .credit && $0.type != .investment }
            for (i, w) in setup.wallets.enumerated() {
                _ = try await repo.createAccount(
                    name: w.name, type: w.type, openingBalance: w.balance, icon: w.icon.isEmpty ? nil : w.icon,
                    userId: profileId.uuidString, isDefault: i == mainIndex
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
        let budgetTotal = await createBudgets(setup.budgets, userId: profileId.uuidString)
        if setup.smartTrackerConsent {
            try? await SupabaseSDK.recordSmartTrackerConsent(profileId: profileId)
            if setup.memorySync, !isGuest {
                try? await SupabaseSDK.recordMemorySyncConsent(profileId: profileId)
                await DraftStore.shared.syncMemory()
            }
        }
        var joinedPlus = false
        if setup.joinsPlus, PlusStore.isInternalBuild {
            // Until StoreKit exists the trial starts on the server through the internal test switch, like the paywall.
            if (try? await SupabaseSDK.setTestPlusState("trial7")) != nil,
               let session = try? await SupabaseSDK.client.auth.session {
                _ = try? await SupabaseSDK.fetchProfile(authUserId: session.user.id)
                joinedPlus = PlusStore.shared.isPlus
            }
        }
        return SetupWelcome(name: setup.name, wallets: setup.wallets.count,
                            categories: OnboardingCategory.all.count - setup.hiddenCategoryKeys.count,
                            paydayDay: setup.paydayDay, budgetTotal: budgetTotal,
                            joinedPlus: joinedPlus, plusUntil: joinedPlus ? PlusStore.shared.entitlement.until : nil)
    }

    /// One monthly budget per category that was given an amount; a retry skips the ones already saved.
    /// Returns the total of what exists afterwards.
    private func createBudgets(_ budgets: [String: Double], userId: String) async -> Double {
        let amounts = budgets.filter { $0.value > 0 }
        guard !amounts.isEmpty else { return 0 }
        let repo = SupabaseRepository.shared
        guard let categories = try? await repo.fetchCategories() else { return 0 }
        let existing = Set(((try? await repo.fetchBudgets(userId: userId)) ?? []).map(\.categoryId))
        let start = ISO8601DateFormatter().string(from: PaydayCycle.current.period(containing: Date()).start)
        var total = 0.0
        for key in amounts.keys.sorted() {
            guard let amount = amounts[key], let category = categories.first(where: { $0.systemKey == key }) else { continue }
            if existing.contains(category.id) { total += amount; continue }
            if (try? await repo.createBudget(categoryId: category.id, name: category.name, amount: amount, periodUnit: "month",
                                             periodInterval: 1, startDate: start, endDate: nil, userId: userId)) != nil {
                total += amount
            }
        }
        NotificationCenter.default.post(name: .dataDidChange, object: nil)
        return total
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
        PlusStore.shared.reset()
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

    // MARK: - Guest upgrade (Enhancement 3)

    /// Links the Google account to the guest account that is signed in: same account id, so every wallet,
    /// transaction and budget stays. If that Google account already has a Saku account, asks what to do.
    func startGuestLink() {
        guard currentUser?.isGuest == true, !isLinking else { return }
        guestLinkStep = .beforeLogin
    }

    /// "Lanjut" on the notice: the sheet closes first so the Google screen has a free window to open over.
    func continueGuestLink() {
        guestLinkStep = .none
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            linkGoogleToGuest()
        }
    }

    func linkGoogleToGuest() {
        guard currentUser?.isGuest == true, !isLinking else { return }
        isLinking = true
        lastLinkAction = .link
        Task {
            defer { isLinking = false }
            do {
                let login = try await googleLogin()
                let credentials = login.credentials
                // only an address the provider has verified is accepted; nothing is linked or switched otherwise
                guard IdentityToken.emailIsVerified(credentials.idToken) else {
                    guestLinkStep = .emailUnverified
                    return
                }
                guestLinkStep = .working(L("Menautkan akun…"))
                do {
                    let session = try await SupabaseSDK.client.auth.linkIdentityWithIdToken(credentials: credentials)
                    try await finishLinking(session.user)
                } catch let error as AuthError where error.errorCode == .identityAlreadyExists {
                    pendingGoogleCredentials = credentials
                    switchTargetEmail = login.email.map(EmailMask.masked)
                    if let guestId = currentUser?.id {
                        switchSummary = try? await SupabaseRepository.shared.dataCounts(userId: guestId)
                    } else {
                        switchSummary = nil
                    }
                    guestLinkStep = .askSwitch
                }
            } catch is CancellationError {
                guestLinkStep = .none
            } catch let error as NSError where error.domain == kGIDSignInErrorDomain && error.code == GIDSignInError.canceled.rawValue {
                guestLinkStep = .none
            } catch {
                guestLinkStep = .failed(L("Koneksi terputus. Datamu masih aman di iPhone ini. Coba lagi sebentar lagi."))
            }
        }
    }

    /// The account is the same one, now with an email: refresh what the app shows, no sign-out needed.
    private func finishLinking(_ user: Supabase.User) async throws {
        let providerName = user.userMetadata["full_name"]?.stringValue ?? user.userMetadata["name"]?.stringValue
        if let providerName, let profileId = currentUser.flatMap({ UUID(uuidString: $0.id) }) {
            try? await SupabaseSDK.updateProfile(id: profileId, displayName: providerName)
        }
        try await fetchProfileAndSetUser(authUserId: user.id, email: user.email ?? "", displayName: providerName)
        DraftStore.shared.isGuest = false
        guestLinkStep = .none
        linkSucceeded = true
        Haptics.welcome()
    }

    func askSwitchConfirmation() {
        guestLinkStep = .confirmSwitch
    }

    /// Closing the sheet (Batal, Tutup, swipe): the guest stays a guest with everything as it was.
    func cancelSwitch() {
        guard !isLinking else { return }
        guestLinkStep = .none
        pendingGoogleCredentials = nil
        switchTargetEmail = nil
        switchSummary = nil
    }

    /// "Coba lagi" on the failure sheet.
    func retryLink() {
        guestLinkStep = .none
        switch lastLinkAction {
        case .link: linkGoogleToGuest()
        case .switchAccount: switchToExistingAccount()
        }
    }

    /// "Beralih ke akun itu": signs in to the existing account. The guest account is marked first (the server removes
    /// it after 30 days); if signing in fails the mark is taken back and the guest carries on.
    func switchToExistingAccount() {
        guard let credentials = pendingGoogleCredentials, !isLinking else { return }
        lastLinkAction = .switchAccount
        guestLinkStep = .working(L("Beralih ke akun itu…"))
        isLinking = true
        Task {
            defer { isLinking = false }
            do {
                try await SupabaseSDK.markGuestAbandoned()
                do {
                    let response = try await SupabaseSDK.client.auth.signInWithIdToken(credentials: credentials)
                    resetLocalAccountState()
                    pendingGoogleCredentials = nil
                    switchTargetEmail = nil
                    let name = response.user.userMetadata["full_name"]?.stringValue ?? response.user.userMetadata["name"]?.stringValue
                    try await fetchProfileAndSetUser(authUserId: response.user.id, email: response.user.email ?? "", displayName: name)
                    guestLinkStep = .none
                } catch {
                    try? await SupabaseSDK.clearGuestAbandoned()
                    throw error
                }
            } catch {
                guestLinkStep = .failed(L("Koneksi terputus. Kamu masih di akun tamu dan datamu utuh. Coba lagi sebentar lagi."))
            }
        }
    }

    /// A guest session that is back in use (app opened again) is not abandoned.
    private func clearAbandonedMarkIfGuest() async {
        guard currentUser?.isGuest == true else { return }
        try? await SupabaseSDK.clearGuestAbandoned()
    }

    /// What lives on this device for one account: the agreement, drafts, what Saku learned, the Plus state, and
    /// the guest card's own counters.
    private func resetLocalAccountState() {
        SmartTrackerConsent.isGranted = false
        SmartTrackerMemorySync.isGranted = false
        SmartTrackerMemorySync.declinedAt = nil
        DraftStore.shared.reset()
        PlusStore.shared.reset()
        GuestCardPolicy.resetCounters()
        Task { await NotificationManager.shared.removeInvestmentReminders() }
    }

    func logout() {
        Haptics.logout()
        Task {
            try? await SupabaseSDK.client.auth.signOut()
            resetLocalAccountState()
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
