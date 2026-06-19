import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authViewModel: AuthViewModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.appPrimary)
                        Text(authViewModel.currentUser?.fullName ?? "User")
                            .font(.headline)
                        Text(authViewModel.currentUser?.email ?? "")
                            .font(.caption)
                            .foregroundColor(.appTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                }

                Section {
                    HStack {
                        Text("Versi")
                        Spacer()
                        Text("1.0")
                            .foregroundColor(.appTextSecondary)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        authViewModel.logout()
                    } label: {
                        Label("Keluar", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Akun")
        }
    }
}
