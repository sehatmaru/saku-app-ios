import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var selectedMenu: MenuItem?

    enum MenuItem: String, Identifiable {
        case profil, bahasa, tema, notifikasi

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .profil: return "person.fill"
            case .bahasa: return "globe"
            case .tema: return "moon.fill"
            case .notifikasi: return "bell.fill"
            }
        }

        var title: String {
            switch self {
            case .profil: return "Profil"
            case .bahasa: return "Bahasa"
            case .tema: return "Tema"
            case .notifikasi: return "Notifikasi"
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "person.circle.fill")
                            .font(.jakarta(60))
                            .foregroundColor(.appPrimary)
                        Text(authViewModel.currentUser?.displayName ?? "User")
                            .font(.jakarta(17, weight: .semibold))
                        Text(authViewModel.currentUser?.email ?? "")
                            .font(.jakarta(12))
                            .foregroundColor(.appTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                    .overlay(alignment: .topTrailing) {
                        Text(appVersion)
                            .font(.jakarta(11))
                            .foregroundColor(.appTextSecondary)
                    }
                }

                Section {
                    ForEach([MenuItem.profil, .bahasa, .tema, .notifikasi]) { item in
                        Button {
                            selectedMenu = item
                        } label: {
                            Label(item.title, systemImage: item.icon)
                                .font(.jakarta(15))
                        }
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
            .alert("Segera Hadir", isPresented: .init(
                get: { selectedMenu != nil },
                set: { if !$0 { selectedMenu = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Fitur \(selectedMenu?.title ?? "") akan segera tersedia.")
            }
        }
    }
}
