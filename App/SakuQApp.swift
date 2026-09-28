import SwiftUI

@main
struct SakuQApp: App {
    @StateObject private var authViewModel = AuthViewModel()
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

    var body: some Scene {
        WindowGroup {
            ZStack {
                if authViewModel.showSplash {
                    SplashView {
                        Task { await authViewModel.checkSession() }
                    }
                    .transition(.opacity)
                } else if authViewModel.isAuthenticated {
                    DashboardView()
                        .environmentObject(authViewModel)
                        .transition(.opacity)
                } else if !hasSeenOnboarding {
                    OnboardingView { hasSeenOnboarding = true }
                        .transition(.opacity)
                } else {
                    SignInView()
                        .environmentObject(authViewModel)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: authViewModel.isAuthenticated)
            .animation(.easeInOut(duration: 0.5), value: authViewModel.showSplash)
            .animation(.easeInOut(duration: 0.4), value: hasSeenOnboarding)
            .preferredColorScheme(appTheme.colorScheme)
        }
    }
}
