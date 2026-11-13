import SwiftUI

/// The two Shortcuts the owner shares through iCloud. Every recipe below runs one of them; Saku cannot see whether a
/// Shortcut is installed, only that it ran, so the time of the last run is what the pages show.
enum SakuShortcut: String, CaseIterable, Identifiable {
    case screenshot, notification

    var id: String { rawValue }

    /// The name on the card, as the owner shares it.
    var title: String { self == .screenshot ? "Record Screenshot To Saku" : "Record Notification To Saku" }

    /// The Shortcut's own name, as it appears in Shortcuts and in Settings. Not translated.
    var name: String {
        switch self {
        case .screenshot: "Record Screenshot To Saku"
        case .notification: "Record Notification To Saku"
        }
    }

    var url: URL {
        switch self {
        case .screenshot: URL(string: "https://www.icloud.com/shortcuts/ab6c7e1da8dc4a458670e00abaac3645")!
        case .notification: URL(string: "https://www.icloud.com/shortcuts/d3a93d7813ca477694caea93c960a360")!
        }
    }

    var icon: String { self == .screenshot ? "camera.viewfinder" : "bell" }

    /// The name shown on the button and the sheet.
    var label: String { self == .screenshot ? "Record Screenshot To Saku" : "Record Notification To Saku" }

    var blurb: String {
        self == .screenshot ? L("Membaca screenshot struk atau bukti transfer, lalu menyimpannya sebagai draf.")
                            : L("Membaca notifikasi transaksi dari bank atau e-wallet, lalu menyimpannya sebagai draf.")
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

/// A sentence with its key words in **bold**.
func richText(_ markdown: String) -> Text {
    Text((try? AttributedString(markdown: markdown)) ?? AttributedString(markdown))
}

/// One way to make a draft without opening Saku: a trigger on the iPhone runs a Shortcut, the Shortcut hands Saku
/// the notification or the picture, and Saku makes a draft.
enum AutoRecipe: String, CaseIterable, Identifiable {
    case notification, backTap, actionButton, screenshot

    /// The triggers on the list. Screenshot is no longer one of them (its shortcut still serves Back Tap and Action Button).
    static var allCases: [AutoRecipe] { [.notification, .backTap, .actionButton] }

    var id: String { rawValue }

    var shortcut: SakuShortcut { self == .notification ? .notification : .screenshot }

    var title: String {
        switch self {
        case .notification: L("Notifikasi bank/aplikasi")
        case .backTap: "Back Tap"
        case .actionButton: "Action Button"
        case .screenshot: "Screenshot"
        }
    }

    /// Short enough for the three stages under the demo.
    var stageTitle: String { self == .notification ? L("Notifikasi") : title }

    /// One line under the title on the list.
    var subtitle: String {
        switch self {
        case .notification: L("Transaksi dari notifikasi jadi draf")
        case .backTap: L("Ketuk punggung iPhone dua kali")
        case .actionButton: L("Tekan tombol samping kiri")
        case .screenshot: L("Screenshot struk jadi draf otomatis")
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

    /// What the iPhone needs, shown on the list before anyone starts.
    var requirement: String {
        switch self {
        case .notification, .screenshot: "iOS 27+"
        case .actionButton: "iPhone 15 Pro+"
        case .backTap: "iPhone 8+"
        }
    }

    /// The sentences after the install, one tap or one screen each, the key words in **bold**.
    var steps: [String] {
        let name = "**" + shortcut.name + "**"
        let pick = L("Di daftar pintasan, pilih %@, lalu ketuk **Selesai**.", name)
        let automation = L("Buka Shortcuts, pilih tab **Otomatisasi**, ketuk +, lalu pilih **%@**.", self == .notification ? L("Notifikasi") : "Screenshot")
        switch self {
        case .notification:
            return [L("Buka **%@**, lalu nyalakan **Automation**.", shortcut.name),
                    L("Tambahkan aplikasi bank atau e-wallet lainnya dengan ketuk tanda **+**.")]
        case .screenshot:
            return [automation, L("Aktifkan **Jalankan Segera**, lalu ketuk Berikutnya."), pick]
        case .backTap:
            return [L("Buka **Pengaturan** › **Aksesibilitas** › **Sentuh** › **Ketuk Bagian Belakang**."),
                    L("Pilih **Ketuk Dua Kali** atau **Ketuk Tiga Kali**."),
                    L("Gulir ke bagian **Pintasan**, lalu pilih %@.", name)]
        case .actionButton:
            return [L("Buka **Pengaturan** › **Tombol Tindakan**."),
                    L("Geser ke **Pintasan**, ketuk **Pilih Pintasan**."),
                    L("Pilih %@.", name)]
        }
    }

    var tryIt: String {
        switch self {
        case .notification: L("**Selesai**. Lakukan satu transaksi kecil untuk mencoba.")
        case .backTap: L("Buka struk, lalu ketuk punggung iPhone")
        case .actionButton: L("Buka struk, lalu tekan Tombol Aksi")
        case .screenshot: L("Ambil screenshot struk")
        }
    }
}

/// Eased progress of `t` through the window `a...b` of a looping 0...1 timeline.
private func eased(_ t: Double, _ a: Double, _ b: Double) -> Double {
    let x = min(max((t - a) / (b - a), 0), 1)
    return 1 - pow(1 - x, 3)
}

private func loopTime(_ date: Date, seconds: Double) -> Double {
    date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: seconds) / seconds
}

/// The idea of the whole page in one moving line: something happens, a Shortcut runs, a draft appears.
/// The trigger tile takes the four recipes in turn. With Reduce Motion the line stands still.
private struct FlowHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            let t = reduceMotion ? 1 : loopTime(context.date, seconds: 4)
            let recipe = AutoRecipe.allCases[reduceMotion ? 0 : Int(seconds / 4) % AutoRecipe.allCases.count]
            HStack(spacing: 8) {
                tile(recipe.icon, lit: t < 0.34, tint: .appText).id(recipe.id).transition(.opacity)
                track(eased(t, 0.1, 0.45))
                tile("square.stack.3d.up", lit: t >= 0.34 && t < 0.7, tint: .appText)
                track(eased(t, 0.45, 0.8))
                tile("tray.full", lit: t >= 0.7, tint: .stGreen)
            }
        }
        .padding(.vertical, 8).frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Pemicu, lalu Shortcuts, lalu draf"))
    }

    private func tile(_ icon: String, lit: Bool, tint: Color) -> some View {
        Image(systemName: icon).font(.system(size: 22)).foregroundStyle(lit ? tint : Color.appTextTertiary)
            .frame(width: 52, height: 52).background(Color.stRaised, in: RoundedRectangle(cornerRadius: 14))
            .scaleEffect(lit ? 1.06 : 1)
    }

    /// A line with a dot riding along it.
    private func track(_ progress: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.stLine).frame(height: 2)
                Circle().fill(Color.stGreen).frame(width: 8, height: 8)
                    .offset(x: (geo.size.width - 8) * progress)
                    .opacity(progress > 0 && progress < 1 ? 1 : 0)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 52)
    }
}

/// A small iPhone acting out one recipe on a loop: the trigger, the Shortcut running, the draft arriving.
/// With Reduce Motion it shows the last frame, the draft.
private struct RecipeDemo: View {
    let recipe: AutoRecipe
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = reduceMotion ? 0.88 : loopTime(context.date, seconds: 9)
            HStack(alignment: .center, spacing: 28) {
                phone(t).opacity(1 - eased(t, 0.95, 1))
                VStack(alignment: .leading, spacing: 0) {
                    stage(recipe.icon, recipe.stageTitle, on: t < 0.4, last: false)
                    stage("square.stack.3d.up", "Shortcuts", on: t >= 0.4 && t < 0.62, last: false)
                    stage("tray.full", L("Draf"), on: t >= 0.62, last: true)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("%@, lalu Shortcuts, lalu draf", recipe.title))
    }

    /// One stage of the flow: its icon on a line that runs down to the next one, then its name.
    private func stage(_ icon: String, _ label: String, on: Bool, last: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(on ? Color.stSuccessText : Color.appTextSecondary)
                    .frame(width: 36, height: 36).background(on ? Color.stSuccessBg : Color.stRaised, in: Circle())
                if !last { Rectangle().fill(Color.stLine).frame(width: 2, height: 22) }
            }
            Text(label).font(.app(14, weight: .semibold)).foregroundStyle(on ? Color.appText : Color.appTextSecondary)
                .frame(height: 36, alignment: .leading)
        }
        .animation(.easeInOut(duration: 0.4), value: on)
    }

    private func phone(_ t: Double) -> some View {
        let w: CGFloat = 104, h: CGFloat = 176
        let triggerOut = 1 - eased(t, 0.4, 0.5)
        return ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.stRaised)
            trigger(t).opacity(triggerOut)
            // the Shortcut runs
            Image(systemName: "square.stack.3d.up").font(.system(size: 20)).foregroundStyle(Color.appText)
                .frame(width: 44, height: 44).background(Color.stChip, in: RoundedRectangle(cornerRadius: 12))
                .scaleEffect(0.7 + 0.3 * eased(t, 0.4, 0.5))
                .opacity(eased(t, 0.4, 0.5) * (1 - eased(t, 0.6, 0.7)))
            draft(t).offset(y: 150 - 136 * eased(t, 0.62, 0.8))
        }
        .frame(width: w, height: h)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.appBorder, lineWidth: 1.5))
        .overlay(alignment: .leading) {
            if recipe == .actionButton {
                let pressed = t > 0.08 && t < 0.3
                Capsule().fill(pressed ? Color.stGreen : Color.appBorder).frame(width: 4, height: 24)
                    .offset(x: pressed ? -1 : -3, y: -36)
            }
        }
    }

    /// What starts it, drawn on the phone.
    @ViewBuilder private func trigger(_ t: Double) -> some View {
        switch recipe {
        case .notification:
            HStack(spacing: 6) {
                Image(systemName: "bell.fill").font(.system(size: 11)).foregroundStyle(Color.stGreen)
                VStack(alignment: .leading, spacing: 3) {
                    Capsule().fill(Color.appTextSecondary).frame(width: 40, height: 4)
                    Capsule().fill(Color.appTextTertiary).frame(width: 28, height: 4)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).frame(width: 88, height: 30)
            .background(Color.stChip, in: RoundedRectangle(cornerRadius: 10))
            .offset(y: -130 + 68 * eased(t, 0.03, 0.2))
        case .backTap:
            ZStack {
                // the back of the phone: the camera, then two taps
                RoundedRectangle(cornerRadius: 9).strokeBorder(Color.appBorder, lineWidth: 1.5).frame(width: 34, height: 34).offset(x: -24, y: -58)
                ripple(eased(t, 0.05, 0.22))
                ripple(eased(t, 0.2, 0.37))
                Image(systemName: "hand.point.up.left.fill").font(.system(size: 24)).foregroundStyle(Color.appTextSecondary).offset(x: 10, y: 22)
            }
        case .actionButton:
            ZStack {
                ripple(eased(t, 0.08, 0.3)).offset(x: -52, y: -36)
                screenLines
            }
        case .screenshot:
            ZStack {
                screenLines
                Color.white.opacity(eased(t, 0.05, 0.12) * (1 - eased(t, 0.12, 0.28)) * 0.9)
            }
        }
    }

    private func ripple(_ p: Double) -> some View {
        Circle().strokeBorder(Color.stGreen, lineWidth: 2).frame(width: 44, height: 44)
            .scaleEffect(0.3 + 1.1 * p).opacity(p > 0 && p < 1 ? 1 - p : 0)
    }

    /// A stand-in for whatever is on screen: a receipt.
    private var screenLines: some View {
        VStack(alignment: .leading, spacing: 7) {
            Capsule().fill(Color.appTextSecondary).frame(width: 44, height: 5)
            Capsule().fill(Color.appTextTertiary).frame(width: 64, height: 4)
            Capsule().fill(Color.appTextTertiary).frame(width: 52, height: 4)
            Capsule().fill(Color.appTextTertiary).frame(width: 60, height: 4)
        }
    }

    /// The draft card arriving from below, with its check.
    private func draft(_ t: Double) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Capsule().fill(Color.white.opacity(0.5)).frame(width: 30, height: 4)
                Capsule().fill(Color.white).frame(width: 50, height: 7)
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color.stExpense)
            VStack(alignment: .leading, spacing: 7) {
                Capsule().fill(Color.appTextTertiary).frame(width: 60, height: 4)
                Capsule().fill(Color.appTextTertiary).frame(width: 46, height: 4)
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .frame(width: 84, height: 120)
        .background(Color.appBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.appDivider, lineWidth: 1))
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Color.stGreen)
                .background(Color.appBackground, in: Circle())
                .scaleEffect(eased(t, 0.82, 0.9)).padding(8)
        }
    }
}

/// One line of a plain list: an icon, a title with an optional note under it, and whatever sits at the trailing edge.
private struct ListLine<Trailing: View>: View {
    let icon: String
    let title: String
    var note: String? = nil
    var noteTint: Color = .appTextSecondary
    var divider = true
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Color.appText).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.app(16, weight: .semibold)).foregroundStyle(Color.appText).fixedSize(horizontal: false, vertical: true)
                if let note { Text(note).font(.app(12)).foregroundStyle(noteTint).lineLimit(2).minimumScaleFactor(0.9) }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 10).frame(minHeight: 60)
        .overlay(alignment: .bottom) {
            if divider { Rectangle().fill(Color.appDivider).frame(height: 0.5).padding(.leading, 42) }
        }
    }
}

/// Profil › Smart Tracker › Catat otomatis: install the two Shortcuts once, then pick when they run.
struct AutoRecordView: View {
    @ObservedObject private var plus = PlusStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var plusReason: PlusReason?
    /// Bumped when Saku comes back to the front, so "Terakhir jalan" is read again.
    @State private var refresh = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FlowHero().padding(.top, 8)

                if !plus.isPlus { plusNote.padding(.top, 8) }

                sectionLabel(L("Pilih pemicu"))
                ForEach(Array(AutoRecipe.allCases.enumerated()), id: \.element.id) { index, recipe in
                    recipeLine(recipe, last: index == AutoRecipe.allCases.count - 1)
                }

                Label(L("Semuanya masuk sebagai draf. Tidak ada yang tercatat sebelum kamu cek."), systemImage: "lock")
                    .font(.app(13)).lineSpacing(3).foregroundStyle(Color.appTextSecondary)
                    .padding(.top, 24).padding(.bottom, 40)
            }
            .padding(.horizontal, 24)
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
            .padding(.top, 28).padding(.bottom, 6)
    }

    /// Reading pictures and notifications is Saku Plus; saying so here saves a failed first try.
    private var plusNote: some View {
        ListLine(icon: "info.circle", title: L("Catat otomatis butuh Saku Plus"), divider: false) {
            Button { plusReason = .aiHelp } label: {
                Text(L("Lihat")).font(.app(15, weight: .semibold)).foregroundStyle(Color.appPrimaryText).frame(minWidth: 44, minHeight: 44)
            }
        }
    }

    private func recipeLine(_ recipe: AutoRecipe, last: Bool) -> some View {
        NavigationLink(destination: AutoRecipeDetailView(recipe: recipe).detailPage()) {
            ListLine(icon: recipe.icon, title: recipe.title, note: recipe.subtitle + " · " + recipe.requirement, divider: !last) {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.appTextTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(recipe.title)
        .accessibilityHint(recipe.subtitle)
    }
}


/// Smooth ease in and out of `t` through the window `a...b`.
private func smooth(_ t: Double, _ a: Double, _ b: Double) -> Double {
    let x = min(max((t - a) / (b - a), 0), 1)
    return x * x * (3 - 2 * x)
}

/// How to switch the automation on, acted out on a copy of the Shortcuts card: a finger touches the down arrow, the card
/// opens, the finger goes to the Automation switch and touches it, the switch slides on. The words are the ones
/// Shortcuts shows. The stage keeps one height, so nothing below it moves. With Reduce Motion it stands at the end.
private struct AutomationGuide: View {
    static let apps = ["myBCA", "GoPay", "OVO", "DANA", "Jago", "neobank", "Krom", "+"]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let top: CGFloat = 130
    private let lower: CGFloat = 86

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = reduceMotion ? 0.85 : loopTime(context.date, seconds: 8)
            GeometryReader { geo in
                let pad: CGFloat = 2
                let cardW = geo.size.width - 2 * pad
                let open = smooth(t, 0.26, 0.42)
                let on = smooth(t, 0.66, 0.74)
                let chevron = CGPoint(x: pad + cardW - 23, y: pad + 34)
                let toggle = CGPoint(x: pad + cardW - 34, y: pad + top + 1 + 40 + 1 + 22)
                let start = CGPoint(x: geo.size.width - 24, y: geo.size.height - 6)
                // where the finger is: in from the corner, to the arrow, to the switch, then away
                let toArrow = smooth(t, 0.04, 0.22), toSwitch = smooth(t, 0.46, 0.62), away = smooth(t, 0.82, 0.92)
                let x = start.x + (chevron.x - start.x) * toArrow
                let y = start.y + (chevron.y - start.y) * toArrow
                let fx = x + (toggle.x - chevron.x) * toSwitch + (start.x - toggle.x) * away
                let fy = y + (toggle.y - chevron.y) * toSwitch + (start.y - toggle.y) * away
                // a touch is a quick dip in size
                let press = 1 - 0.28 * (smooth(t, 0.22, 0.25) - smooth(t, 0.25, 0.29)) - 0.28 * (smooth(t, 0.64, 0.67) - smooth(t, 0.67, 0.71))
                let seen = smooth(t, 0.02, 0.06) * (1 - smooth(t, 0.9, 0.95))

                ZStack(alignment: .topLeading) {
                    card(open: open, on: on, width: cardW).padding(pad)
                    Circle().fill(Color.stGreen.opacity(0.22)).overlay(Circle().strokeBorder(Color.stGreen, lineWidth: 2))
                        .frame(width: 34, height: 34).scaleEffect(press)
                        .position(x: fx, y: fy).opacity(seen)
                    badge(1).position(x: chevron.x + 10, y: chevron.y - 22).opacity(smooth(t, 0.12, 0.18) * (1 - smooth(t, 0.44, 0.5)))
                    badge(2).position(x: toggle.x - 46, y: toggle.y).opacity(smooth(t, 0.5, 0.56) * (1 - smooth(t, 0.86, 0.92)))
                }
                .opacity(max(smooth(t, 0, 0.03), reduceMotion ? 1 : 0) * (1 - smooth(t, 0.96, 1)))
            }
        }
        .frame(height: 224)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Ketuk panah bawah, lalu nyalakan Automation"))
    }

    /// The number of the tap, in the colour of the step numbers.
    private func badge(_ n: Int) -> some View {
        Text("\(n)").font(.app(12, weight: .bold)).foregroundStyle(.white)
            .frame(width: 20, height: 20).background(Color.stGreen, in: Circle())
    }

    private func card(open: Double, on: Double, width: CGFloat) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "bell.fill").font(.system(size: 14)).foregroundStyle(Color.appError)
                    Text("When I receive a notification from").font(.app(12, weight: .semibold)).foregroundStyle(Color.appText)
                        .lineLimit(1).fixedSize()
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down.circle").font(.system(size: 22)).foregroundStyle(Color.stGreen)
                        .rotationEffect(.degrees(180 * open))
                }
                .frame(height: 44)
                FlowLayout(spacing: 6) {
                    ForEach(Self.apps, id: \.self) { app in
                        Text(app).font(.app(12, weight: .semibold)).foregroundStyle(Color.appText)
                            .padding(.horizontal, 10).frame(height: 26).background(Color.appFill, in: Capsule())
                    }
                }
                .frame(height: 62, alignment: .topLeading)
            }
            .padding(12)
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle").font(.system(size: 14)).foregroundStyle(Color.appTextSecondary)
                    Text("Add Filter").font(.app(13)).foregroundStyle(Color.appTextSecondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).frame(height: 40)
                Divider()
                HStack {
                    Text("Automation").font(.app(13)).foregroundStyle(Color.appText)
                    Spacer(minLength: 8)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.stChip)
                        Capsule().fill(Color.stGreen).opacity(on)
                        Circle().fill(Color.white).frame(width: 22, height: 22).shadow(color: .black.opacity(0.15), radius: 1.5, y: 1).offset(x: 2 + 20 * on)
                    }
                    .frame(width: 44, height: 26)
                }
                .padding(.horizontal, 12).frame(height: 44)
            }
            .frame(height: lower * open, alignment: .top).clipped().opacity(smooth(open, 0.15, 1))
        }
        .frame(width: width, alignment: .top)
        .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.appBorder, lineWidth: 1))
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// The button on a recipe's first step. Dark while the Shortcut has not run; light with a check once it has.
/// It opens the sheet that adds the Shortcut.
private struct ShortcutButton: View {
    let shortcut: SakuShortcut
    let action: () -> Void

    var body: some View {
        let ran = shortcut.lastRunText
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: ran == nil ? "square.stack.3d.up.fill" : "checkmark").font(.system(size: 17, weight: .bold))
                    .foregroundStyle(ran == nil ? Color.appText : Color.appBackground)
                    .frame(width: 40, height: 40).background(ran == nil ? Color.appBackground : Color.appBackground.opacity(0.22), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(ran == nil ? L("Tambah ke Shortcuts") : L("Terpasang")).font(.app(16, weight: .bold))
                        .foregroundStyle(ran == nil ? Color.appBackground : Color.appBackground)
                    Text(ran ?? shortcut.label).font(.app(13)).foregroundStyle(ran == nil ? Color.appBackground.opacity(0.7) : Color.appBackground.opacity(0.85))
                        .lineLimit(1).minimumScaleFactor(0.85)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ran == nil ? Color.appBackground : Color.appBackground.opacity(0.85))
            }
            .padding(.horizontal, 10).frame(height: 60).frame(maxWidth: .infinity)
            .background(ran == nil ? Color.appText : Color.stGreen, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(L("Tambah ke Shortcuts") + ": " + shortcut.label)
    }
}

/// What the Shortcut is and what it holds, with the button that opens its iCloud page. iOS then shows its own
/// "Add Shortcut" sheet. The preview is a drawing, in the English words Shortcuts itself uses.
private struct ShortcutSheet: View {
    let shortcut: SakuShortcut
    var done: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        let ran = shortcut.lastRunText
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(shortcut.label).font(.app(22, weight: .bold)).tracking(-0.3).foregroundStyle(Color.appText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(shortcut.blurb).font(.app(15)).foregroundStyle(Color.appTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let ran {
                Label(L("Terpasang") + " · " + ran, systemImage: "checkmark.circle").font(.app(13, weight: .semibold))
                    .foregroundStyle(Color.stSuccessText).padding(.horizontal, 12).frame(height: 36)
                    .background(Color.stSuccessBg, in: Capsule())
            }
            preview
        }
        .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .filterSheet {
            SmartSheetFooter(primary: ran == nil ? L("Tambah ke Shortcuts") : L("Tambah ulang ke Shortcuts"), secondary: L("Batal"),
                             onPrimary: {
                shortcut.wasOpened = true
                openURL(shortcut.url)
                done()
                dismiss()
            }) { dismiss() }
        }
        .background(Color.appBackground)
        .presentationDetents([.medium, .large])
    }

    private var preview: some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Configure this automation.").font(.app(12)).foregroundStyle(Color.appTextSecondary)
                    .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 30, alignment: .leading).background(Color.stChip, in: Capsule())
                Label(shortcut == .screenshot ? "When I save a screenshot to" : "When I receive a notification from", systemImage: shortcut == .screenshot ? "camera" : "bell.fill")
                    .font(.app(14, weight: .semibold)).foregroundStyle(Color.appText)
                if shortcut == .screenshot {
                    Text("Photos, Files or Clipboard").font(.app(13)).foregroundStyle(Color.appTextTertiary)
                        .padding(.horizontal, 10).frame(height: 28).background(Color.stChip, in: Capsule())
                } else {
                    FlowLayout(spacing: 6) { ForEach(AutomationGuide.apps, id: \.self) { appChip($0) } }
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.stDash, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))

            if shortcut == .screenshot {
                action("photo", "Get the latest", chip: "1 screenshot")
                actionCard("textformat", "Read image", rows: [("Image", "Latest Screenshots")])
            }
        }
        .padding(10).background(Color.appFill, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityHidden(true)
    }

    private func appChip(_ name: String) -> some View {
        Text(name).font(.app(13, weight: .semibold)).foregroundStyle(Color.appText)
            .padding(.horizontal, 10).frame(height: 28).background(Color.stChip, in: Capsule())
    }

    private func action(_ icon: String, _ title: String, chip: String) -> some View {
        HStack(spacing: 10) {
            actionIcon(icon)
            Text(title).font(.app(14, weight: .semibold)).foregroundStyle(Color.appText)
            Text(chip).font(.app(13)).foregroundStyle(Color.appTextTertiary).padding(.horizontal, 10).frame(height: 28).background(Color.stChip, in: Capsule())
            Spacer(minLength: 0)
        }
        .padding(12).background(Color.appBackground, in: RoundedRectangle(cornerRadius: 16))
    }

    private func actionCard(_ icon: String, _ title: String, rows: [(String, String)]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                actionIcon(icon)
                Text(title).font(.app(14, weight: .semibold)).foregroundStyle(Color.appText)
                Spacer(minLength: 0)
            }
            .padding(12)
            ForEach(rows, id: \.0) { row in
                Divider()
                HStack {
                    Text(row.0).font(.app(14)).foregroundStyle(Color.appText)
                    Spacer(minLength: 8)
                    Text(row.1).font(.app(13)).foregroundStyle(Color.appTextTertiary).padding(.horizontal, 10).frame(height: 28).background(Color.stChip, in: Capsule())
                }
                .padding(.horizontal, 12).frame(height: 44)
            }
            Divider()
            HStack {
                Text("Show When Run").font(.app(14)).foregroundStyle(Color.appText)
                Spacer(minLength: 8)
                Capsule().fill(Color.stChip).frame(width: 40, height: 24).overlay(alignment: .leading) { Circle().fill(Color.appBackground).padding(2) }
            }
            .padding(.horizontal, 12).frame(height: 44)
        }
        .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 16))
    }

    private func actionIcon(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 28, height: 28).background(Color.stGreen, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// One recipe: the demo on top, then the steps as a plain list, the first being the one-tap install.
struct AutoRecipeDetailView: View {
    let recipe: AutoRecipe
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var refresh = 0
    @State private var showsShortcut = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RecipeDemo(recipe: recipe).padding(.top, 8)
                Text(recipe.summary).font(.app(15)).lineSpacing(3).foregroundStyle(Color.appBody).padding(.top, 14)

                if recipe.isAvailable {
                    steps.padding(.top, 24)
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
        .sheet(isPresented: $showsShortcut) { ShortcutSheet(shortcut: recipe.shortcut) { refresh += 1 } }
    }

    private var steps: some View {
        let list = recipe.steps
        let count = list.count + 2
        return VStack(alignment: .leading, spacing: 0) {
            numbered(1, of: count) {
                richText(L("Pasang Shortcuts **%@**.", recipe.shortcut.name))
                ShortcutButton(shortcut: recipe.shortcut) { showsShortcut = true }.padding(.top, 10)
            }
            ForEach(Array(list.enumerated()), id: \.offset) { index, sentence in
                numbered(index + 2, of: count) {
                    richText(sentence)
                    if recipe == .notification && index == 0 { AutomationGuide().padding(.top, 10) }
                }
            }
            numbered(count, of: count) { richText(recipe.tryIt) }
        }
    }

    /// A step: its number on a line that runs down to the next one, then the sentence.
    private func numbered<C: View>(_ number: Int, of count: Int, @ViewBuilder content: () -> C) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 4) {
                Text("\(number)").font(.app(14, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 28, height: 28).background(Color.stGreen, in: Circle())
                if number < count { Rectangle().fill(Color.stGreen.opacity(0.4)).frame(width: 2).frame(maxHeight: .infinity).padding(.bottom, 4) }
            }
            VStack(alignment: .leading, spacing: 0) { content() }
                .font(.app(15)).lineSpacing(3).foregroundStyle(Color.appText)
                .padding(.top, 3).padding(.bottom, 22)
            Spacer(minLength: 0)
        }
    }

    private var unavailable: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle").font(.system(size: 19)).foregroundStyle(Color.appTextSecondary).padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Belum tersedia di iOS-mu")).font(.app(16, weight: .semibold))
                Text(L("Pemicu ini ada di Shortcuts mulai iOS 27. Sampai iOS-mu diperbarui, pakai Back Tap atau Action Button."))
                    .font(.app(14)).lineSpacing(3).foregroundStyle(Color.appBody)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }
}
