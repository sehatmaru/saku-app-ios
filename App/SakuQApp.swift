import SwiftUI

@main
struct SakuQApp: App {
    @StateObject private var authViewModel = AuthViewModel()

    var body: some Scene {
        // Keep this closure free of state reads: SwiftUI may re-run it on its async
        // render thread during animations, which trips Swift 6's main-actor check.
        WindowGroup {
            RootView()
                .environmentObject(authViewModel)
        }
    }
}

/// Picks the top-level screen: splash, dashboard, onboarding, or sign-in.
struct RootView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @AppStorage("appTheme") private var appTheme: ThemeOption = .system
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

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

    var body: some View {
        ZStack {
            if authViewModel.showSplash {
                SplashView {
                    Task { await authViewModel.checkSession() }
                }
                .transition(.opacity)
            } else if authViewModel.isAuthenticated {
                DashboardView()
                    .transition(.opacity)
            } else if !hasSeenOnboarding {
                OnboardingView { hasSeenOnboarding = true }
                    .transition(.opacity)
            } else {
                SignInView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: authViewModel.isAuthenticated)
        .animation(.easeInOut(duration: 0.5), value: authViewModel.showSplash)
        .animation(.easeInOut(duration: 0.4), value: hasSeenOnboarding)
        .preferredColorScheme(appTheme.colorScheme)
    }
}
