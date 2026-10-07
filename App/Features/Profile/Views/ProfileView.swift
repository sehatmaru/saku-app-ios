import SwiftUI
import PhotosUI

/// Profil tab: account, appearance and notification settings, and sign-out.
struct ProfileView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel: ProfileViewModel

    /// Today's cash and assets, for the previews in the "Total saldo di Beranda" sheet.
    var cash: Double = 0
    var assets: Double = 0

    init(viewModel: ProfileViewModel = ProfileViewModel(), cash: Double = 0, assets: Double = 0) {
        self.cash = cash
        self.assets = assets
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    @State private var showLogoutAlert = false
    @State private var showResetAlert = false
    @State private var isResetting = false
    @State private var resetError: String?
    @State private var showsPayday = false
    @State private var isCancellingPayday = false
    @State private var isPaydayToastShown = false
    @State private var isPaydayFlashing = false
    /// Mirrors PaydaySetting.day (0 = not set) so the row updates when the payday changes.
    @AppStorage("paydayDay") private var paydayDay = 0
    /// Mirrors PaydaySetting.schedule so the pending-change banner follows it.
    @AppStorage("paydaySchedule") private var paydaySchedule = Data()

    @State private var showsHomeBalance = false
    @State private var showsTheme = false
    @State private var showsLanguage = false
    @State private var homeBalanceFailed = false
    @AppStorage(HomeBalanceSetting.key) private var homeBalanceMode = HomeBalanceMode.cash.rawValue

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
        formatter.locale = AppLanguage.locale
        return formatter.string(from: date)
    }

    private var languageLabel: String {
        appLanguage == "id" ? "Indonesia" : "English"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ScreenHeader(title: L("Profil")) {}
                    profileHeader
                    SectionDivider()
                    VStack(alignment: .leading, spacing: 0) {
                        financeSection
                        appearanceSection
                        notificationSection
                        if DevTools.isAccountResetEnabled { developmentSection }
                        logoutButton
                        Text("Bergabung sejak \(memberSinceDate) · Saku versi \(appVersion)")
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
            .sheet(isPresented: $showsHomeBalance) {
                HomeBalanceSheet(selection: homeBalanceMode, cash: cash, assets: assets) { mode in
                    showsHomeBalance = false
                    saveHomeBalance(mode)
                }
            }
            .sheet(isPresented: $showsTheme) {
                OptionSheet(title: L("Tema"), selection: appTheme,
                            options: ThemeOption.allCases.map { ($0, L($0.rawValue), nil) }) { appTheme = $0 }
            }
            .sheet(isPresented: $showsLanguage) {
                OptionSheet(title: L("Bahasa"), selection: appLanguage,
                            options: [("id", "Bahasa Indonesia", "Indonesian"), ("en", "English", "English")]) { code in
                    guard code != appLanguage else { return }
                    // Cached dashboard state holds pre-rendered text (health tips, month labels).
                    AppDataCache.shared.clearAll()
                    appLanguage = code
                }
            }
            .alert("Gagal menyimpan", isPresented: $homeBalanceFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Gagal menyimpan. Coba lagi.")
            }
            .toast(L("Tanggal gajian disimpan"), isShown: $isPaydayToastShown)
            .onAppear {
                viewModel.loadProfile(from: authViewModel.currentUser)
            }
            .alert("Hapus akun dan semua data?", isPresented: $showResetAlert) {
                Button("Batal", role: .cancel) {}
                Button("Hapus semua", role: .destructive) { resetAccount() }
            } message: {
                Text("Akun dan semua datamu dihapus permanen, lalu kamu kembali ke awal. Tidak bisa dibatalkan.")
            }
            .alert("Gagal menghapus akun", isPresented: Binding(get: { resetError != nil }, set: { if !$0 { resetError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(resetError ?? "")
            }
            .overlay {
                if isResetting {
                    ZStack {
                        Color.black.opacity(0.3).ignoresSafeArea()
                        ProgressView("Menghapus…")
                            .padding(24)
                            .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isResetting)
            .alert("Keluar", isPresented: $showLogoutAlert) {
                Button("Batal", role: .cancel) {}
                Button("Keluar", role: .destructive) {
                    authViewModel.logout()
                }
            } message: {
                Text(authViewModel.currentUser?.isGuest == true
                     ? L("Kamu masuk sebagai tamu. Setelah keluar, data di akun tamu ini tidak bisa dibuka lagi.")
                     : L("Kamu akan keluar. Datamu tetap tersimpan."))
            }
        }
    }

    // MARK: - Header

    /// Avatar, name and email in one row, with "Ubah" to edit.
    private var profileHeader: some View {
        HStack(spacing: 16) {
            InitialsAvatar(initials: authViewModel.currentUser?.initials ?? "U", size: 64, fontSize: 24,
                           image: authViewModel.avatarImage)
            VStack(alignment: .leading, spacing: 3) {
                Text(authViewModel.currentUser?.fullName ?? "User")
                    .font(.app(22, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Color.appText)
                Text(authViewModel.currentUser?.isGuest == true ? L("Mode tamu") : authViewModel.currentUser?.email ?? "")
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
            sectionCaption(L("Keuangan"))

            NavigationLink(destination: CategoriesView()) {
                row(icon: "square.grid.2x2", title: L("Kategori"), subtitle: L("Tambah, ubah, sembunyikan")) {
                    chevron
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())

            Button { showsPayday = true } label: {
                row(icon: "calendar", title: L("Tanggal gajian"), subtitle: L("Awal periode budget")) {
                    Text(paydayDay == 0 ? L("Belum diatur") : L("Tgl %lld", paydayDay))
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

            if let pending = pendingPayday {
                HStack(spacing: 8) {
                    Text(L("Gajian pindah ke tanggal %lld mulai %@.", pending.day, PaydayCycle.dayMonth.string(from: pending.from)))
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                    Spacer(minLength: 8)
                    if isCancellingPayday {
                        ProgressView()
                    } else {
                        Button(L("Batalkan")) { cancelPendingPayday() }
                            .font(.app(13, weight: .semibold))
                            .foregroundStyle(Color.appPrimary)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var pendingPayday: PaydayEntry? {
        _ = paydaySchedule
        return PaydayCycle.current.pending
    }

    private func cancelPendingPayday() {
        isCancellingPayday = true
        Task {
            try? await SupabaseSDK.cancelPendingPayday()
            isCancellingPayday = false
            NotificationCenter.default.post(name: .dataDidChange, object: nil)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.appTextTertiary)
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionCaption(L("Tampilan"))

            Button { showsTheme = true } label: {
                row(icon: "moon", title: L("Tema")) {
                    Text(LocalizedStringKey(appTheme.rawValue))
                        .font(.app(15))
                        .foregroundStyle(Color.appTextSecondary)
                    chevron
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())

            Button { showsLanguage = true } label: {
                row(icon: "globe", title: L("Bahasa")) {
                    Text(languageLabel)
                        .font(.app(15))
                        .foregroundStyle(Color.appTextSecondary)
                    chevron
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())

            Button { showsHomeBalance = true } label: {
                row(icon: "house", title: L("Total saldo di Beranda")) {
                    Text(homeBalanceMode == HomeBalanceMode.all.rawValue ? L("Kas + aset") : L("Kas saja"))
                        .font(.app(15))
                        .foregroundStyle(Color.appTextSecondary)
                    chevron
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
        }
    }

    /// Optimistic: the mirror flips at once so Beranda follows; the profile row is rolled back if the save fails.
    private func saveHomeBalance(_ mode: HomeBalanceMode) {
        guard mode.rawValue != homeBalanceMode,
              let id = authViewModel.currentUser.flatMap({ UUID(uuidString: $0.id) }) else { return }
        let previous = homeBalanceMode
        homeBalanceMode = mode.rawValue
        Task {
            do {
                try await SupabaseSDK.updateHomeBalanceMode(profileId: id, mode: mode)
            } catch {
                homeBalanceMode = previous
                homeBalanceFailed = true
            }
        }
    }

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionCaption(L("Notifikasi"))
            row(icon: "arrow.left.arrow.right", title: L("Transaksi baru"), subtitle: L("Tiap ada transaksi")) {
                Toggle("Transaksi baru", isOn: $notifTransactions)
                    .labelsHidden()
                    .tint(.appPrimary)
            }
            row(icon: "chart.pie", title: L("Budget hampir habis"), subtitle: L("Saat mencapai 80%")) {
                Toggle("Budget hampir habis", isOn: $notifBudget)
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

    private func row<Trailing: View>(icon: String, title: String, subtitle: String? = nil, isDestructive: Bool = false, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 19))
                .foregroundStyle(isDestructive ? Color.appError : Color.appTextSecondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.app(16))
                    .foregroundStyle(isDestructive ? Color.appError : Color.appText)
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

    /// Only while the app is in development and testing (see `DevTools`).
    private var developmentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionCaption(L("Pengembangan"))
            Button { showResetAlert = true } label: {
                row(icon: "trash", title: L("Hapus akun & data"), subtitle: L("Hanya uji coba: hapus akun dan data"), isDestructive: true) {
                    chevron
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .disabled(isResetting)
        }
    }

    private func resetAccount() {
        isResetting = true
        Task {
            let ok = await authViewModel.deleteAccountAndData()
            isResetting = false
            if !ok { resetError = authViewModel.errorMessage ?? L("Coba lagi.") }
        }
    }

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
    @State private var pickerItem: PhotosPickerItem?
    @State private var newPhoto: UIImage?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    InitialsAvatar(initials: initials, size: 88, fontSize: 32,
                                   image: newPhoto ?? authViewModel.avatarImage)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.appPrimary, in: Circle())
                                .overlay(Circle().strokeBorder(Color.appBackground, lineWidth: 2))
                        }
                }
                .accessibilityLabel("Ubah foto profil")
                .padding(.top, 24)
                .padding(.bottom, 32)
                .onChange(of: pickerItem) { _, item in
                    Task {
                        guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                        newPhoto = UIImage(data: data)
                    }
                }

                VStack(spacing: 0) {
                    formRow(L("Nama")) {
                        TextField("Masukkan nama", text: $viewModel.displayName)
                            .font(.app(16))
                            .foregroundStyle(Color.appText)
                            .textContentType(.name)
                            .submitLabel(.done)
                    }
                    formRow("Email") {
                        Text(authViewModel.currentUser?.isGuest == true ? L("Mode tamu") : authViewModel.currentUser?.email ?? "")
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
                if let updated = await viewModel.saveProfile(user: authViewModel.currentUser, photo: newPhoto) {
                    authViewModel.currentUser = updated
                    if let newPhoto { authViewModel.avatarImage = newPhoto }
                    self.newPhoto = nil
                    toastMessage = L("Profil berhasil disimpan")
                    withAnimation { showToast = true }
                } else if let error = viewModel.errorMessage {
                    toastMessage = error
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

// MARK: - Total saldo di Beranda

/// Two options, each with a one-line explanation and a small preview of the Beranda number.
private struct HomeBalanceSheet: View {
    let selection: String
    let cash: Double
    let assets: Double
    let onPick: (HomeBalanceMode) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Text("Total saldo di Beranda").font(.app(17, weight: .semibold))
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.appTextSecondary)
                            .frame(width: 30, height: 30)
                            .background(Color.appFill, in: Circle())
                    }
                    .accessibilityLabel(L("Tutup"))
                }
            }
            .padding(.top, 14)

            VStack(spacing: 12) {
                option(.cash, title: L("Kas saja"), detail: L("Rekening, e-wallet, dan tunai."),
                       big: cash, sub: L("Belum termasuk aset %@", assets.formattedAsCurrency()))
                option(.all, title: L("Kas + aset"), detail: L("Nilai dompet investasi ikut dijumlahkan."),
                       big: cash + assets, sub: L("Kas %@ + aset %@", cash.formattedAsCurrency(), assets.formattedAsCurrency()))
            }
            .padding(.top, 22)

            Text("Hanya mengubah angka di Beranda. Dompet tetap menampilkan kas dan aset terpisah.")
                .font(.app(13))
                .foregroundStyle(Color.appTextSecondary)
                .padding(.top, 16)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .foregroundStyle(Color.appText)
        .presentationDetents([.height(520)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(Color.appBackground)
    }

    private func option(_ mode: HomeBalanceMode, title: String, detail: String, big: Double, sub: String) -> some View {
        let on = selection == mode.rawValue
        return Button { onPick(mode); dismiss() } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(on ? Color.appPrimary : Color.appTextTertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.app(16, weight: .medium))
                        Text(detail).font(.app(13)).foregroundStyle(Color.appTextSecondary)
                    }
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total saldo").font(.app(11)).foregroundStyle(Color.appTextSecondary)
                    Text(big.formattedAsCurrency()).font(.app(26, weight: .ultraLight)).monospacedDigit()
                    Text(sub).font(.app(11)).foregroundStyle(Color.appTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.appFill, in: RoundedRectangle(cornerRadius: 12))
                .padding(.leading, 34)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(on ? Color.appPrimary : Color.appBorder, lineWidth: on ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}


// MARK: - Option sheet

/// Theme and language: a short list, tap a row to pick it and close.
private struct OptionSheet<Value: Equatable>: View {
    let title: String
    let selection: Value
    let options: [(value: Value, title: String, subtitle: String?)]
    let onPick: (Value) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Text(title).font(.app(17, weight: .semibold))
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.appTextSecondary)
                            .frame(width: 30, height: 30)
                            .background(Color.appFill, in: Circle())
                    }
                    .accessibilityLabel(L("Tutup"))
                }
            }
            .padding(.top, 14)

            VStack(spacing: 0) {
                ForEach(options.indices, id: \.self) { i in
                    let option = options[i]
                    let on = option.value == selection
                    Button { onPick(option.value); dismiss() } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title).font(.app(16))
                                if let subtitle = option.subtitle {
                                    Text(subtitle).font(.app(13)).foregroundStyle(Color.appTextSecondary)
                                }
                            }
                            Spacer()
                            if on {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color.appPrimary)
                            }
                        }
                        .frame(minHeight: 56)
                        .rowSeparator()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.top, 12)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .foregroundStyle(Color.appText)
        .presentationDetents([.height(CGFloat(options.count) * 56 + 110)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(Color.appBackground)
    }
}
