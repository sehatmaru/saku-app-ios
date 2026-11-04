import SwiftUI

/// Profil › Smart Tracker (design 1b): three switches (AI, Notifikasi, Siri), the quota card, and the way the data is processed.
/// Smart Tracker itself is always on; the AI switch needs the one AI agreement. Notifikasi keeps a sub-menu with the steps.
struct SmartTrackerSettingsView: View {
    @ObservedObject private var plus = PlusStore.shared
    @ObservedObject private var quotaStore = AIQuotaStore.shared
    @EnvironmentObject private var authViewModel: AuthViewModel
    @AppStorage(SmartTrackerConsent.key) private var aiOn = false
    @State private var plusReason: PlusReason?
    @State private var siri = SmartTrackerWays.siri
    @State private var notification = SmartTrackerWays.notification
    @State private var reminder = SmartTrackerWays.reminder
    @State private var showsConsent = false
    @State private var showsPrivacy = false
    @State private var failed = false

    private var profileId: UUID? { authViewModel.currentUser.flatMap { UUID(uuidString: $0.id) } }
    private var isGuest: Bool { authViewModel.currentUser?.isGuest == true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Smart Tracker").font(.app(34, weight: .bold)).tracking(-0.4).foregroundStyle(Color.appText)
                    .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 12)

                wayRow(.ai, aiDetail) {
                    if isGuest { lock } else {
                        Toggle(SmartWay.ai.title, isOn: Binding(get: { aiOn }, set: { setAI($0) })).labelsHidden().tint(Color.appPrimary)
                    }
                }
                wayRow(.notification, notificationDetail) {
                    if isGuest { lock } else {
                        Toggle(SmartWay.notification.title, isOn: Binding(get: { notification }, set: { notification = $0; SmartTrackerWays.notification = $0 }))
                            .labelsHidden().tint(Color.appPrimary).disabled(!NotificationTrigger.isAvailable)
                    }
                }
                if !isGuest { setupGuideRow }
                wayRow(.reminder, L("Diingatkan 5 jam dan 1 hari setelah draf masuk")) {
                    Toggle(SmartWay.reminder.title, isOn: Binding(get: { reminder }, set: { reminder = $0; SmartTrackerWays.reminder = $0; DraftStore.shared.rescheduleReminder() }))
                        .labelsHidden().tint(Color.appPrimary)
                }
                wayRow(.siri, isGuest ? L("Perlu akun") : L("Catat lewat perintah suara Siri")) {
                    if isGuest { lock } else {
                        Toggle(SmartWay.siri.title, isOn: Binding(get: { siri }, set: { siri = $0; SmartTrackerWays.siri = $0 }))
                            .labelsHidden().tint(Color.appPrimary)
                    }
                }

                Rectangle().fill(Color.appDivider).frame(height: 1).padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 16)

                if isGuest {
                    guestCard.padding(.horizontal, 24)
                } else if let quota = quotaStore.quota {
                    quotaCard(quota).padding(.horizontal, 24)
                    if quota.isOut {
                        Text(L("Jatah habis. Dibaca dengan aturan di perangkat.")).font(.app(13)).lineSpacing(2).foregroundStyle(Color.appError)
                            .padding(.horizontal, 24).padding(.top, 12)
                        textLink(L("Lihat Saku Plus")) { plusReason = .aiHelp }.padding(.horizontal, 24).padding(.top, 4)
                    } else if !aiOn && !quota.isPlus {
                        Text(L("AI mati. Jatah tidak terpakai.")).font(.app(13)).lineSpacing(2).foregroundStyle(Color.appTextSecondary)
                            .padding(.horizontal, 24).padding(.top, 12)
                    }
                } else {
                    quotaPlaceholder.padding(.horizontal, 24)
                }

                textLink(L("Cara data diproses")) { showsPrivacy = true }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 40)
            }
        }
        .scrollIndicators(.hidden)
        .background(Color.appBackground)
        .hidesSmartButton()
        .plusOffer($plusReason)
        .task { await quotaStore.refresh() }
        .sheet(isPresented: $showsConsent) { SmartTrackerConsentSheet(profileId: profileId) { showsConsent = false } }
        .sheet(isPresented: $showsPrivacy) { SmartTrackerPrivacySheet() }
        .confirmDialog(isPresented: $failed, icon: "exclamationmark.triangle", title: L("Gagal mematikan AI"),
                       message: L("Periksa koneksi internetmu lalu coba lagi. Pengaturanmu belum berubah."), confirmTitle: nil, cancelTitle: L("Tutup"))
    }

    private static let resetFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        f.locale = AppLanguage.locale
        f.timeZone = TimeZone(identifier: "Asia/Jakarta")
        return f
    }()

    // MARK: Rows

    private var lock: some View {
        Image(systemName: "lock").font(.system(size: 20)).foregroundStyle(Color.appTextSecondary).frame(width: 44, height: 44)
    }

    private func wayRow<Trailing: View>(_ way: SmartWay, _ detail: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 14) {
            Image(systemName: way.icon).font(.system(size: 20)).foregroundStyle(Color.appTextSecondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(L(way.title)).font(.app(17)).foregroundStyle(Color.appText)
                Text(L(detail)).font(.app(13)).lineSpacing(2).foregroundStyle(Color.appTextSecondary)
            }
            Spacer(minLength: 8)
            trailing().frame(minWidth: 51, minHeight: 44)
        }
        .padding(.horizontal, 24).padding(.vertical, 12).frame(minHeight: 64)
    }

    /// The sub-menu under Notifikasi: the steps to connect a bank or e-wallet app. Plus is needed to record from notifications.
    private var setupGuideRow: some View {
        NavigationLink(destination: NotificationSetupGuideView().detailPage()) {
            HStack(spacing: 8) {
                Text(L("Cara mengatur notifikasi")).font(.app(15, weight: .semibold)).foregroundStyle(Color.appPrimaryText)
                Spacer(minLength: 8)
                if !plus.isPlus {
                    Text(verbatim: "Plus").font(.app(11, weight: .semibold)).foregroundStyle(Color.appPrimaryText)
                        .padding(.horizontal, 8).padding(.vertical, 2).background(Color.appPrimary.opacity(0.12), in: Capsule())
                }
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
            }
            .padding(.leading, 62).padding(.trailing, 24).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func textLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.app(15, weight: .semibold)).foregroundStyle(Color.appPrimaryText)
                .frame(minHeight: 44, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Cards

    /// This month's AI help, real from the server (design 1b). Plus shows no bar; an empty allowance turns red.
    private func quotaCard(_ quota: AIQuotaReading) -> some View {
        let out = quota.isOut
        let total = max(quota.total ?? 1, 1)
        return VStack(alignment: .leading, spacing: quota.isPlus ? 10 : 14) {
            Text(L("Jatah AI bulan ini")).font(.app(15)).foregroundStyle(Color.appTextSecondary)
            if quota.isPlus {
                Text(L("Tanpa batas")).font(.app(40, weight: .ultraLight)).tracking(-1).foregroundStyle(Color.appPrimary)
                Text(L("Saku Plus aktif. AI tanpa batas.")).font(.app(13)).lineSpacing(3).foregroundStyle(Color.appTextSecondary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(quota.left ?? 0)").font(.app(52, weight: .ultraLight)).tracking(-1.5).monospacedDigit()
                        .foregroundStyle(out ? Color.appError : Color.appText)
                    Text(L("dari %lld", quota.total ?? 0)).font(.app(17)).foregroundStyle(Color.appTextSecondary)
                }
                SegmentBar(value: Double(quota.left ?? 0) / Double(total), color: out ? Color.appError : Color.appPrimary,
                           count: 40, height: 14, spacing: 3)
                Text(L("Reset %@", Self.resetFormat.string(from: AIQuotaReading.resetDate))).font(.app(13)).foregroundStyle(Color.appTextSecondary)
                Rectangle().fill(Color.appBorder).frame(height: 1)
                NavigationLink(destination: ReferralView().detailPage()) {
                    HStack(spacing: 8) {
                        Text(L("Bonus referral")).font(.app(15)).foregroundStyle(Color.appText)
                        Spacer(minLength: 8)
                        Text(L("+%lld dari maks. +40", quota.referralBonus)).font(.app(15, weight: .semibold)).foregroundStyle(Color.appPrimaryText)
                        Image(systemName: "chevron.right").font(.system(size: 14)).foregroundStyle(Color.appTextSecondary)
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 20))
    }

    private var guestCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Masuk ke akun untuk memakai AI. Persetujuan dan jatah disimpan di akun.")).font(.app(15)).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: L("Masuk ke akun")) { authViewModel.startGuestLink() }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 20))
    }

    /// Loading and failed states of the allowance card: say which one it is, and offer the retry.
    private var quotaPlaceholder: some View {
        HStack(spacing: 10) {
            if quotaStore.failed {
                Text(L("Jatah AI belum bisa dimuat. Periksa koneksi lalu coba lagi.")).font(.app(13)).foregroundStyle(Color.appTextSecondary)
                Spacer(minLength: 8)
                Button { Task { await quotaStore.refresh() } } label: {
                    Text(L("Coba lagi")).font(.app(15, weight: .semibold)).foregroundStyle(Color.appPrimaryText).frame(minHeight: 44)
                }
            } else {
                ProgressView().controlSize(.small)
                Text(L("Memuat jatah AI")).font(.app(13)).foregroundStyle(Color.appTextSecondary)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 20))
    }

    private var aiDetail: String {
        if isGuest { return L("Perlu akun") }
        return aiOn ? L("Baca teks, suara, dan gambar dengan AI") : L("Mati. Dibaca dengan aturan di perangkat")
    }

    private var notificationDetail: String {
        if isGuest { return L("Perlu akun") }
        return NotificationTrigger.isAvailable ? L("Ubah notifikasi bank jadi draf") : L("Butuh iOS 27")
    }

    /// Turning on needs the agreement sheet; turning off just stops AI and Ingatan sync (nothing is deleted).
    private func setAI(_ on: Bool) {
        guard !isGuest else { return }
        if on { showsConsent = true; return }
        let previous = SmartTrackerConsent.isGranted
        SmartTrackerConsent.isGranted = false
        guard let profileId else { return }
        Task {
            do { try await SupabaseSDK.revokeSmartTrackerConsent(profileId: profileId) }
            catch { SmartTrackerConsent.isGranted = previous; failed = true }
        }
    }
}

/// The "Notifikasi" trigger of Shortcuts automations only exists from iOS 27; older iPhones cannot forward bank notifications.
enum NotificationTrigger {
    static var isAvailable: Bool { if #available(iOS 27, *) { true } else { false } }
}

/// Notifikasi aplikasi (designs "Notifikasi Bank" 1c and 2a): how to connect each bank or e-wallet app through a
/// Shortcuts automation, which titles become drafts, and what can be recorded. Older iOS gets a notice instead of the steps.
struct NotificationSetupGuideView: View {
    @ObservedObject private var store = DraftStore.shared
    @Environment(\.openURL) private var openURL

    private var steps: [Text] {
        [Text(L("Buka Shortcuts, pilih tab ")) + Text(L("Otomatisasi")).bold() + Text(L(", ketuk +, lalu pilih ")) + Text(L("Notifikasi")).bold() + Text("."),
         Text(L("Pilih aplikasi bank atau e-wallet-mu, lalu aktifkan ")) + Text(L("Jalankan Segera")).bold() + Text("."),
         Text(L("Ketuk Berikutnya, cari Saku, lalu pilih aksi ")) + Text(L("Catat dari notifikasi")).bold() + Text("."),
         Text(L("Di aksi itu, isi Aplikasi dengan nama bank-nya. Untuk Judul, Subjudul, dan Isi, pilih variabel ")) + Text(L("Notifikasi")).bold() + Text("."),
         Text(L("Ketuk ")) + Text(L("Selesai")).bold() + Text(L(". Kalau muncul ")) + Text(L("Tanya Sebelum Menjalankan")).bold() + Text(L(", matikan."))]
    }

    private var kinds: [(String, String)] {
        [("arrow.left.arrow.right", L("Transfer masuk dan keluar")), ("qrcode", L("Pembayaran QRIS dan kartu")),
         ("wallet.bifold", L("Top up dan tarik tunai")), ("doc.text", L("Tagihan dan cicilan"))]
    }

    private var privacy: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock").font(.system(size: 16)).foregroundStyle(Color.appTextSecondary).padding(.top, 1)
            Text(L("Saku hanya membaca notifikasi untuk membuat draf, lalu langsung menghapusnya. Tidak ada yang tercatat sebelum kamu cek. Yang diingat hanya 10 judul terakhir, di HP ini, supaya bisa kamu pilih."))
                .font(.app(13)).lineSpacing(3).foregroundStyle(Color.appTextSecondary)
            Spacer(minLength: 0)
        }
    }

    private var divider: some View { Rectangle().fill(Color.appSeparator).frame(height: 1).padding(.vertical, 24) }

    private var recordable: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Yang bisa dicatat").font(.app(20, weight: .semibold))
            VStack(spacing: 0) {
                ForEach(Array(kinds.enumerated()), id: \.offset) { _, kind in
                    HStack(spacing: 14) {
                        Image(systemName: kind.0).font(.system(size: 18)).foregroundStyle(Color.appTextSecondary).frame(width: 24)
                        Text(kind.1).font(.app(16))
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                }
            }
            .padding(.top, 8)
            Text("Dari notifikasi aplikasi bank, e-wallet, atau belanja di HP-mu.")
                .font(.app(13)).lineSpacing(2).foregroundStyle(Color.appTextSecondary).padding(.top, 6)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    illustration.padding(.top, 12)
                    if NotificationTrigger.isAvailable { available } else { unavailable }
                    Color.clear.frame(height: NotificationTrigger.isAvailable ? 130 : 24)
                }
                .padding(.horizontal, 24)
            }
            if NotificationTrigger.isAvailable {
                LinearGradient(colors: [Color.appBackground.opacity(0), Color.appBackground], startPoint: .top, endPoint: .center)
                    .frame(height: 120).allowsHitTesting(false)
                Button { openURL(URL(string: "shortcuts://create-automation")!) } label: {
                    Label(L("Buka Shortcuts"), systemImage: "arrow.up.forward.app")
                        .font(.app(17, weight: .semibold)).foregroundStyle(Color.appBackground)
                        .frame(maxWidth: .infinity).frame(height: 52).background(Color.appText, in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
                .padding(.horizontal, 24).padding(.bottom, 12)
            }
        }
        .background(Color.appBackground)
        .navigationTitle(L("Notifikasi aplikasi"))
        .navigationBarTitleDisplayMode(.inline)
        .hidesSmartButton()
    }

    /// A notification becoming a draft, with the bank's own logo.
    private var illustration: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                WalletIconView(icon: WalletIcon.resolve("bca"), size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("Transfer Berhasil")).font(.app(13, weight: .semibold))
                    Text(L("Rp150.000 ke Budi Santoso")).font(.app(13)).foregroundStyle(Color.appTextSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text("baru saja").font(.app(12)).foregroundStyle(Color.appTextTertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 10).background(Color.stRaised, in: RoundedRectangle(cornerRadius: 14))
            Image(systemName: "arrow.down").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.appTextTertiary)
            HStack(spacing: 12) {
                Image(systemName: "arrow.left.arrow.right").font(.system(size: 16)).foregroundStyle(Color.appTextSecondary).frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("Transfer ke Budi")).font(.app(15))
                    Text(L("Draf · BCA")).font(.app(13)).foregroundStyle(Color.appPrimary)
                }
                Spacer(minLength: 0)
                Text("−Rp150.000").font(.app(15)).monospacedDigit()
            }
            .padding(.horizontal, 12).padding(.vertical, 10).background(Color.stRaised, in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(16).background(Color.appFill, in: RoundedRectangle(cornerRadius: 20))
    }

    private var available: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Setiap ada notifikasi transaksi, Shortcuts di iPhone meneruskannya ke Saku. Atur sekali saja untuk tiap aplikasi."))
                .font(.app(15)).lineSpacing(3).foregroundStyle(Color.appBody).padding(.top, 16)

            Text(L("Sudah terhubung")).font(.app(13, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
                .padding(.top, 22).padding(.bottom, 8)
            if store.connectedApps.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "powerplug").font(.system(size: 18)).foregroundStyle(Color.appTextSecondary)
                        .frame(width: 40, height: 40).background(Color.stChip, in: Circle()).stFloat()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Belum ada aplikasi terhubung")).font(.app(15, weight: .semibold))
                        Text(L("Begitu notifikasi pertama masuk, aplikasinya muncul di sini."))
                            .font(.app(13)).lineSpacing(2).foregroundStyle(Color.appTextSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.stDash, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(store.connectedApps, id: \.self) { app in
                        Label(app, systemImage: "checkmark.circle.fill")
                            .font(.app(14, weight: .semibold)).foregroundStyle(Color.stSuccessText)
                            .padding(.horizontal, 12).frame(height: 32)
                            .background(Color.stSuccessBg, in: Capsule())
                    }
                }
            }

            Text(L("Cara menghubungkan")).font(.app(13, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
                .padding(.top, 24).padding(.bottom, 8)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 4) {
                            Text("\(index + 1)").font(.app(14, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 28, height: 28).background(Color.stGreen, in: Circle())
                            if index < steps.count - 1 {
                                Rectangle().fill(Color.stLine).frame(width: 2).frame(maxHeight: .infinity)
                            }
                        }
                        step.font(.app(15)).lineSpacing(3).padding(.top, 3).padding(.bottom, 18)
                        Spacer(minLength: 0)
                    }
                }
            }

            divider
            NotificationFilterSection()
            privacy.padding(.top, 20)
            divider
            recordable
        }
    }

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle").font(.system(size: 19)).foregroundStyle(Color.appTextSecondary).padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Belum tersedia di iOS-mu")).font(.app(16, weight: .semibold))
                    Text(L("Pemicu Notifikasi di Shortcuts baru ada di iOS 27 ke atas. Sampai iOS-mu diperbarui, catat lewat ketik atau ucapan, menu Bagikan, atau Siri."))
                        .font(.app(14)).lineSpacing(3).foregroundStyle(Color.appBody)
                }
                Spacer(minLength: 0)
            }
            .padding(16).background(Color.stChip, in: RoundedRectangle(cornerRadius: 16)).padding(.top, 16)
            recordable.padding(.top, 28)
            privacy.padding(.top, 24)
        }
    }
}

private struct ExampleLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 15)).foregroundStyle(Color.appTextSecondary)
            configuration.title
        }
    }
}


/// "Notifikasi yang ditangkap" (BUG-22, design "Notifikasi Bank" 1c): three summary rows; each opens a sheet with
/// the words that drop a notification, the words that are the only ones kept, or the titles that came in last.
private struct NotificationFilterSection: View {
    private enum Panel: String, Identifiable { case ignore, only, recent; var id: String { rawValue } }

    @State private var ignore = NotificationFilter.ignore
    @State private var only = NotificationFilter.only
    @State private var recent = NotificationFilter.recent
    @State private var panel: Panel?

    private var draftCount: Int {
        recent.filter { NotificationFilter.verdict(title: $0, ignore: ignore, only: only) == .draft }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Notifikasi yang ditangkap").font(.app(20, weight: .semibold))
            Text("Pilih notifikasi mana yang dibuat draf, berdasarkan judulnya.")
                .font(.app(15)).lineSpacing(3).foregroundStyle(Color.appTextSecondary).padding(.top, 6)
            VStack(spacing: 0) {
                row(L("Abaikan judul"), ignore.isEmpty ? L("Belum ada") : ignore.joined(separator: ", ")) { panel = .ignore }
                Divider()
                row(L("Simpan draf"), only.isEmpty ? L("Semua judul ditangkap") : only.joined(separator: ", ")) { panel = .only }
                Divider()
                row(L("Judul terakhir"), recent.isEmpty ? L("Belum ada notifikasi masuk") : L("%lld judul · %lld jadi draf", recent.count, draftCount)) { panel = .recent }
            }
            .padding(.horizontal, 16).background(Color.appFill, in: RoundedRectangle(cornerRadius: 16)).padding(.top, 16)
            if !only.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle").font(.system(size: 15)).foregroundStyle(Color.stWarn).padding(.top, 1)
                    Text("\"Simpan draf\" sedang diisi, jadi notifikasi dengan judul lain tidak dibuat draf.")
                        .font(.app(13)).lineSpacing(2).foregroundStyle(Color.appBody)
                }
                .padding(.top, 12).transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: only.isEmpty)
        .sheet(item: $panel, onDismiss: reload) { panel in
            switch panel {
            case .ignore: FilterWordsSheet(toOnly: false)
            case .only: FilterWordsSheet(toOnly: true)
            case .recent: RecentTitlesSheet()
            }
        }
    }

    private func row(_ title: String, _ value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.app(16)).foregroundStyle(Color.appText)
                    Text(value).font(.app(13)).foregroundStyle(Color.appTextSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.appTextTertiary)
            }
            .padding(.vertical, 14).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func reload() {
        ignore = NotificationFilter.ignore; only = NotificationFilter.only; recent = NotificationFilter.recent
    }
}

/// A sheet's title, in the style of the picker sheets; the sheet closes from its pinned "Tutup".
private struct FilterSheetHeader: View {
    let title: String

    var body: some View {
        Text(title).font(.app(22, weight: .bold)).tracking(-0.3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 22)
    }
}

/// "Abaikan judul" or "Simpan draf": the words, one per row with a small x, and a field to add one.
private struct FilterWordsSheet: View {
    let toOnly: Bool
    @State private var words: [String]
    @State private var input = ""
    @Environment(\.dismiss) private var dismiss

    init(toOnly: Bool) {
        self.toOnly = toOnly
        _words = State(initialValue: toOnly ? NotificationFilter.only : NotificationFilter.ignore)
    }

    private var canAdd: Bool { !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FilterSheetHeader(title: toOnly ? L("Simpan draf") : L("Abaikan judul"))
                Text(toOnly ? L("Bila diisi, hanya notifikasi yang judulnya mengandung kata ini yang dibuat draf.")
                            : L("Notifikasi yang judulnya mengandung kata ini tidak dibuat draf, mis. Promo."))
                    .font(.app(15)).lineSpacing(3).foregroundStyle(Color.appTextSecondary).padding(.top, 6)
                HStack(spacing: 8) {
                    TextField(L("Tambah kata"), text: $input)
                        .font(.app(16)).padding(.horizontal, 14).frame(height: 44)
                        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 12))
                        .submitLabel(.done).onSubmit(add)
                    Button(L("Tambah"), action: add)
                        .font(.app(15, weight: .semibold)).foregroundStyle(Color.appPrimary)
                        .padding(.horizontal, 18).frame(height: 44)
                        .background(Color.appPrimary.opacity(0.12), in: Capsule())
                        .opacity(canAdd ? 1 : 0.4).disabled(!canAdd)
                }
                .padding(.top, 16)
                if toOnly, !words.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle").font(.system(size: 15)).foregroundStyle(Color.stWarn).padding(.top, 1)
                        Text("Notifikasi dengan judul lain tidak dibuat draf. Kosongkan daftar ini untuk menangkap semuanya lagi.")
                            .font(.app(13)).lineSpacing(2).foregroundStyle(Color.appBody)
                    }
                    .padding(.top, 12)
                }
                VStack(spacing: 0) {
                    ForEach(words, id: \.self) { word in
                        HStack(alignment: .top, spacing: 12) {
                            Text(word).font(.app(16)).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Button { remove(word) } label: {
                                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.appTextSecondary)
                                    .frame(width: 28, height: 28).background(Color.appFill, in: Circle())
                            }
                            .buttonStyle(.plain).accessibilityLabel(L("Hapus %@", word))
                        }
                        .padding(.vertical, 12)
                        .overlay(alignment: .top) { Rectangle().fill(Color.appSeparator).frame(height: 1) }
                    }
                    if words.isEmpty {
                        Text("Belum ada kata").font(.app(15)).foregroundStyle(Color.appTextTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
                            .overlay(alignment: .top) { Rectangle().fill(Color.appSeparator).frame(height: 1) }
                    }
                }
                .padding(.top, 12)
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .pinnedFooter { SmartSheetFooter(primary: L("Tutup"), secondary: nil, onPrimary: { dismiss() }) }
        .presentationDetents([.medium, .large])
        .background(Color.appBackground)
    }

    private func add() {
        guard canAdd else { return }
        NotificationFilter.add(input, toOnly: toOnly)
        input = ""
        words = toOnly ? NotificationFilter.only : NotificationFilter.ignore
    }

    private func remove(_ word: String) {
        if toOnly { NotificationFilter.only.removeAll { $0 == word } } else { NotificationFilter.ignore.removeAll { $0 == word } }
        words = toOnly ? NotificationFilter.only : NotificationFilter.ignore
    }
}

/// "Judul terakhir": the titles that came in, each opening to two buttons that put the whole title on a list.
private struct RecentTitlesSheet: View {
    @State private var recent = NotificationFilter.recent
    @State private var ignore = NotificationFilter.ignore
    @State private var only = NotificationFilter.only
    @State private var opened: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FilterSheetHeader(title: L("Judul terakhir"))
                Text("Ketuk judul untuk memasukkannya ke daftar.").font(.app(15)).foregroundStyle(Color.appTextSecondary).padding(.top, 6)
                if recent.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "bell").font(.system(size: 32, weight: .light)).foregroundStyle(Color.appTextTertiary)
                        Text("Belum ada notifikasi masuk").font(.app(16, weight: .semibold))
                        Text("Judul notifikasi yang masuk akan muncul di sini supaya bisa kamu pilih.")
                            .font(.app(14)).lineSpacing(2).foregroundStyle(Color.appTextSecondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 40).padding(.bottom, 24)
                }
                VStack(spacing: 0) {
                    ForEach(recent, id: \.self) { title in titleRow(title) }
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
        .pinnedFooter { SmartSheetFooter(primary: L("Tutup"), secondary: nil, onPrimary: { dismiss() }) }
        .presentationDetents([.medium, .large])
        .background(Color.appBackground)
    }

    private func status(_ title: String) -> (text: String, isDraft: Bool) {
        switch NotificationFilter.verdict(title: title, ignore: ignore, only: only) {
        case .draft: return (L("Jadi draf"), true)
        case .ignored(let word):
            return (L("Diabaikan · ada “%@”", word.count > 24 ? String(word.prefix(24)) + "…" : word), false)
        case .notInOnly: return (L("Diabaikan · tidak cocok dengan Simpan draf"), false)
        }
    }

    private func titleRow(_ title: String) -> some View {
        let info = status(title)
        let isOpen = opened == title
        let inIgnore = ignore.contains { $0.caseInsensitiveCompare(title) == .orderedSame }
        let inOnly = only.contains { $0.caseInsensitiveCompare(title) == .orderedSame }
        return VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.spring(duration: 0.3)) { opened = isOpen ? nil : title } } label: {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.app(15)).lineSpacing(2).foregroundStyle(info.isDraft ? Color.appText : Color.appTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(info.text).font(.app(12)).foregroundStyle(info.isDraft ? Color.appPrimary : Color.appTextTertiary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.appTextTertiary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0)).padding(.top, 5)
                }
                .padding(.vertical, 12).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen {
                HStack(spacing: 8) {
                    pill(inIgnore ? L("Diabaikan") : L("Abaikan"), on: inIgnore) { apply(title, inOnly: false) }
                    pill(inOnly ? L("Hanya ini") : L("Simpan draf"), on: inOnly) { apply(title, inOnly: true) }
                }
                .padding(.bottom, 14).transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(Color.appSeparator).frame(height: 1) }
    }

    private func pill(_ text: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.app(14, weight: .medium)).foregroundStyle(on ? Color.appBackground : Color.appText)
                .frame(maxWidth: .infinity).frame(height: 40)
                .background(on ? Color.appText : Color.clear, in: Capsule())
                .overlay(Capsule().strokeBorder(on ? Color.appText : Color.appBorder, lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle())
    }

    private func apply(_ title: String, inOnly: Bool) {
        NotificationFilter.toggle(title, inOnly: inOnly)
        ignore = NotificationFilter.ignore
        only = NotificationFilter.only
    }
}
