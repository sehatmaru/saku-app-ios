import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel = ProfileViewModel()
    @State private var showLogoutAlert = false

    @AppStorage("appLanguage") private var appLanguage = "id"
    @AppStorage("appTheme") private var appTheme: ThemeOption = .system
    @AppStorage("notifTransactions") private var notifTransactions = true
    @AppStorage("notifBudget") private var notifBudget = true
    @AppStorage("memberSince") private var memberSince: Double = Date().timeIntervalSince1970

    enum ThemeOption: String, CaseIterable {
        case light = "Terang"
        case dark = "Gelap"
        case system = "Sistem"

        var icon: String {
            switch self {
            case .light: return "sun.max.fill"
            case .dark: return "moon.fill"
            case .system: return "iphone"
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var memberSinceDate: String {
        let date = Date(timeIntervalSince1970: memberSince)
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = Locale(identifier: "id_ID")
        return formatter.string(from: date)
    }

    private var userInitials: String {
        let name = authViewModel.currentUser?.displayName ?? "U"
        let parts = name.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)).uppercased() }.joined()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    profileHeader
                    menuSection
                    dangerSection
                }
                .padding()
            }
            .background(Color.appGroupedBackground)
            .navigationTitle("Akun")
            .onAppear {
                viewModel.loadProfile(from: authViewModel.currentUser)
            }
            .alert("Keluar", isPresented: $showLogoutAlert) {
                Button("Batal", role: .cancel) {}
                Button("Keluar", role: .destructive) {
                    authViewModel.logout()
                }
            } message: {
                Text("Anda akan keluar dari akun. Data tetap tersimpan.")
            }
        }
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        HStack(spacing: Spacing.lg) {
            ZStack {
                LinearGradient(
                    colors: [.appPrimary, .appPrimary.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 20))

                Text(userInitials)
                    .font(.jakarta(26, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(authViewModel.currentUser?.displayName ?? "User")
                    .font(.jakarta(18, weight: .bold))
                    .foregroundColor(.appText)

                HStack(spacing: 4) {
                    Image(systemName: "envelope.fill")
                        .font(.jakarta(9))
                        .foregroundColor(.appTextSecondary)
                    Text(authViewModel.currentUser?.email ?? "")
                        .font(.jakarta(12))
                        .foregroundColor(.appTextSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.appCardBackground))
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 2) {
                Text("Bergabung Sejak")
                    .font(.jakarta(8, weight: .medium))
                    .foregroundColor(.appTextSecondary.opacity(0.5))

                Text(memberSinceDate)
                    .font(.jakarta(10, weight: .semibold))
                    .foregroundColor(.appTextSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.appTextSecondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.appTextSecondary.opacity(0.1), lineWidth: 0.5)
            )
            .padding(Spacing.sm)
        }
    }

    // MARK: - Menu Section

    private var menuSection: some View {
        VStack(spacing: 0) {
            NavigationLink(destination: ProfileEditView(viewModel: viewModel, authViewModel: authViewModel)) {
                menuRow(icon: "person.fill", title: "Profil", subtitle: "Nama dan informasi akun", iconColor: .appPrimary)
            }

            menuDivider

            NavigationLink(destination: LanguageView(appLanguage: $appLanguage)) {
                menuRow(icon: "globe", title: "Bahasa", subtitle: languageLabel, iconColor: .blue)
            }

            menuDivider

            NavigationLink(destination: ThemeView(appTheme: $appTheme)) {
                menuRow(icon: "moon.fill", title: "Tema", subtitle: appTheme.rawValue, iconColor: .purple)
            }

            menuDivider

            NavigationLink(destination: NotificationView(
                notifTransactions: $notifTransactions,
                notifBudget: $notifBudget
            )) {
                menuRow(icon: "bell.fill", title: "Notifikasi", subtitle: notifLabel, iconColor: .appWarning)
            }
        }
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.appCardBackground))
    }

    private var menuDivider: some View {
        Divider()
            .padding(.leading, 56)
    }

    private func menuRow(icon: String, title: String, subtitle: String, iconColor: Color) -> some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.jakarta(14, weight: .semibold))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.jakarta(15, weight: .medium))
                    .foregroundColor(.appText)
                Text(subtitle)
                    .font(.jakarta(11))
                    .foregroundColor(.appTextSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.jakarta(10))
                .foregroundColor(.appTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 14)
    }

    // MARK: - Danger Section

    private var dangerSection: some View {
        VStack(spacing: 0) {
            Button(role: .destructive) {
                showLogoutAlert = true
            } label: {
                HStack(spacing: Spacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.appError.opacity(0.12))
                            .frame(width: 36, height: 36)
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.jakarta(14, weight: .semibold))
                            .foregroundColor(.appError)
                    }

                    Text("Keluar")
                        .font(.jakarta(15, weight: .medium))
                        .foregroundColor(.appError)

                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
        }
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.appCardBackground))
    }

    // MARK: - Labels

    private var languageLabel: String {
        appLanguage == "id" ? "Indonesia" : "English"
    }

    private var notifLabel: String {
        let labels = [
            notifTransactions ? "Transaksi" : nil,
            notifBudget ? "Budget" : nil
        ].compactMap { $0 }
        return labels.isEmpty ? "Nonaktif" : labels.joined(separator: ", ")
    }
}

// MARK: - Profile Edit

struct ProfileEditView: View {
    @ObservedObject var viewModel: ProfileViewModel
    @ObservedObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showToast = false
    @State private var toastMessage = ""

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                VStack(spacing: Spacing.sm) {
                    Button {
                        // TODO: Image picker
                    } label: {
                        ZStack {
                            LinearGradient(
                                colors: [.appPrimary, .appPrimary.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 22))

                            Text(initials)
                                .font(.jakarta(28, weight: .bold))
                                .foregroundColor(.white)

                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white)
                                        .padding(6)
                                        .background(Color.black.opacity(0.45))
                                        .clipShape(Circle())
                                        .offset(x: 2, y: 2)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Text("Ubah Profil")
                        .font(.jakarta(17, weight: .semibold))
                        .foregroundColor(.appText)
                }
                .padding(.top, Spacing.xl)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Nama Tampilan")
                        .font(.jakarta(12))
                        .foregroundColor(.appTextSecondary)

                    TextField("Masukkan nama", text: $viewModel.displayName)
                        .font(.jakarta(17))
                        .padding()
                        .background(Color.appGroupedBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, Spacing.xl)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Email")
                        .font(.jakarta(12))
                        .foregroundColor(.appTextSecondary)

                    Text(authViewModel.currentUser?.email ?? "")
                        .font(.jakarta(15))
                        .foregroundColor(.appTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.appGroupedBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, Spacing.xl)

                Spacer()

                Button {
                    Task {
                        if let updated = await viewModel.saveDisplayName(user: authViewModel.currentUser) {
                            authViewModel.currentUser = updated
                            toastMessage = "Profil berhasil disimpan"
                            withAnimation { showToast = true }
                        }
                    }
                } label: {
                    HStack(spacing: Spacing.sm) {
                        if viewModel.isLoading {
                            ProgressView()
                                .tint(.white)
                        }
                        Text("Simpan")
                            .font(.jakarta(17, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.appPrimary)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(viewModel.isLoading)
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.xl)
            }
        }
        .background(Color.appGroupedBackground)
        .navigationTitle("Profil")
        .navigationBarTitleDisplayMode(.inline)
        .toast(isPresented: $showToast, message: toastMessage)
    }

    private var initials: String {
        let name = authViewModel.currentUser?.displayName ?? "U"
        let parts = name.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)).uppercased() }.joined()
    }
}

// MARK: - Language

struct LanguageView: View {
    @Binding var appLanguage: String
    @Environment(\.dismiss) private var dismiss

    private let options: [(code: String, name: String, native: String, flag: String)] = [
        ("id", "Indonesian", "Bahasa Indonesia", "🇮🇩"),
        ("en", "English", "English", "🇺🇸"),
    ]

    var body: some View {
        List {
            ForEach(options, id: \.code) { option in
                Button {
                    appLanguage = option.code
                } label: {
                    HStack(spacing: Spacing.md) {
                        Text(option.flag)
                            .font(.system(size: 28))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.name)
                                .font(.jakarta(15, weight: .medium))
                                .foregroundColor(.appText)
                            Text(option.native)
                                .font(.jakarta(12))
                                .foregroundColor(.appTextSecondary)
                        }

                        Spacer()

                        if appLanguage == option.code {
                            Image(systemName: "checkmark")
                                .font(.jakarta(14, weight: .semibold))
                                .foregroundColor(.appPrimary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.insetGrouped)
        .background(Color.appGroupedBackground)
        .scrollContentBackground(.hidden)
        .navigationTitle("Bahasa")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Theme

struct ThemeView: View {
    @Binding var appTheme: ProfileView.ThemeOption
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(ProfileView.ThemeOption.allCases, id: \.rawValue) { theme in
                Button {
                    appTheme = theme
                } label: {
                    HStack(spacing: Spacing.md) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.appPrimary.opacity(0.12))
                                .frame(width: 40, height: 40)
                            Image(systemName: theme.icon)
                                .font(.jakarta(16))
                                .foregroundColor(.appPrimary)
                        }

                        Text(theme.rawValue)
                            .font(.jakarta(15, weight: .medium))
                            .foregroundColor(.appText)

                        Spacer()

                        if appTheme == theme {
                            Image(systemName: "checkmark")
                                .font(.jakarta(14, weight: .semibold))
                                .foregroundColor(.appPrimary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.insetGrouped)
        .background(Color.appGroupedBackground)
        .scrollContentBackground(.hidden)
        .navigationTitle("Tema")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Notifications

struct NotificationView: View {
    @Binding var notifTransactions: Bool
    @Binding var notifBudget: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                notifRow(
                    icon: "arrow.left.arrow.right",
                    title: "Transaksi",
                    subtitle: "Pengingat mencatat transaksi harian",
                    isOn: $notifTransactions
                )

                notifRow(
                    icon: "chart.pie.fill",
                    title: "Budget",
                    subtitle: "Peringatan saat budget mendekati batas",
                    isOn: $notifBudget
                )
            }
        }
        .listStyle(.insetGrouped)
        .background(Color.appGroupedBackground)
        .scrollContentBackground(.hidden)
        .navigationTitle("Notifikasi")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func notifRow(icon: String, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.appPrimary.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.jakarta(14, weight: .semibold))
                    .foregroundColor(.appPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.jakarta(15, weight: .medium))
                    .foregroundColor(.appText)
                Text(subtitle)
                    .font(.jakarta(11))
                    .foregroundColor(.appTextSecondary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .tint(.appPrimary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    ProfileView()
        .environmentObject(AuthViewModel())
}
