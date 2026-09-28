import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
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

    private var languageLabel: String {
        appLanguage == "id" ? "Indonesia" : "English"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    profileHeader
                    appearanceSection
                    notificationSection
                    logoutButton
                    Text("Bergabung sejak \(memberSinceDate) · SakuQ versi \(appVersion)")
                        .font(.app(13))
                        .foregroundStyle(Color.appTextTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
                .padding(.horizontal, 24)
            }
            .background(Color.appBackground)
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Selesai") { dismiss() }
                        .font(.app(17, weight: .semibold))
                        .foregroundStyle(Color.appPrimary)
                }
            }
            .onAppear {
                viewModel.loadProfile(from: authViewModel.currentUser)
            }
            .alert("Keluar", isPresented: $showLogoutAlert) {
                Button("Batal", role: .cancel) {}
                Button("Keluar", role: .destructive) {
                    authViewModel.logout()
                }
            } message: {
                Text(authViewModel.currentUser?.isGuest == true
                     ? "Kamu masuk sebagai tamu. Setelah keluar, data di akun tamu ini tidak bisa dibuka lagi."
                     : "Anda akan keluar dari akun. Data tetap tersimpan.")
            }
        }
    }

    // MARK: - Header

    private var profileHeader: some View {
        VStack(spacing: 0) {
            InitialsAvatar(initials: authViewModel.currentUser?.initials ?? "U", size: 88, fontSize: 32)
            Text(authViewModel.currentUser?.fullName ?? "User")
                .font(.app(24, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(Color.appText)
                .lineLimit(1)
                .padding(.top, 14)
            Text(authViewModel.currentUser?.isGuest == true ? "Mode tamu" : authViewModel.currentUser?.email ?? "")
                .font(.app(15))
                .foregroundStyle(Color.appTextSecondary)
                .lineLimit(1)
                .padding(.top, 4)
            NavigationLink(destination: ProfileEditView(viewModel: viewModel, authViewModel: authViewModel)) {
                Label("Ubah profil", systemImage: "pencil")
                    .font(.app(15, weight: .medium))
                    .foregroundStyle(Color.appText)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(Color.appFill, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    // MARK: - Sections

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionCaption("Tampilan")

            row(icon: "circle.lefthalf.filled", title: "Tema") {
                Picker("Tema", selection: $appTheme) {
                    ForEach(ThemeOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            NavigationLink(destination: LanguageView(appLanguage: $appLanguage)) {
                row(icon: "globe", title: "Bahasa") {
                    Text(languageLabel)
                        .font(.app(15))
                        .foregroundStyle(Color.appTextSecondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.appTextTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())

            row(icon: "eye.slash", title: "Sembunyikan saldo") {
                Toggle("Sembunyikan saldo", isOn: Binding(
                    get: { !isBalanceVisible },
                    set: { hidden in withAnimation(.smooth) { isBalanceVisible = !hidden } }
                ))
                .labelsHidden()
                .tint(.appPrimary)
            }
        }
    }

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionCaption("Notifikasi")
            row(icon: "arrow.left.arrow.right", title: "Transaksi", subtitle: "Setiap ada transaksi baru") {
                Toggle("Transaksi", isOn: $notifTransactions)
                    .labelsHidden()
                    .tint(.appPrimary)
            }
            row(icon: "chart.pie", title: "Budget", subtitle: "Saat pemakaian mencapai 80%") {
                Toggle("Budget", isOn: $notifBudget)
                    .labelsHidden()
                    .tint(.appPrimary)
            }
        }
    }

    private func sectionCaption(_ title: String) -> some View {
        Text(title)
            .font(.app(13))
            .foregroundStyle(Color.appTextSecondary)
            .padding(.top, 28)
            .padding(.bottom, 4)
    }

    private func row<Trailing: View>(icon: String, title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 19))
                .foregroundStyle(Color.appTextSecondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.app(16))
                    .foregroundStyle(Color.appText)
                if let subtitle {
                    Text(subtitle)
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .frame(minHeight: 52)
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.appDivider).frame(height: 1)
        }
    }

    // MARK: - Logout

    private var logoutButton: some View {
        Button {
            showLogoutAlert = true
        } label: {
            Label("Keluar", systemImage: "rectangle.portrait.and.arrow.right")
                .font(.app(16, weight: .semibold))
                .foregroundStyle(Color.appError)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.appError.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, 32)
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

                    Text(authViewModel.currentUser?.isGuest == true ? "Mode tamu" : authViewModel.currentUser?.email ?? "")
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
