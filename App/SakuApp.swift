import SwiftUI

@main
struct SakuApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var authViewModel = AuthViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        // Keep this closure free of state reads: SwiftUI may re-run it on its async
        // render thread during animations, which trips Swift 6's main-actor check.
        WindowGroup {
            RootView()
                .environmentObject(authViewModel)
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    DraftStore.shared.ingestSharedText()
                }
        }
    }
}

/// Picks the top-level screen: splash, dashboard, onboarding, or sign-in.
struct RootView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @AppStorage("appTheme") private var appTheme: ThemeOption = .system
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("appLanguage") private var appLanguage = "id"

    enum ThemeOption: String {
        case light = "Terang"
        case dark = "Gelap"
        case system = "Sistem"

        var colorScheme: ColorScheme? {
            switch self {
            case .light: return .light
            case .dark: return .dark
            case .system: return nil
            }
        }
    }

    /// First name from the Google/Apple account, unless the profile only has an email.
    private var prefilledName: String {
        guard let name = authViewModel.currentUser?.displayName, !name.contains("@") else { return "" }
        return name.split(separator: " ").first.map(String.init) ?? ""
    }

    var body: some View {
        ZStack {
            if authViewModel.showSplash {
                SplashView { authViewModel.splashAnimationFinished() }
                .transition(.opacity)
            } else if let date = authViewModel.pendingDeletion {
                PendingDeletionView(date: date, authViewModel: authViewModel)
                    .transition(.opacity)
            } else if authViewModel.isAuthenticated, authViewModel.needsSetup {
                SetupOnboardingView(initialName: prefilledName) { setup in
                    await authViewModel.completeSetup(setup)
                }
                .transition(.opacity)
            } else if authViewModel.isAuthenticated {
                DashboardView()
                    .transition(.opacity)
            } else if !hasSeenOnboarding {
                // the intro melts away while the sign-in screen rises
                OnboardingView { hasSeenOnboarding = true }
                    .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .offset(y: -70))))
            } else {
                SignInView()
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.4), value: authViewModel.isAuthenticated)
        .animation(.easeInOut(duration: 0.5), value: authViewModel.showSplash)
        .animation(.settle(0.6), value: hasSeenOnboarding)
        .animation(.easeInOut(duration: 0.4), value: authViewModel.needsSetup)
        .animation(.easeInOut(duration: 0.4), value: authViewModel.pendingDeletion)
        .overlay {
            // setup was just saved: the welcome screen sits over Beranda until "Buka Sakumu" lets it slide away
            if let welcome = authViewModel.welcome {
                SetupWelcomeView(welcome: welcome) { startsEntry in
                    withAnimation(.settle(0.4)) { authViewModel.welcome = nil }
                    if startsEntry {
                        Task {
                            try? await Task.sleep(for: .milliseconds(450))
                            NotificationCenter.default.post(name: .openFirstEntry, object: nil)
                        }
                    }
                }
                .transition(.asymmetric(insertion: .identity, removal: .opacity.combined(with: .offset(y: -24))))
                .zIndex(10)
            }
        }
        .task { await authViewModel.checkSession() }
        .preferredColorScheme(appTheme.colorScheme)
        .environment(\.locale, AppLanguage.locale)
        .id(appLanguage)
    }
}
