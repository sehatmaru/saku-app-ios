import SwiftUI

/// Round initials avatar on appPrimary.
struct InitialsAvatar: View {
    let initials: String
    var size: CGFloat = 34
    var fontSize: CGFloat = 13

    var body: some View {
        Text(initials)
            .font(.app(fontSize, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.appPrimary, in: Circle())
    }
}

/// Header avatar shared by every tab; opens the profile sheet.
struct ProfileAvatarButton: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var showProfile = false

    var body: some View {
        Button { showProfile = true } label: {
            InitialsAvatar(initials: authViewModel.currentUser?.initials ?? "U")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profil")
        .sheet(isPresented: $showProfile) {
            ProfileView()
                .environmentObject(authViewModel)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}
