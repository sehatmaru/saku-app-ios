import SwiftUI

@main
struct SakuQApp: App {
    @StateObject private var authViewModel = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            ZStack {
                if authViewModel.showSplash {
                    SplashView {
                        authViewModel.dismissSplash()
                    }
                    .transition(.opacity)
                } else if authViewModel.isAuthenticated {
                    DashboardView()
                        .environmentObject(authViewModel)
                        .transition(.opacity)
                } else {
                    SignInView()
                        .environmentObject(authViewModel)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: authViewModel.isAuthenticated)
            .animation(.easeInOut(duration: 0.5), value: authViewModel.showSplash)
        }
    }
}
