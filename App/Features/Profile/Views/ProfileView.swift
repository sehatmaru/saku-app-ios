import SwiftUI

/// Profil tab: account, appearance and notification settings, and sign-out.
struct ProfileView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel: ProfileViewModel

    init(viewModel: ProfileViewModel = ProfileViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    @State private var showLogoutAlert = false
    @State private var showsPayday = false
    @State private var isPaydayToastShown = false
    @State private var isPaydayFlashing = false
    /// Mirrors PaydaySetting.day (0 = not set) so the row updates when the payday changes.
    @AppStorage("paydayDay") private var paydayDay = 0

    @AppStorage("appLanguage") private var appLanguage = "id"
    @AppStorage("appTheme") private var appTheme: ThemeOption = .system
    @AppStorage("notifTransactions") private var notifTransactions = true
    @AppStorage("notifBudget") private var notifBudget = true
    @AppStorage("memberSince") private var memberSince: Double = Date().timeIntervalSince1970

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
                    ScreenHeader(title: "Profil") {}
                    profileHeader
                    SectionDivider()
                    VStack(alignment: .leading, spacing: 0) {
                        financeSection
                        appearanceSection
                        notificationSection
                        logoutButton
                        Text("Bergabung sejak \(memberSinceDate) · SakuQ versi \(appVersion)")
                            .font(.app(13))
                            .foregroundStyle(Color.appTextTertiary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 16)
                            .padding(.bottom, 32)
                    }
                    .padding(.horizontal, 24)
                }
            }
            .background(Color.appBackground)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showsPayday) {
                PaydaySheet(context: .settings) { day in
                    guard day != nil else { return }
                    isPaydayToastShown = true
                    withAnimation(.easeOut(duration: 0.2)) { isPaydayFlashing = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                        withAnimation(.easeOut(duration: 0.6)) { isPaydayFlashing = false }
                    }
                }
            }
            .toast("Tanggal gajian disimpan", isShown: $isPaydayToastShown)
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

    /// Avatar, name and email in one row, with "Ubah" to edit.
    private var profileHeader: some View {
        HStack(spacing: 16) {
            InitialsAvatar(initials: authViewModel.currentUser?.initials ?? "U", size: 64, fontSize: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(authViewModel.currentUser?.fullName ?? "User")
                    .font(.app(22, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Color.appText)
                Text(authViewModel.currentUser?.isGuest == true ? "Mode tamu" : authViewModel.currentUser?.email ?? "")
                    .font(.app(15))
                    .foregroundStyle(Color.appTextSecondary)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            NavigationLink("Ubah") { ProfileEditView(viewModel: viewModel, authViewModel: authViewModel).detailPage() }
                .font(.app(15))
                .foregroundStyle(Color.appPrimary)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 28)
    }

    // MARK: - Sections

    /// Kategori and the payday that budgets and "bulan ini" run from.
    private var financeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionCaption("Keuangan")

            NavigationLink(destination: CategoriesView()) {
                row(icon: "square.grid.2x2", title: "Kategori", subtitle: "Tambah, urutkan, sembunyikan") {
                    chevron
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())

            Button { showsPayday = true } label: {
                row(icon: "calendar", title: "Tanggal gajian", subtitle: "Awal periode budget & ringkasan") {
                    Text(paydayDay == 0 ? "Belum diatur" : "Tgl \(paydayDay)")
                        .font(.app(15))
                        .foregroundStyle(Color.appTextSecondary)
                        .contentTransition(.numericText())
                    chevron
                }
                .background(isPaydayFlashing ? Color(light: 0xE8F5EE, dark: 0x1E3A2C) : .clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .animation(.settle(0.4), value: paydayDay)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.appTextTertiary)
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionCaption("Tampilan")

            row(icon: "moon", title: "Tema") {
                Picker("Tema", selection: $appTheme) {
                    ForEach(ThemeOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            NavigationLink(destination: LanguageView(appLanguage: $appLanguage).detailPage()) {
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
            .tracking(0.2)
            .foregroundStyle(Color.appTextSecondary)
            .padding(.top, 24)
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
        .frame(minHeight: 48)
        .padding(.vertical, 2)
    }

    // MARK: - Logout

    private var logoutButton: some View {
        Button {
            showLogoutAlert = true
        } label: {
            Label("Keluar", systemImage: "rectangle.portrait.and.arrow.right")
                .font(.app(16, weight: .medium))
                .foregroundStyle(Color.appError)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .overlay(Capsule().strokeBorder(Color.appBorder))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, 28)
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
            VStack(spacing: 0) {
                // TODO: Image picker
                InitialsAvatar(initials: initials, size: 88, fontSize: 32)
                    .padding(.top, 24)
                    .padding(.bottom, 32)
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    formRow("Nama") {
                        TextField("Masukkan nama", text: $viewModel.displayName)
                            .font(.app(16))
                            .foregroundStyle(Color.appText)
                            .textContentType(.name)
                            .submitLabel(.done)
                    }
                    formRow("Email") {
                        Text(authViewModel.currentUser?.isGuest == true ? "Mode tamu" : authViewModel.currentUser?.email ?? "")
                            .font(.app(16))
                            .foregroundStyle(Color.appTextSecondary)
                            .lineLimit(1)
                    }
                }
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.appSeparator).frame(height: 1)
                }

                saveButton
                    .padding(.horizontal, 24)
                    .padding(.top, 32)
                    .padding(.bottom, 32)
            }
        }
        .background(Color.appBackground)
        .navigationTitle("Ubah Profil")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toast(isPresented: $showToast, message: toastMessage)
    }

    /// Label on the left in secondary, value on the right, hairline below.
    private func formRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.app(15))
                .foregroundStyle(Color.appTextSecondary)
                .frame(width: 76, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 52)
        .padding(.horizontal, 24)
        .rowSeparator()
    }

    private var saveButton: some View {
        Button {
            Task {
                if let updated = await viewModel.saveDisplayName(user: authViewModel.currentUser) {
                    authViewModel.currentUser = updated
                    toastMessage = "Profil berhasil disimpan"
                    withAnimation { showToast = true }
                }
            }
        } label: {
            HStack(spacing: 8) {
                if viewModel.isLoading {
                    ProgressView().tint(.white)
                }
                Text("Simpan")
                    .font(.app(16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.appPrimary, in: Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(viewModel.isLoading)
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
        ScrollView {
            VStack(spacing: 0) {
                ForEach(options, id: \.code) { option in
                    Button {
                        appLanguage = option.code
                    } label: {
                        HStack(spacing: 14) {
                            Text(option.flag)
                                .font(.system(size: 22))
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.native)
                                    .font(.app(16))
                                    .foregroundStyle(Color.appText)
                                Text(option.name)
                                    .font(.app(13))
                                    .foregroundStyle(Color.appTextSecondary)
                            }
                            Spacer()
                            if appLanguage == option.code {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color.appPrimary)
                            }
                        }
                        .frame(minHeight: 60)
                        .padding(.horizontal, 24)
                        .rowSeparator()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityAddTraits(appLanguage == option.code ? .isSelected : [])
                }
            }
            .padding(.top, 8)
        }
        .background(Color.appBackground)
        .navigationTitle("Bahasa")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}
