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
    @State private var showsExport = false
    @State private var homeBalanceFailed = false
    @AppStorage(HomeBalanceSetting.key) private var homeBalanceMode = HomeBalanceMode.cash.rawValue

    @AppStorage("appLanguage") private var appLanguage = "id"
    @AppStorage("appTheme") private var appTheme: ThemeOption = .system
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
                BalanceSheet(selection: homeBalanceMode, cash: cash, assets: assets) { mode in
                    saveHomeBalance(mode)
                }
            }
            .sheet(isPresented: $showsTheme) {
                ThemeSheet(selection: appTheme.rawValue) { raw in
                    if let option = ThemeOption(rawValue: raw) { appTheme = option }
                }
            }
            .sheet(isPresented: $showsLanguage) {
                LanguageSheet(selection: appLanguage) { code in
                    guard code != appLanguage else { return }
                    // Cached dashboard state holds pre-rendered text (health tips, month labels).
                    AppDataCache.shared.clearAll()
                    appLanguage = code
                }
            }
            .sheet(isPresented: $showsExport) {
                ExportSheet()
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
    /// The plan ring: dashed, one segment per bar of Paket Saku (trial 7, yearly 12, monthly 10, grace 1 of 14), the lit ones
    /// are what is left. They grow in one by one when the card opens.
    private func planRing(_ bars: (total: Int, filled: Int), daysLeft: Int) -> some View {
        let gap = bars.total > 12 ? 0.012 : 0.02
        let size = 1 / Double(bars.total)
        return ZStack {
            ForEach(0..<bars.total, id: \.self) { i in
                Circle()
                    .trim(from: Double(i) * size + gap / 2, to: Double(i + 1) * size - gap / 2)
                    .stroke(i < bars.filled ? Color.white : Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 6, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                    .opacity(ringGrown ? 1 : 0)
                    .animation(.easeOut(duration: 0.3).delay(0.3 + Double(i) * 0.06), value: ringGrown)
            }
            if daysLeft < 100 { Text("\(daysLeft)").font(.app(20, weight: .light)) }
            else { Image(systemName: "sparkles").font(.system(size: 18)) }
        }
        .frame(width: 52, height: 52)
    }

    private var plusHeroCard: some View {
        let trial = plus.entitlement.phase() == .trial
        let daysLeft = plus.entitlement.daysLeft() ?? 0
        return VStack(alignment: .leading, spacing: 16) {
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
                if let bars = plus.entitlement.bars() { planRing(bars, daysLeft: daysLeft) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(trial ? L("Sisa %lld hari", daysLeft) : L("Saku Plus aktif")).font(.app(16, weight: .semibold))
                    Text(trial ? L("Uji coba Plus s.d. %@", shortUntil) : L("s.d. %@", longUntil))
                        .font(.app(13)).foregroundStyle(Color(light: 0xE3F4EC, dark: 0xE3F4EC))
                        .minimumScaleFactor(0.8)
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
                    .font(.system(size: 104))
                    .foregroundStyle(.white.opacity(0.14))
                    .rotationEffect(.degrees(floating ? -6 : -12))
                    .offset(x: 10, y: floating ? 2 : 10)
                    .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: floating)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .onAppear { heroIn = true; floating = true; ringGrown = true }
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

            Button { showsExport = true } label: {
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
    @ObservedObject private var plus = PlusStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showToast = false
    @State private var toastIsError = false
    @State private var toastMessage = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var deletesAccount = false
    @State private var isSavingPhoto = false
    /// Entrance motion of the avatar card (design "Ubah Profil": rise and pop).
    @State private var entered = false
    @FocusState private var nameFocused: Bool
    @AppStorage("memberSince") private var memberSince: Double = Date().timeIntervalSince1970

    private var isGuest: Bool { authViewModel.currentUser?.isGuest == true }
    private var trimmed: String { viewModel.displayName.trimmingCharacters(in: .whitespaces) }
    /// "Simpan" lights up only when the name actually changed and is not empty (design).
    private var changed: Bool { !trimmed.isEmpty && trimmed != (authViewModel.currentUser?.displayName ?? "") }
    private var shownName: String { trimmed.isEmpty ? L("Nama") : trimmed }
    private var photo: UIImage? { authViewModel.avatarImage }
    private var initials: String {
        let parts = trimmed.split(separator: " ").prefix(2)
        return parts.isEmpty ? "U" : parts.map { String($0.prefix(1)).uppercased() }.joined()
    }
    private var memberSinceLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = AppLanguage.locale
        return formatter.string(from: Date(timeIntervalSince1970: memberSince))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // top bar: just back; the name's check mark saves, the photo saves itself
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color.appPrimary)
                            .frame(width: 40, height: 40).contentShape(Rectangle())
                    }
                    .accessibilityLabel(L("Kembali"))
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.top, 8)

                Color.clear.frame(height: 10)

                VStack(spacing: 22) {
                    avatarCard
                    infoSection
                    if !isGuest { deleteCard }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
        .background(Color.appBackground)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            viewModel.loadProfile(from: authViewModel.currentUser)
            entered = true
        }
        .toast(isPresented: $showToast, message: toastMessage, icon: toastIsError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
        .navigationDestination(isPresented: $deletesAccount) {
            DeleteAccountView(authViewModel: authViewModel).detailPage()
        }
    }

    // MARK: Pieces

    /// Avatar, live name with the Plus badge, joined date and the photo actions.
    private var avatarCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().strokeBorder(Color.appPrimary.opacity(0.25), lineWidth: 2).frame(width: 104, height: 104)
                // tapping the avatar changes the photo; it saves as soon as one is picked
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    InitialsAvatar(initials: initials, size: 92, fontSize: 32, image: photo)
                        .overlay { if isSavingPhoto { Circle().fill(.black.opacity(0.35)); ProgressView().tint(.white) } }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Ganti foto"))
                .contextMenu {
                    if photo != nil { Button(L("Hapus foto"), role: .destructive) { savePhoto(nil) } }
                }
                .scaleEffect(entered ? 1 : 0.6).opacity(entered ? 1 : 0)
                .animation(.spring(duration: 0.6, bounce: 0.3).delay(0.1), value: entered)
                Image(systemName: "camera").font(.system(size: 16)).foregroundStyle(Color.appPrimary)
                    .frame(width: 32, height: 32).background(.white, in: Circle())
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    .offset(x: 35, y: 32).allowsHitTesting(false)
                    .scaleEffect(entered ? 1 : 0.6).opacity(entered ? 1 : 0)
                    .animation(.spring(duration: 0.5, bounce: 0.35).delay(0.45), value: entered)
            }
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Text(shownName).font(.app(22, weight: .semibold)).tracking(-0.3)
                    if plus.isPlus { plusBadge }
                }
                Text(L("Bergabung sejak %@", memberSinceLabel))
                    .font(.app(11)).foregroundStyle(Color.appTextSecondary)
            }
        }
        .padding(.horizontal, 18).padding(.top, 24).padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .background(Color.appPrimary.opacity(0.12))
        .overlay(alignment: .topTrailing) {
            // the crown watermark peeking from the corner (design "Ubah Profil")
            Image(systemName: "crown.fill").font(.system(size: 140))
                .foregroundStyle(Color.appPrimary.opacity(0.08))
                .offset(x: 18, y: -16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .opacity(entered ? 1 : 0).offset(y: entered ? 0 : 16)
        .animation(.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.6), value: entered)
        .onChange(of: pickerItem) { _, item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                savePhoto(image)
                pickerItem = nil
            }
        }
    }

    private var plusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "crown.fill").font(.system(size: 12))
            Text(verbatim: "Plus").font(.app(12, weight: .semibold))
        }
        .foregroundStyle(Color.appInvestment)
        .frame(height: 22).padding(.horizontal, 9)
        .background(Color.appInvestmentTint, in: Capsule())
    }

    /// Nama (with a live counter and a focus ring) and the locked email (design).
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Info akun")).font(.app(13, weight: .semibold))
                .foregroundStyle(Color.appTextSecondary).tracking(0.2)

            HStack(spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Nama")).font(.app(12)).foregroundStyle(Color.appTextSecondary)
                    TextField("", text: $viewModel.displayName, prompt: Text(L("Nama")).foregroundStyle(Color.appTextTertiary))
                        .font(.app(17, weight: .medium)).foregroundStyle(Color.appText)
                        .textContentType(.name).submitLabel(.done)
                        .focused($nameFocused)
                }
                Spacer(minLength: 8)
                Text("\(viewModel.displayName.count)/30")
                    .font(.app(13)).foregroundStyle(Color.appTextTertiary).monospacedDigit()
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .strokeBorder(nameFocused ? Color.appPrimary : .clear, lineWidth: 1.5))
            // the check mark appears beside the field only when the name changed
            if changed {
                Button { save() } label: {
                    Group {
                        if viewModel.isLoading { ProgressView().tint(.white) } else { Image(systemName: "checkmark").font(.system(size: 17, weight: .bold)) }
                    }
                    .foregroundStyle(.white).frame(width: 48, height: 48).background(Color.appPrimary, in: Circle())
                }
                .buttonStyle(PressScaleStyle()).disabled(viewModel.isLoading)
                .accessibilityLabel(L("Simpan"))
                .transition(.scale.combined(with: .opacity))
            }
            }
            .animation(.spring(duration: 0.3, bounce: 0.2), value: changed)
            .onChange(of: viewModel.displayName) { _, value in
                if value.count > 30 { viewModel.displayName = String(value.prefix(30)) }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Email").font(.app(12)).foregroundStyle(Color.appTextSecondary)
                    Text(authViewModel.currentUser?.isGuest == true ? L("Mode tamu") : authViewModel.currentUser?.email ?? "")
                        .font(.app(17, weight: .medium)).foregroundStyle(Color.appTextSecondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "lock").font(.system(size: 16)).foregroundStyle(Color.appTextTertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16))

        }
    }

    /// The quiet danger card that leads straight to the delete flow.
    private var deleteCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "trash").font(.system(size: 17)).foregroundStyle(Color.appError)
                    .frame(width: 40, height: 40).background(Color.appError.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Hapus akun")).font(.app(16, weight: .semibold))
                    Text(L("Semua transaksi, dompet, dan budget akan terhapus permanen dan tidak bisa dikembalikan."))
                        .font(.app(14)).foregroundStyle(Color.appTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // straight into the delete flow: it explains the 30 days, asks why and confirms by typing
            Button { deletesAccount = true } label: {
                Text(L("Hapus akun")).font(.app(16, weight: .medium)).foregroundStyle(Color.appError)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(Color.appError.opacity(0.12), in: Capsule())
            }
            .buttonStyle(PressScaleStyle())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.appError.opacity(0.25), lineWidth: 1))
    }

    /// Saves the photo (nil removes it) on its own, leaving a half-typed name alone.
    private func savePhoto(_ image: UIImage?) {
        guard !isSavingPhoto, let name = authViewModel.currentUser?.displayName else { return }
        isSavingPhoto = true
        Task {
            defer { isSavingPhoto = false }
            if let updated = await viewModel.saveProfile(user: authViewModel.currentUser, photo: image, removePhoto: image == nil, name: name) {
                authViewModel.currentUser = updated
                authViewModel.avatarImage = image
                toastIsError = false
                toastMessage = image == nil ? L("Foto dihapus") : L("Foto profil diperbarui")
            } else {
                toastIsError = true
                toastMessage = viewModel.errorMessage ?? L("Foto belum tersimpan. Coba lagi.")
            }
            withAnimation { showToast = true }
        }
    }

    private func save() {
        guard changed, !viewModel.isLoading else { return }
        Task {
            if let updated = await viewModel.saveProfile(user: authViewModel.currentUser, photo: nil) {
                authViewModel.currentUser = updated
                toastIsError = false
                toastMessage = L("Profil berhasil disimpan")
                withAnimation { showToast = true }
            } else if let error = viewModel.errorMessage {
                toastIsError = true
                toastMessage = error
                withAnimation { showToast = true }
            }
        }
    }
}

