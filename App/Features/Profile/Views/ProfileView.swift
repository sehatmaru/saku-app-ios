import SwiftUI
import PhotosUI

/// Profil tab: account, appearance and notification settings, and sign-out.
struct ProfileView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel: ProfileViewModel
    @ObservedObject private var plus = PlusStore.shared

    /// Today's cash and assets, for the previews in the "Total saldo di Beranda" sheet.
    var cash: Double = 0
    var assets: Double = 0

    init(viewModel: ProfileViewModel = ProfileViewModel(), cash: Double = 0, assets: Double = 0) {
        self.cash = cash
        self.assets = assets
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    @State private var showLogoutAlert = false
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

    /// The free card's "Coba Saku Plus" opens the paywall with the general pitch.
    @State private var plusReason: PlusReason?
    /// Entrance motion of the Plus hero (design "Profil Revamp"): pop-in and the trial ring growing.
    @State private var heroIn = false
    @State private var ringGrown = false
    @State private var floating = false

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
                    // Design "Profil Revamp" 1a: identity first, then status (the Plus card), then settings.
                    if plus.isPlus {
                        plusHeroCard.stEnter(0)
                    } else {
                        profileHeader.stEnter(0)
                        if authViewModel.currentUser?.isGuest == true {
                            guestCard.stEnter(1)
                        } else {
                            freePlusCard.stEnter(1)
                        }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        if PlusStore.isInternalBuild {
                            // referral codes need the server; the page runs on sample data and stays out of the App Store build
                            NavigationLink(destination: ReferralView().detailPage()) {
                                row(icon: "person.2", title: L("Ajak teman"), subtitle: L("Dapat +5 bantuan AI per teman")) { chevron }
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(RowPressStyle())
                            .stEnter(2)
                        }
                        Rectangle().fill(Color.appDivider).frame(height: 1)
                            .padding(.top, 14).stEnter(2)
                        dataSection.stEnter(3)
                        appearanceSection.stEnter(4)
                        notificationSection.stEnter(5)
                        if authViewModel.currentUser?.isGuest == false {
                            logoutButton.stEnter(6)
                        }
                        Text(authViewModel.currentUser?.isGuest == true
                             ? L("Saku versi %@", appVersion)
                             : L("Bergabung sejak %@ · Saku versi %@", memberSinceDate, appVersion))
                            .font(.app(13))
                            .foregroundStyle(Color.appTextTertiary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 18)
                            .padding(.bottom, 96) // room for the floating ✦
                            .stEnter(7)
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
            .plusOffer($plusReason)
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
                     ? L("Kamu masuk sebagai tamu. Setelah keluar, data di akun tamu ini tidak bisa dibuka lagi.")
                     : L("Kamu akan keluar. Datamu tetap tersimpan."))
            }
        }
    }

    // MARK: - Header and status cards (design "Profil Revamp" 1a)

    /// Avatar, name and email in one row, with "Ubah" to edit. Guests have no profile to edit.
    private var profileHeader: some View {
        let isGuest = authViewModel.currentUser?.isGuest == true
        return HStack(spacing: 14) {
            InitialsAvatar(initials: authViewModel.currentUser?.initials ?? "U", size: 56, fontSize: 20,
                           image: authViewModel.avatarImage)
            VStack(alignment: .leading, spacing: 2) {
                Text(authViewModel.currentUser?.fullName ?? "User")
                    .font(.app(20, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Color.appText)
                Text(isGuest ? L("Data hanya di perangkat ini") : authViewModel.currentUser?.email ?? "")
                    .font(.app(14))
                    .foregroundStyle(Color.appTextSecondary)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            if !isGuest {
                NavigationLink("Ubah") { ProfileEditView(viewModel: viewModel, authViewModel: authViewModel).detailPage() }
                    .font(.app(15))
                    .foregroundStyle(Color.appPrimary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 18)
    }

    /// The green hero for Plus accounts: identity, the crown watermark and the status row with Kelola.
    private var plusHeroCard: some View {
        let trial = plus.entitlement.phase() == .trial
        let daysLeft = plus.entitlement.daysLeft() ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                InitialsAvatar(initials: authViewModel.currentUser?.initials ?? "U", size: 56, fontSize: 20,
                               image: authViewModel.avatarImage)
                    .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 3))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "crown.fill").font(.system(size: 12)).foregroundStyle(Color.appInvestment)
                            .frame(width: 24, height: 24).background(.white, in: Circle())
                            .offset(x: 4, y: 2)
                            .scaleEffect(heroIn ? 1 : 0.6).opacity(heroIn ? 1 : 0)
                            .animation(.spring(duration: 0.5, bounce: 0.35).delay(0.5), value: heroIn)
                    }
                    .scaleEffect(heroIn ? 1 : 0.6).opacity(heroIn ? 1 : 0)
                    .animation(.spring(duration: 0.6, bounce: 0.3).delay(0.15), value: heroIn)
                VStack(alignment: .leading, spacing: 2) {
                    Text(authViewModel.currentUser?.fullName ?? "User").font(.app(20, weight: .semibold)).tracking(-0.2)
                    Text(authViewModel.currentUser?.email ?? "")
                        .font(.app(14)).foregroundStyle(Color(light: 0xE3F4EC, dark: 0xE3F4EC))
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                NavigationLink("Ubah") { ProfileEditView(viewModel: viewModel, authViewModel: authViewModel).detailPage() }
                    .font(.app(15))
                    .foregroundStyle(.white)
            }
            HStack(spacing: 12) {
                if trial { trialRing(daysLeft: daysLeft) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(trial ? L("Sisa %lld hari", daysLeft) : L("Saku Plus aktif")).font(.app(16, weight: .semibold))
                    Text(trial ? L("Uji coba Plus s.d. %@", shortUntil) : L("s.d. %@", longUntil))
                        .font(.app(13)).foregroundStyle(Color(light: 0xE3F4EC, dark: 0xE3F4EC))
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                NavigationLink(destination: PlusStatusView().detailPage()) {
                    Text(L("Kelola")).font(.app(15, weight: .medium)).foregroundStyle(Color.appPrimary)
                        .frame(height: 34).padding(.horizontal, 16).background(.white, in: Capsule())
                }
            }
            .padding(.top, 14)
            .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.28)).frame(height: 1) }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .topTrailing) {
                Color.appPrimary
                // the crown floats gently behind the card (design: floaty, 6s)
                Image(systemName: "crown.fill")
                    .font(.system(size: 140))
                    .foregroundStyle(.white.opacity(0.14))
                    .rotationEffect(.degrees(floating ? -6 : -12))
                    .offset(x: 14, y: floating ? -20 : -12)
                    .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: floating)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .onAppear { heroIn = true; floating = true; ringGrown = true }
    }

    /// The trial's ring fills 7 of 14 days when the card opens (design: ring, 1.4s).
    private func trialRing(daysLeft: Int) -> some View {
        ZStack {
            Circle().stroke(.white.opacity(0.25), lineWidth: 6)
            Circle()
                .trim(from: 0, to: ringGrown ? min(1, Double(daysLeft) / 14) : 0)
                .stroke(.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 1.4).delay(0.3), value: ringGrown)
            Text("\(daysLeft)").font(.app(20, weight: .light))
        }
        .frame(width: 52, height: 52)
    }

    /// Free accounts: the quiet invitation with three benefits and one button.
    private var freePlusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "crown.fill").font(.system(size: 18)).foregroundStyle(Color.appInvestment)
                Text(L("Coba Saku Plus")).font(.app(18, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 8) {
                benefit(L("Semua fitur terbuka"))
                benefit(L("Bantuan AI tanpa batas"))
                benefit(L("Ekspor dan laporan lengkap"))
            }
            PrimaryButton(title: L("Coba Saku Plus")) { plusReason = .general }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 24)
        .padding(.bottom, 6)
    }

    private func benefit(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.appPrimary)
            Text(text).font(.app(15))
        }
    }

    /// Guests cannot buy Plus yet: the honest ask is saving their data by signing in.
    private var guestCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L("Amankan datamu")).font(.app(17, weight: .semibold))
                Text(L("Masuk agar datamu tersimpan di semua perangkat. Saku Plus tersedia setelah masuk."))
                    .font(.app(14)).foregroundStyle(Color.appTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PrimaryButton(title: L("Masuk atau daftar")) { authViewModel.logout() }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 24)
        .padding(.bottom, 6)
    }

    private var longUntil: String { untilText("d MMM yyyy") }
    private var shortUntil: String { untilText("d MMM") }

    /// The end date of the paid or trial period; the internal test switch has none.
    private func untilText(_ format: String) -> String {
        guard let date = plus.entitlement.until else { return "-" }
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = AppLanguage.locale
        return formatter.string(from: date)
    }

    // MARK: - Sections

    /// Design "Profil Revamp": one Data section (no caption "Keuangan"); values sit on the right
    /// and subtitles that only repeated the value are gone.
    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionCaption(L("Data"))

            NavigationLink(destination: CategoriesView()) {
                row(icon: "square.grid.2x2", title: L("Kategori")) {
                    chevron
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())

            Button { showsPayday = true } label: {
                row(icon: "calendar", title: L("Tanggal gajian")) {
                    Text(paydayDay == 0 ? L("Belum diatur") : "\(paydayDay)")
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

            NavigationLink(destination: SmartTrackerSettingsView().detailPage()) {
                row(icon: "sparkles", title: L("Smart tracker")) {
                    chevron
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())

            NavigationLink(destination: ExportView().detailPage()) {
                row(icon: "square.and.arrow.up", title: L("Ekspor data")) {
                    Text(verbatim: "CSV").font(.app(15)).foregroundStyle(Color.appTextSecondary)
                    chevron
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
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
                row(icon: "house", title: L("Total saldo")) {
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
        guard mode.rawValue != homeBalanceMode else { return }
        let previous = homeBalanceMode
        homeBalanceMode = mode.rawValue
        // guests have no profile row; the device mirror is all there is
        guard let id = authViewModel.currentUser.flatMap({ UUID(uuidString: $0.id) }) else { return }
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

    /// Design "Profil Revamp": a soft error-tinted bar, not a bordered capsule.
    private var logoutButton: some View {
        Button {
            showLogoutAlert = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 17))
                Text("Keluar").font(.app(16, weight: .medium))
            }
            .foregroundStyle(Color.appError)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.appError.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
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
    @State private var toastIsError = false
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

                // Design "Profil Revamp": Hapus akun moved here from the Profil tab; it lives with
                // the account details now.
                if authViewModel.currentUser?.isGuest == false {
                    NavigationLink(destination: DeleteAccountView(authViewModel: authViewModel).detailPage()) {
                        Text(L("Hapus akun"))
                            .font(.app(15)).foregroundStyle(Color.appTextSecondary)
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 24)
                }
            }
        }
        .background(Color.appBackground)
        .navigationTitle("Ubah Profil")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toast(isPresented: $showToast, message: toastMessage, icon: toastIsError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
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
                    toastIsError = false
                    toastMessage = L("Profil berhasil disimpan")
                    withAnimation { showToast = true }
                } else if let error = viewModel.errorMessage {
                    toastIsError = true
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
    @State private var on: Bool

    init(selection: String, cash: Double, assets: Double, onPick: @escaping (HomeBalanceMode) -> Void) {
        self.selection = selection; self.cash = cash; self.assets = assets; self.onPick = onPick
        _on = State(initialValue: selection == HomeBalanceMode.all.rawValue)
    }

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

            VStack(spacing: 4) {
                Text("Total saldo di Beranda").font(.app(13)).foregroundStyle(Color.appTextSecondary)
                Text((on ? cash + assets : cash).formattedAsCurrency())
                    .font(.app(42, weight: .ultraLight)).monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.25), value: on)
                    .animation(.easeOut(duration: 0.25), value: on)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(Color.stChip, in: RoundedRectangle(cornerRadius: 24))
            .padding(.top, 22)

            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: "wallet.bifold").font(.system(size: 18)).foregroundStyle(Color.appTextSecondary).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Kas").font(.app(16))
                        Text("Rekening, e-wallet, tunai · selalu ikut").font(.app(13)).foregroundStyle(Color.appTextSecondary)
                    }
                    Spacer(minLength: 8)
                    Text(cash.formattedAsCurrency()).font(.app(15)).monospacedDigit()
                }
                .padding(.vertical, 14)
                Divider()
                HStack(spacing: 14) {
                    Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 18)).foregroundStyle(Color.appInvestment).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ikutkan aset investasi").font(.app(16))
                        Text(L("%@ dari dompet investasi", assets.formattedAsCurrency())).font(.app(13)).foregroundStyle(Color.appTextSecondary)
                    }
                    Spacer(minLength: 8)
                    Toggle("Ikutkan aset investasi", isOn: Binding(get: { on }, set: { on = $0; onPick($0 ? .all : .cash) }))
                        .labelsHidden().tint(.appPrimary)
                }
                .padding(.vertical, 14)
            }
            .padding(.top, 18)

            Text("Hanya mengubah angka di Beranda. Dompet tetap menampilkan kas dan aset terpisah.")
                .font(.app(13))
                .foregroundStyle(Color.appTextSecondary)
                .padding(.top, 10)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .foregroundStyle(Color.appText)
        .presentationDetents([.height(500)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(Color.appBackground)
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
