import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel: ProfileViewModel

    init(viewModel: ProfileViewModel = ProfileViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    @State private var showLogoutAlert = false

    @AppStorage("appLanguage") private var appLanguage = "id"
    @AppStorage("appTheme") private var appTheme: ThemeOption = .system
    @AppStorage("notifTransactions") private var notifTransactions = true
    @AppStorage("notifBudget") private var notifBudget = true
    @AppStorage("memberSince") private var memberSince: Double = Date().timeIntervalSince1970
    @AppStorage("isBalanceVisible") private var isBalanceVisible = true

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
                VStack(alignment: .leading, spacing: 0) {
                    ScreenHeader(title: "Profil") { EmptyView() }
                    profileHeader
                    preferences
                    logoutRow
                    Text("SakuQ versi \(appVersion)")
                        .font(.app(13))
                        .foregroundStyle(Color.appTextTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                }
            }
            .background(Color.appBackground)
            .toolbar(.hidden, for: .navigationBar)
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
        NavigationLink(destination: ProfileEditView(viewModel: viewModel, authViewModel: authViewModel)) {
            HStack(spacing: 16) {
                Text(userInitials)
                    .font(.app(24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Color.appPrimary, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(authViewModel.currentUser?.displayName ?? "User")
                        .font(.app(22, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(Color.appText)
                        .lineLimit(1)
                    Text(authViewModel.currentUser?.email ?? "")
                        .font(.app(15))
                        .foregroundStyle(Color.appTextSecondary)
                        .lineLimit(1)
                    Text("Bergabung sejak \(memberSinceDate)")
                        .font(.app(13))
                        .foregroundStyle(Color.appTextTertiary)
                }

                Spacer(minLength: 8)
                chevron
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }

    // MARK: - Preferences

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Preferensi")
                .font(.app(13))
                .tracking(0.2)
                .foregroundStyle(Color.appTextSecondary)
                .padding(.top, 24)
                .padding(.bottom, 4)

            NavigationLink(destination: LanguageView(appLanguage: $appLanguage)) {
                settingRow(icon: "globe", title: "Bahasa", value: languageLabel)
            }
            .buttonStyle(RowPressStyle())

            NavigationLink(destination: ThemeView(appTheme: $appTheme)) {
                settingRow(icon: "moon", title: "Tema", value: appTheme.rawValue)
            }
            .buttonStyle(RowPressStyle())

            NavigationLink(destination: NotificationView(
                notifTransactions: $notifTransactions,
                notifBudget: $notifBudget
            )) {
                settingRow(icon: "bell", title: "Notifikasi", value: notifLabel)
            }
            .buttonStyle(RowPressStyle())

            HStack(spacing: 14) {
                rowIcon("eye.slash")
                Toggle("Sembunyikan saldo", isOn: Binding(
                    get: { !isBalanceVisible },
                    set: { hidden in withAnimation(.smooth) { isBalanceVisible = !hidden } }
                ))
                .font(.app(16))
                .foregroundStyle(Color.appText)
                .tint(.appPrimary)
            }
            .padding(.vertical, 10)
            .rowSeparator()
        }
        .padding(.horizontal, 24)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.appDivider).frame(height: 1).padding(.horizontal, 24)
        }
    }

    private func settingRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 14) {
            rowIcon(icon)
            Text(title)
                .font(.app(16))
                .foregroundStyle(Color.appText)
            Spacer(minLength: 8)
            Text(value)
                .font(.app(15))
                .foregroundStyle(Color.appTextSecondary)
                .lineLimit(1)
            chevron
        }
        .padding(.vertical, 14)
        .rowSeparator()
        .contentShape(Rectangle())
    }

    private func rowIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 19))
            .foregroundStyle(Color.appTextSecondary)
            .frame(width: 24)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.appTextTertiary)
    }

    // MARK: - Logout

    private var logoutRow: some View {
        Button {
            showLogoutAlert = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 19))
                    .frame(width: 24)
                Text("Keluar")
                    .font(.app(16))
                Spacer()
            }
            .foregroundStyle(Color.appError)
            .padding(.vertical, 14)
            .overlay(alignment: .top) { Rectangle().fill(Color.appSeparator).frame(height: 1) }
            .rowSeparator()
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .padding(.horizontal, 24)
        .padding(.top, 28)
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
                                .font(.app(28, weight: .bold))
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
                        .font(.app(17, weight: .semibold))
                        .foregroundColor(.appText)
                }
                .padding(.top, Spacing.xl)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Nama Tampilan")
                        .font(.app(12))
                        .foregroundColor(.appTextSecondary)

                    TextField("Masukkan nama", text: $viewModel.displayName)
                        .font(.app(17))
                        .padding()
                        .background(Color.appGroupedBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, Spacing.xl)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Email")
                        .font(.app(12))
                        .foregroundColor(.appTextSecondary)

                    Text(authViewModel.currentUser?.email ?? "")
                        .font(.app(15))
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
                            .font(.app(17, weight: .semibold))
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
                                .font(.app(15, weight: .medium))
                                .foregroundColor(.appText)
                            Text(option.native)
                                .font(.app(12))
                                .foregroundColor(.appTextSecondary)
                        }

                        Spacer()

                        if appLanguage == option.code {
                            Image(systemName: "checkmark")
                                .font(.app(14, weight: .semibold))
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
                                .font(.app(16))
                                .foregroundColor(.appPrimary)
                        }

                        Text(theme.rawValue)
                            .font(.app(15, weight: .medium))
                            .foregroundColor(.appText)

                        Spacer()

                        if appTheme == theme {
                            Image(systemName: "checkmark")
                                .font(.app(14, weight: .semibold))
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
                    .font(.app(14, weight: .semibold))
                    .foregroundColor(.appPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.app(15, weight: .medium))
                    .foregroundColor(.appText)
                Text(subtitle)
                    .font(.app(11))
                    .foregroundColor(.appTextSecondary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .tint(.appPrimary)
        }
        .padding(.vertical, 2)
    }
}
