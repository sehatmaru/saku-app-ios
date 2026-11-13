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
    @State private var reminder = SmartTrackerWays.reminder
    @State private var showsConsent = false
    @State private var failed = false

    private var profileId: UUID? { authViewModel.currentUser.flatMap { UUID(uuidString: $0.id) } }
    private var isGuest: Bool { authViewModel.currentUser?.isGuest == true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                quotaSection.padding(.top, 8)

                sectionLabel(L("Cara mencatat"))
                wayRow(.ai, aiDetail) {
                    if isGuest { lock } else {
                        Toggle(SmartWay.ai.title, isOn: Binding(get: { aiOn }, set: { setAI($0) })).labelsHidden().tint(Color.appPrimary)
                    }
                }
                wayRow(.siri, isGuest ? L("Perlu akun") : L("Catat lewat perintah suara Siri")) {
                    if isGuest { lock } else {
                        Toggle(SmartWay.siri.title, isOn: Binding(get: { siri }, set: { siri = $0; SmartTrackerWays.siri = $0 }))
                            .labelsHidden().tint(Color.appPrimary)
                    }
                }

                if !isGuest { autoRecordRow }

                sectionLabel(L("Pengingat"))
                wayRow(.reminder, L("Diingatkan 5 jam dan 1 hari setelah draf masuk")) {
                    Toggle(SmartWay.reminder.title, isOn: Binding(get: { reminder }, set: { reminder = $0; SmartTrackerWays.reminder = $0; DraftStore.shared.rescheduleReminder() }))
                        .labelsHidden().tint(Color.appPrimary)
                }

                privacyRow.padding(.bottom, 40)
            }
        }
        .scrollIndicators(.hidden)
        .background(Color.appBackground)
        .navigationTitle("Smart Tracker")
        .navigationBarTitleDisplayMode(.inline)
        .hidesSmartButton()
        .plusOffer($plusReason)
        .task { await quotaStore.refresh() }
        .sheet(isPresented: $showsConsent) { SmartTrackerConsentSheet(profileId: profileId) { showsConsent = false } }
        .confirmDialog(isPresented: $failed, icon: "exclamationmark.triangle", title: L("Gagal mematikan AI"),
                       message: L("Periksa koneksi internetmu lalu coba lagi. Pengaturanmu belum berubah."), confirmTitle: nil, cancelTitle: L("Tutup"))
    }

    /// The allowance sits first: it is the thing people open this page to check.
    @ViewBuilder private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 0) {
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

        }
        .padding(.bottom, 12)
    }

    /// One menu row to the page that explains how data is processed.
    private var privacyRow: some View {
        NavigationLink(destination: SmartTrackerPrivacyPage().detailPage()) {
            HStack(spacing: 14) {
                Image(systemName: "lock.shield").font(.system(size: 20)).foregroundStyle(Color.appText).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Cara data diproses")).font(.app(16, weight: .semibold)).foregroundStyle(Color.appText)
                    Text(L("Apa yang dikirim, dibuang, dan disimpan")).font(.app(12)).foregroundStyle(Color.appTextSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 24).padding(.vertical, 10).frame(minHeight: 60).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static let resetFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        f.locale = AppLanguage.locale
        f.timeZone = TimeZone(identifier: "Asia/Jakarta")
        return f
    }()

    // MARK: Rows

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.app(13, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
            .padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 6)
    }

    private var lock: some View {
        Image(systemName: "lock").font(.system(size: 20)).foregroundStyle(Color.appTextSecondary).frame(width: 44, height: 44)
    }

    private func wayRow<Trailing: View>(_ way: SmartWay, _ detail: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 14) {
            Image(systemName: way.icon).font(.system(size: 20)).foregroundStyle(Color.appText).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(L(way.title)).font(.app(16, weight: .semibold)).foregroundStyle(Color.appText)
                Text(L(detail)).font(.app(12)).foregroundStyle(Color.appTextSecondary)
            }
            Spacer(minLength: 8)
            trailing().frame(minWidth: 51, minHeight: 44)
        }
        .padding(.horizontal, 24).padding(.vertical, 10).frame(minHeight: 60)
    }

    /// Catat otomatis: the ready-made Shortcuts and the triggers that run them. The notification guide now lives inside it.
    private var autoRecordRow: some View {
        NavigationLink(destination: AutoRecordView().detailPage()) {
            HStack(spacing: 14) {
                Image(systemName: "hand.tap").font(.system(size: 20)).foregroundStyle(Color.appText).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Catat otomatis")).font(.app(16, weight: .semibold)).foregroundStyle(Color.appText)
                    Text(L("Notifikasi, ketuk belakang, Tombol Aksi")).font(.app(12)).foregroundStyle(Color.appTextSecondary)
                }
                Spacer(minLength: 8)
                if !plus.isPlus {
                    Text(verbatim: "Plus").font(.app(11, weight: .semibold)).foregroundStyle(Color.appPrimaryText)
                        .padding(.horizontal, 8).padding(.vertical, 2).background(Color.appPrimary.opacity(0.12), in: Capsule())
                }
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 24).padding(.vertical, 10).frame(minHeight: 60).contentShape(Rectangle())
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
