import SwiftUI

/// Profil › Smart Tracker (design 2b): status, the ways of recording (each with its own switch), what is
/// kept on this phone, privacy, and one button to turn the whole thing on or off.
struct SmartTrackerSettingsView: View {
    @ObservedObject private var store = DraftStore.shared
    @EnvironmentObject private var authViewModel: AuthViewModel
    @AppStorage(SmartTrackerConsent.key) private var isOn = false
    @State private var quick = SmartTrackerWays.quick
    @State private var share = SmartTrackerWays.share
    @State private var siri = SmartTrackerWays.siri
    @State private var showsOff = false
    @State private var showsConsent = false
    @State private var isTurningOff = false
    @State private var failed = false

    private var profileId: UUID? { authViewModel.currentUser.flatMap { UUID(uuidString: $0.id) } }
    private var memoryCount: Int { store.memory.reduce(0) { $0 + ($1.categoryId != nil ? 1 : 0) + ($1.accountId != nil ? 1 : 0) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                statusCard.padding(.horizontal, 24).padding(.top, 12).stEnter(0)

                caption(L("Cara mencatat")).stEnter(1)
                VStack(spacing: 0) {
                    toggleRow(.quick, L("Ketik atau ucapkan dari Beranda"), $quick) { SmartTrackerWays.quick = $0 }
                    separator
                    NavigationLink(destination: NotificationSetupGuideView().detailPage()) {
                        wayRow(.notification, L("Diteruskan lewat Shortcuts")) {
                            HStack(spacing: 6) {
                                Text(isOn ? (store.connectedApps.isEmpty ? L("Atur") : L("%lld aplikasi", store.connectedApps.count)) : L("Mati"))
                                    .font(.app(15)).foregroundStyle(Color.appTextSecondary)
                                chevron
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    separator
                    toggleRow(.share, L("Dari menu Bagikan di aplikasi lain"), $share) { SmartTrackerWays.share = $0 }
                    separator
                    toggleRow(.siri, L("“Hai Siri, catat di Saku”"), $siri) { SmartTrackerWays.siri = $0 }
                }
                .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 24).opacity(isOn ? 1 : 0.5).disabled(!isOn).stEnter(2)

                caption(L("Yang tersimpan di HP ini")).stEnter(3)
                VStack(spacing: 0) {
                    NavigationLink(destination: DraftQueueView(userId: authViewModel.currentUser?.id ?? "").detailPage()) {
                        storedRow("tray", L("Draf menunggu"), L("Terhapus sendiri setelah 30 hari"), trailing: store.drafts.isEmpty ? L("Belum ada") : "\(store.drafts.count)", link: true)
                    }
                    .buttonStyle(.plain)
                    separator
                    NavigationLink(destination: SmartTrackerMemoryView().detailPage()) {
                        storedRow("brain", L("Ingatan Saku"), L("Kategori dan dompet favoritmu"), trailing: memoryCount == 0 ? L("Belum ada") : "\(memoryCount)", link: true)
                    }
                    .buttonStyle(.plain)
                    separator
                    storedRow("textformat", L("Kalimat asli"), L("Dihapus begitu draf jadi"), trailing: L("Tidak disimpan"), link: false)
                }
                .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 24).stEnter(4)

                caption(L("Privasi")).stEnter(5)
                NavigationLink(destination: SmartTrackerPrivacyView().detailPage()) {
                    storedRow("checkmark.shield", L("Cara data diproses"), L("Di HP, di server, dan berapa lama"), trailing: "", link: true)
                        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)

                Button { isOn ? (showsOff = true) : (showsConsent = true) } label: {
                    ZStack {
                        if isTurningOff { ProgressView() } else if isOn {
                            Text(L("Matikan Smart Tracker"))
                        } else {
                            Label(L("Aktifkan Smart Tracker"), systemImage: "sparkles")
                        }
                    }
                    .font(.app(17, weight: .semibold))
                    .foregroundStyle(isOn ? Color.stDangerText : Color.stInkText)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(isOn ? Color.stDangerBg : Color.stInk, in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
                .padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 40).stEnter(6)
            }
        }
        .background(Color.appBackground)
        .navigationTitle("Smart Tracker")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsConsent) { SmartTrackerConsentSheet(profileId: profileId) { showsConsent = false } }
        .confirmDialog(isPresented: $showsOff, icon: "power", destructive: true, title: L("Matikan Smart Tracker?"),
                       message: L("Semua cara mencatat berhenti. %lld draf dan %lld ingatan dihapus dari HP ini. Transaksi yang sudah tersimpan tetap aman.",
                                  store.drafts.count, memoryCount),
                       confirmTitle: L("Matikan dan hapus"), isBusy: isTurningOff) { turnOff() }
        .confirmDialog(isPresented: $failed, icon: "exclamationmark.triangle", title: L("Gagal mematikan Smart Tracker"),
                       message: L("Periksa koneksi internetmu lalu coba lagi. Pengaturanmu belum berubah."), confirmTitle: nil, cancelTitle: L("Tutup"))
    }

    // MARK: Pieces

    private var statusCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles").font(.system(size: 21))
                .foregroundStyle(isOn ? Color.stGreen : Color.appTextTertiary)
                .frame(width: 44, height: 44).background(Color.stRaised, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text(isOn ? L("Smart Tracker aktif") : L("Smart Tracker belum aktif")).font(.app(16, weight: .semibold))
                Text(isOn ? (SmartTrackerConsent.since.map { L("Aktif sejak %@", Self.sinceFormat.string(from: $0)) } ?? L("Aktif"))
                          : L("Aktifkan untuk mencatat dengan satu kalimat"))
                    .font(.app(13)).foregroundStyle(Color.appTextSecondary)
            }
            Spacer()
        }
        .padding(16)
        .background(isOn ? Color.stSuccessBg : Color.appFill, in: RoundedRectangle(cornerRadius: 16))
        .animation(.easeInOut(duration: 0.3), value: isOn)
    }

    private static let sinceFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        f.locale = AppLanguage.locale
        return f
    }()

    private func caption(_ text: String) -> some View {
        Text(L(text)).font(.app(13, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 8)
    }

    private var separator: some View { Rectangle().fill(Color.appSeparator).frame(height: 1).padding(.leading, 58) }
    private var chevron: some View {
        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.appTextTertiary)
    }

    private func wayRow<Trailing: View>(_ way: SmartWay, _ detail: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Image(systemName: way.icon).font(.system(size: 17)).foregroundStyle(Color.stGreen)
                .frame(width: 32, height: 32).background(Color.stRaised, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 1) {
                Text(L(way.title)).font(.app(16)).foregroundStyle(Color.appText)
                Text(L(detail)).font(.app(12)).foregroundStyle(Color.appTextTertiary)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 62).contentShape(Rectangle())
    }

    private func toggleRow(_ way: SmartWay, _ detail: String, _ value: Binding<Bool>, set: @escaping (Bool) -> Void) -> some View {
        wayRow(way, detail) {
            Toggle("", isOn: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0; set($0) }))
                .labelsHidden().tint(Color.stGreen)
        }
    }

    private func storedRow(_ icon: String, _ title: String, _ detail: String, trailing: String, link: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 19)).foregroundStyle(Color.appTextSecondary).frame(width: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(L(title)).font(.app(16)).foregroundStyle(Color.appText)
                Text(L(detail)).font(.app(12)).foregroundStyle(Color.appTextTertiary)
            }
            Spacer(minLength: 8)
            if !trailing.isEmpty { Text(trailing).font(.app(15)).foregroundStyle(Color.appTextSecondary) }
            if link { chevron }
        }
        .padding(.horizontal, 14).frame(minHeight: 56).contentShape(Rectangle())
    }

    private func turnOff() {
        guard let profileId else { return }
        isTurningOff = true
        Task {
            do {
                try await SupabaseSDK.revokeSmartTrackerConsent(profileId: profileId)
                DraftStore.shared.forgetEverything()
                _ = ShareInbox.drain()
                showsOff = false
            } catch {
                showsOff = false
                failed = true
            }
            isTurningOff = false
        }
    }
}

/// Cara data diproses: the same words as the agreement, any time, with the state of the agreement.
struct SmartTrackerPrivacyView: View {
    var body: some View {
        ScrollView {
            SmartTrackerPrivacyContent().padding(24)
        }
        .background(Color.appBackground)
        .navigationTitle(L("Cara data diproses"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Ingatan Saku (design 2c): what Saku learned from corrections, grouped by what it fills in.
struct SmartTrackerMemoryView: View {
    @ObservedObject private var store = DraftStore.shared
    @State private var showsForgetAll = false

    private var categoryEntries: [MerchantMemory.Entry] { store.memory.filter { $0.categoryId != nil } }
    private var walletEntries: [MerchantMemory.Entry] { store.memory.filter { $0.accountId != nil } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(L("Tiap kali kamu mengoreksi draf, Saku ingat pilihanmu. Jadi lain kali kamu tulis “kopi”, kategorinya langsung Jajan & Kopi."))
                    .font(.app(15)).lineSpacing(3).foregroundStyle(Color.appBody).padding(.horizontal, 24).padding(.top, 12)
                if store.memory.isEmpty {
                    STEmptyHero(icon: "brain", tint: .stGreen, fill: .stSuccessBg, title: "Belum ada ingatan",
                                message: "Koreksi kategori atau dompet di draf, dan Saku akan mengingatnya untuk lain kali.")
                        .padding(.top, 56)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("Contohnya nanti")).font(.app(12, weight: .semibold)).foregroundStyle(Color.appTextTertiary)
                        exampleRow("kopi", icon: "cup.and.saucer", result: "Jajan & Kopi")
                        exampleRow("gopay", icon: "wallet.bifold", result: "GoPay")
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.stDash, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                    .padding(.horizontal, 24).padding(.top, 32).stEnter(3)
                    Text(L("Ingatan hanya disimpan di HP ini dan bisa dilupakan kapan saja."))
                        .font(.app(13)).lineSpacing(2).foregroundStyle(Color.appTextTertiary)
                        .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 60).stEnter(4)
                } else {
                    group(L("Kata → kategori"), L("Mengisi kategori"), categoryEntries, .category)
                    group(L("Kata → dompet"), L("Mengisi dompet"), walletEntries, .account)
                    Text(L("Melupakan ingatan tidak mengubah transaksi yang sudah tersimpan."))
                        .font(.app(13)).foregroundStyle(Color.appTextTertiary).padding(.horizontal, 24).padding(.top, 18)
                    Button { showsForgetAll = true } label: {
                        Text(L("Lupakan semua")).font(.app(16, weight: .semibold)).foregroundStyle(Color.stDangerText)
                            .frame(maxWidth: .infinity).frame(height: 44)
                    }
                    .padding(.top, 16).padding(.bottom, 60)
                }
            }
        }
        .background(Color.appBackground)
        .navigationTitle(L("Ingatan"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmDialog(isPresented: $showsForgetAll, icon: "brain", destructive: true, title: L("Lupakan semua?"),
                       message: L("Semua pilihan yang diingat dihapus. Transaksi yang sudah tersimpan tidak berubah."),
                       confirmTitle: L("Lupakan semua")) {
            store.forgetMemory()
            showsForgetAll = false
        }
    }

    private func exampleRow(_ word: String, icon: String, result: String) -> some View {
        HStack(spacing: 10) {
            Text(word).font(.app(15)).padding(.horizontal, 10).frame(height: 30).background(Color.stChip, in: RoundedRectangle(cornerRadius: 8))
            Image(systemName: "arrow.right").font(.system(size: 13)).foregroundStyle(Color.appTextTertiary)
            Label(L(result), systemImage: icon).font(.app(15, weight: .medium)).labelStyle(ExampleLabelStyle())
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ detail: String, _ entries: [MerchantMemory.Entry], _ field: MerchantMemory.Field) -> some View {
        if !entries.isEmpty {
            HStack {
                Text(L(title)).font(.app(13, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
                Spacer()
                Text(L(detail)).font(.app(12)).foregroundStyle(Color.appTextTertiary)
            }
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 6)
            ForEach(entries) { entry in
                let category = store.categories.first { $0.id == entry.categoryId }
                let wallet = store.accounts.first { $0.id == entry.accountId }
                HStack(spacing: 10) {
                    Text(entry.keyword).font(.app(15)).lineLimit(1)
                        .padding(.horizontal, 10).frame(height: 30).background(Color.stChip, in: RoundedRectangle(cornerRadius: 8))
                    Image(systemName: "arrow.right").font(.system(size: 13)).foregroundStyle(Color.appTextTertiary)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Image(systemName: field == .category ? (category?.icon ?? "tag") : "wallet.bifold")
                                .font(.system(size: 15)).foregroundStyle(Color.appTextSecondary)
                            Text(field == .category ? (category?.name ?? "—") : (wallet?.name ?? "—"))
                                .font(.app(15, weight: .medium)).lineLimit(1)
                        }
                        Text(L("%lld kali dipakai", entry.uses)).font(.app(12)).foregroundStyle(Color.appTextTertiary)
                    }
                    Spacer(minLength: 0)
                    Button { withAnimation(.easeInOut(duration: 0.3)) { store.forget(entry, field: field) } } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.appTextTertiary)
                            .frame(width: 36, height: 36)
                    }
                    .accessibilityLabel(L("Lupakan"))
                }
                .padding(.leading, 24).padding(.trailing, 14).padding(.vertical, 8)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.appSeparator).frame(height: 1) }
                .transition(.opacity)
            }
        }
    }
}

/// Notifikasi bank (design 2d): how to connect each bank or e-wallet app through a Shortcuts automation.
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

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            Text("BCA").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                                .frame(width: 30, height: 30).background(Color(hex: "0066AE"), in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading) {
                                Text("BCA mobile").font(.app(13, weight: .semibold))
                                Text(L("Transfer Rp500.000 ke BIBIT berhasil")).font(.app(13)).foregroundStyle(Color.appBody).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10).background(Color.stRaised, in: RoundedRectangle(cornerRadius: 14))
                        Image(systemName: "arrow.down").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.appTextTertiary)
                        HStack(spacing: 10) {
                            Image(systemName: "tray").font(.system(size: 15)).foregroundStyle(Color.stGreen)
                                .frame(width: 30, height: 30).background(Color.stSuccessBg, in: Circle())
                            Text(L("Draf menunggu di Perlu dicek")).font(.app(14, weight: .medium))
                            Spacer(minLength: 0)
                            Text("Rp500.000").font(.app(14)).monospacedDigit()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10).background(Color.stRaised, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(14).background(Color.appFill, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 24).padding(.top, 12)

                    Text(L("Setiap ada notifikasi transaksi, Shortcuts di iPhone meneruskannya ke Saku. Atur sekali saja untuk tiap aplikasi."))
                        .font(.app(15)).lineSpacing(3).foregroundStyle(Color.appBody).padding(.horizontal, 24).padding(.top, 16)

                    Text(L("Sudah terhubung")).font(.app(13, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
                        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 8)
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
                        .padding(.horizontal, 24)
                    } else {
                        FlowLayout(spacing: 6) {
                            ForEach(store.connectedApps, id: \.self) { app in
                                Label(app, systemImage: "checkmark.circle.fill")
                                    .font(.app(14, weight: .semibold)).foregroundStyle(Color.stSuccessText)
                                    .padding(.horizontal, 12).frame(height: 32)
                                    .background(Color.stSuccessBg, in: Capsule())
                            }
                        }
                        .padding(.horizontal, 24)
                    }

                    Text(L("Cara menghubungkan")).font(.app(13, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
                        .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 8)
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
                    .padding(.horizontal, 24)

                    Text(L("Bisa dipakai untuk")).font(.app(13, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
                        .padding(.horizontal, 24).padding(.top, 4).padding(.bottom, 8)
                    FlowLayout(spacing: 6) {
                        ForEach(NotificationParser.supportedApps, id: \.self) { app in
                            Text(app).font(.app(14)).padding(.horizontal, 12).frame(height: 30).background(Color.stChip, in: Capsule())
                        }
                    }
                    .padding(.horizontal, 24)

                    Label(L("Saku hanya membaca notifikasi untuk membuat draf, lalu langsung menghapusnya. Tidak ada yang tercatat sebelum kamu cek."),
                          systemImage: "lock")
                        .font(.app(13)).lineSpacing(2).foregroundStyle(Color.appTextTertiary).padding(.horizontal, 24).padding(.top, 16)
                    Color.clear.frame(height: 130)
                }
            }
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
        .background(Color.appBackground)
        .navigationTitle(L("Notifikasi bank"))
        .navigationBarTitleDisplayMode(.inline)
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
