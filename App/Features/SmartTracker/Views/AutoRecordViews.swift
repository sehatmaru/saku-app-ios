import SwiftUI

/// The two Shortcuts the owner shares through iCloud. Every recipe below runs one of them; Saku cannot see whether a
/// Shortcut is installed, only that it ran, so the time of the last run is what the pages show.
enum SakuShortcut: String, CaseIterable, Identifiable {
    case screenshot, notification

    var id: String { rawValue }

    /// The Shortcut's own name, as it appears in Shortcuts and in Settings. Not translated.
    var name: String {
        switch self {
        case .screenshot: "Screenshot To Saku"
        case .notification: "Notification Record To Saku"
        }
    }

    var url: URL {
        switch self {
        case .screenshot: URL(string: "https://www.icloud.com/shortcuts/da2c810a80ef4217b18a35ff41cbecb4")!
        case .notification: URL(string: "https://www.icloud.com/shortcuts/716543278f364045a3925ff1836510f0")!
        }
    }

    var icon: String { self == .screenshot ? "camera.viewfinder" : "bell" }

    var purpose: String {
        self == .screenshot ? L("Membaca layar atau screenshot jadi draf") : L("Meneruskan notifikasi bank jadi draf")
    }

    private var runKey: String { "sakuShortcut.lastRun." + rawValue }
    private var openedKey: String { "sakuShortcut.opened." + rawValue }

    /// Called by the intent the Shortcut runs.
    func noteRun() { UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: runKey) }

    var lastRun: Date? {
        let t = UserDefaults.standard.double(forKey: runKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    /// The install link was opened from Saku at least once on this iPhone.
    var wasOpened: Bool {
        get { UserDefaults.standard.bool(forKey: openedKey) }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: openedKey) }
    }

    var lastRunText: String? {
        guard let date = lastRun else { return nil }
        let time = DateFormatter.arrivalTime.string(from: date)
        if Calendar.current.isDateInToday(date) { return L("Terakhir jalan hari ini %@", time) }
        return L("Terakhir jalan %@ %@", DateFormatter.shortDay.string(from: date), time)
    }
}

/// One way to make a draft without opening Saku: a trigger on the iPhone runs a Shortcut, the Shortcut hands Saku
/// the notification or the picture, and Saku makes a draft.
enum AutoRecipe: String, CaseIterable, Identifiable {
    case notification, backTap, actionButton, screenshot

    var id: String { rawValue }

    var shortcut: SakuShortcut { self == .notification ? .notification : .screenshot }

    var title: String {
        switch self {
        case .notification: L("Notifikasi bank")
        case .backTap: L("Ketuk belakang")
        case .actionButton: L("Tombol Aksi")
        case .screenshot: L("Screenshot baru")
        }
    }

    var summary: String {
        switch self {
        case .notification: L("Notifikasi transaksi dari bank atau e-wallet langsung jadi draf.")
        case .backTap: L("Ketuk punggung iPhone dua atau tiga kali, layar yang terbuka jadi draf.")
        case .actionButton: L("Tekan Tombol Aksi, layar yang terbuka jadi draf.")
        case .screenshot: L("Setiap screenshot yang tersimpan dibaca jadi draf.")
        }
    }

    var icon: String {
        switch self {
        case .notification: "bell"
        case .backTap: "hand.tap"
        case .actionButton: "button.programmable"
        case .screenshot: "camera.viewfinder"
        }
    }

    /// The trigger is a Shortcuts automation: seen on iOS 27, where "Notification" and "Screenshot" are in the list.
    var isAutomation: Bool { self == .notification || self == .screenshot }

    var isAvailable: Bool { !isAutomation || NotificationTrigger.isAvailable }

    /// What the iPhone needs, said on the row before anyone starts.
    var requirement: String? {
        switch self {
        case .notification, .screenshot: NotificationTrigger.isAvailable ? nil : L("Butuh iOS 27")
        case .actionButton: L("iPhone 15 Pro ke atas")
        case .backTap: nil
        }
    }

    /// The steps after "Pasang pintasan", in Markdown so the names to look for stand out.
    var steps: [String] {
        switch self {
        case .notification:
            [L("Buka Shortcuts, pilih tab **Otomatisasi**, lalu ketuk **+**."),
             L("Pilih pemicu **Notifikasi**, pilih aplikasi bank atau e-wallet-mu, lalu aktifkan **Jalankan Segera**."),
             L("Pilih pintasan **Notification Record To Saku**, lalu ketuk **Selesai**.")]
        case .screenshot:
            [L("Buka Shortcuts, pilih tab **Otomatisasi**, lalu ketuk **+**."),
             L("Pilih pemicu **Screenshot**, lalu aktifkan **Jalankan Segera**."),
             L("Pilih pintasan **Screenshot To Saku**, lalu ketuk **Selesai**.")]
        case .backTap:
            [L("Buka Pengaturan iPhone, lalu **Aksesibilitas**, **Sentuh**, **Ketuk Bagian Belakang**."),
             L("Pilih **Ketuk Dua Kali** atau **Ketuk Tiga Kali**."),
             L("Gulir ke **Pintasan**, lalu pilih **Screenshot To Saku**.")]
        case .actionButton:
            [L("Buka Pengaturan iPhone, lalu **Tombol Tindakan**."),
             L("Geser ke **Pintasan**, lalu pilih **Screenshot To Saku**.")]
        }
    }

    var tryIt: String {
        switch self {
        case .notification: L("Coba sekarang: lakukan satu transaksi kecil, lalu tunggu notifikasinya.")
        case .backTap: L("Coba sekarang: buka struk atau bukti transfer, lalu ketuk punggung iPhone.")
        case .actionButton: L("Coba sekarang: buka struk atau bukti transfer, lalu tekan Tombol Aksi.")
        case .screenshot: L("Coba sekarang: ambil screenshot struk atau bukti transfer.")
        }
    }
}

private func markdown(_ text: String) -> Text {
    Text((try? AttributedString(markdown: text)) ?? AttributedString(text))
}

/// Profil › Smart Tracker › Catat otomatis: install the two Shortcuts once, then pick when they run.
struct AutoRecordView: View {
    @ObservedObject private var plus = PlusStore.shared
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var plusReason: PlusReason?
    /// Bumped when Saku comes back to the front, so "Terakhir jalan" is read again.
    @State private var refresh = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(L("Saku bisa membuat draf sendiri saat sesuatu terjadi di iPhone-mu. Pasang pintasannya sekali, lalu pilih kapan dijalankan."))
                    .font(.app(15)).lineSpacing(3).foregroundStyle(Color.appBody)
                    .padding(.horizontal, 24).padding(.top, 12)

                if !plus.isPlus { plusNote.padding(.horizontal, 24).padding(.top, 16) }

                sectionLabel(L("1. Pasang pintasan"))
                VStack(spacing: 0) {
                    ForEach(SakuShortcut.allCases) { shortcutRow($0) }
                }
                Text(L("Kalau sudah terpasang, lewati langkah ini."))
                    .font(.app(13)).foregroundStyle(Color.appTextSecondary).padding(.horizontal, 24).padding(.top, 4)

                sectionLabel(L("2. Pilih kapan dijalankan"))
                VStack(spacing: 0) {
                    ForEach(AutoRecipe.allCases) { recipeRow($0) }
                }

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lock").font(.system(size: 16)).foregroundStyle(Color.appTextSecondary).padding(.top, 1)
                    Text(L("Semuanya masuk sebagai draf. Tidak ada yang tercatat sebelum kamu cek."))
                        .font(.app(13)).lineSpacing(3).foregroundStyle(Color.appTextSecondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 40)
            }
            .id(refresh)
        }
        .scrollIndicators(.hidden)
        .background(Color.appBackground)
        .navigationTitle(L("Catat otomatis"))
        .navigationBarTitleDisplayMode(.inline)
        .hidesSmartButton()
        .plusOffer($plusReason)
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh += 1 } }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.app(13, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 4)
    }

    /// Reading pictures and notifications is Saku Plus; saying so here saves a failed first try.
    private var plusNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle").font(.system(size: 19)).foregroundStyle(Color.appTextSecondary).padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Catat otomatis butuh Saku Plus")).font(.app(16, weight: .semibold))
                Text(L("Pintasannya bisa dipasang sekarang, tapi draf baru dibuat setelah Saku Plus aktif."))
                    .font(.app(14)).lineSpacing(3).foregroundStyle(Color.appBody)
                Button { plusReason = .aiHelp } label: {
                    Text(L("Lihat Saku Plus")).font(.app(15, weight: .semibold)).foregroundStyle(Color.appPrimaryText)
                        .frame(minHeight: 44, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16).background(Color.stChip, in: RoundedRectangle(cornerRadius: 16))
    }

    private func shortcutRow(_ shortcut: SakuShortcut) -> some View {
        let ran = shortcut.lastRunText
        return HStack(spacing: 14) {
            Image(systemName: shortcut.icon).font(.system(size: 20)).foregroundStyle(Color.appTextSecondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: shortcut.name).font(.app(17)).foregroundStyle(Color.appText)
                if let ran {
                    Label(ran, systemImage: "checkmark.circle.fill").font(.app(13)).foregroundStyle(Color.stSuccessText)
                } else {
                    Text(shortcut.purpose).font(.app(13)).lineSpacing(2).foregroundStyle(Color.appTextSecondary)
                }
            }
            Spacer(minLength: 8)
            InstallButton(shortcut: shortcut, compact: true) { refresh += 1 }
        }
        .padding(.horizontal, 24).padding(.vertical, 12).frame(minHeight: 64)
    }

    private func recipeRow(_ recipe: AutoRecipe) -> some View {
        NavigationLink(destination: AutoRecipeDetailView(recipe: recipe).detailPage()) {
            HStack(spacing: 14) {
                Image(systemName: recipe.icon).font(.system(size: 20)).foregroundStyle(Color.appTextSecondary).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(recipe.title).font(.app(17)).foregroundStyle(Color.appText)
                    Text(recipe.summary).font(.app(13)).lineSpacing(2).foregroundStyle(Color.appTextSecondary)
                        .multilineTextAlignment(.leading)
                    if let need = recipe.requirement {
                        Text(need).font(.app(12, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
                            .padding(.horizontal, 8).padding(.vertical, 2).background(Color.stChip, in: Capsule()).padding(.top, 4)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
            }
            .padding(.horizontal, 24).padding(.vertical, 12).frame(minHeight: 64).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Opens the Shortcut's iCloud page; iOS shows its own "Add Shortcut" sheet from there.
private struct InstallButton: View {
    let shortcut: SakuShortcut
    var compact = false
    var opened: () -> Void = {}
    @Environment(\.openURL) private var openURL

    var body: some View {
        let again = shortcut.wasOpened
        Button {
            shortcut.wasOpened = true
            openURL(shortcut.url)
            opened()
        } label: {
            Text(again ? L("Pasang lagi") : L("Pasang"))
                .font(.app(15, weight: .semibold))
                .foregroundStyle(again ? Color.appText : Color.appBackground)
                .padding(.horizontal, 16).frame(minWidth: compact ? 0 : 120).frame(height: 36)
                .background(again ? Color.stChip : Color.appText, in: Capsule())
                .padding(.vertical, 4).contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(L("Pasang pintasan %@", shortcut.name))
    }
}

/// One recipe: what happens, then the steps, the first of which is the one-tap install.
struct AutoRecipeDetailView: View {
    let recipe: AutoRecipe
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var refresh = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                flow.padding(.top, 12)
                Text(recipe.summary).font(.app(15)).lineSpacing(3).foregroundStyle(Color.appBody).padding(.top, 16)

                if recipe.isAvailable {
                    Text(L("Cara mengatur")).font(.app(13, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
                        .padding(.top, 24).padding(.bottom, 8)
                    steps
                    if recipe == .notification {
                        NavigationLink(destination: NotificationSetupGuideView().detailPage()) {
                            HStack(spacing: 8) {
                                Text(L("Atur aplikasi dan judul notifikasi")).font(.app(15, weight: .semibold)).foregroundStyle(Color.appPrimaryText)
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
                            }
                            .frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).padding(.top, 4)
                    }
                } else {
                    unavailable.padding(.top, 16)
                }
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, 24)
            .id(refresh)
        }
        .scrollIndicators(.hidden)
        .background(Color.appBackground)
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.inline)
        .hidesSmartButton()
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh += 1 } }
    }

    /// Trigger, Shortcut, draft: the same three stops for every recipe.
    private var flow: some View {
        HStack(spacing: 6) {
            stop(recipe.icon, recipe.title)
            arrow
            stop("square.stack.3d.up", L("Pintasan"))
            arrow
            stop("tray.full", L("Draf"), tint: Color.stGreen)
        }
        .padding(16).frame(maxWidth: .infinity).background(Color.appFill, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("%@, lalu pintasan, lalu draf", recipe.title))
    }

    private var arrow: some View {
        Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.appTextTertiary)
    }

    private func stop(_ icon: String, _ label: String, tint: Color = .appTextSecondary) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(tint)
                .frame(width: 44, height: 44).background(Color.stRaised, in: RoundedRectangle(cornerRadius: 12))
            Text(label).font(.app(12, weight: .medium)).foregroundStyle(Color.appTextSecondary)
                .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
    }

    private var steps: some View {
        let texts = recipe.steps
        let count = texts.count + 2
        return VStack(alignment: .leading, spacing: 0) {
            step(1, of: count) {
                VStack(alignment: .leading, spacing: 6) {
                    markdown(L("Pasang pintasan **%@**.", recipe.shortcut.name)).font(.app(15)).lineSpacing(3)
                    InstallButton(shortcut: recipe.shortcut) { refresh += 1 }
                }
            }
            ForEach(Array(texts.enumerated()), id: \.offset) { index, text in
                step(index + 2, of: count) {
                    VStack(alignment: .leading, spacing: 2) {
                        markdown(text).font(.app(15)).lineSpacing(3)
                        if recipe.isAutomation && index == 0 {
                            Button { openURL(URL(string: "shortcuts://create-automation")!) } label: {
                                Label(L("Buka Shortcuts"), systemImage: "arrow.up.forward.app")
                                    .font(.app(15, weight: .semibold)).foregroundStyle(Color.appPrimaryText)
                                    .frame(minHeight: 44, alignment: .leading)
                            }
                        }
                    }
                }
            }
            step(count, of: count) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recipe.tryIt).font(.app(15)).lineSpacing(3)
                    if let ran = recipe.shortcut.lastRunText {
                        Label(ran, systemImage: "checkmark.circle.fill").font(.app(13)).foregroundStyle(Color.stSuccessText)
                    } else {
                        Text(L("Pintasan ini belum pernah jalan di iPhone ini.")).font(.app(13)).foregroundStyle(Color.appTextSecondary)
                    }
                }
            }
        }
    }

    private func step<Content: View>(_ number: Int, of count: Int, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 4) {
                Text("\(number)").font(.app(14, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 28, height: 28).background(Color.stGreen, in: Circle())
                if number < count {
                    Rectangle().fill(Color.stLine).frame(width: 2).frame(maxHeight: .infinity)
                }
            }
            content().padding(.top, 3).padding(.bottom, 18)
            Spacer(minLength: 0)
        }
    }

    private var unavailable: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle").font(.system(size: 19)).foregroundStyle(Color.appTextSecondary).padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Belum tersedia di iOS-mu")).font(.app(16, weight: .semibold))
                Text(L("Pemicu ini ada di Shortcuts mulai iOS 27. Sampai iOS-mu diperbarui, pakai Ketuk belakang atau Tombol Aksi."))
                    .font(.app(14)).lineSpacing(3).foregroundStyle(Color.appBody)
            }
            Spacer(minLength: 0)
        }
        .padding(16).background(Color.stChip, in: RoundedRectangle(cornerRadius: 16))
    }
}
