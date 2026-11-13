import SwiftUI

/// The two Shortcuts the owner shares through iCloud. Every recipe below runs one of them; Saku cannot see whether a
/// Shortcut is installed, only that it ran, so the time of the last run is what the pages show.
enum SakuShortcut: String, CaseIterable, Identifiable {
    case screenshot, notification

    var id: String { rawValue }

    /// A short label for the tile.
    var short: String { self == .screenshot ? L("Layar") : L("Notifikasi") }

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

/// One piece of a step: a place to tap, shown as a chip with its icon, or the word between two choices.
enum StepPart {
    case chip(String, String)
    case or

    var spoken: String {
        switch self {
        case .chip(_, let label): label
        case .or: L("atau")
        }
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

    /// What the iPhone needs, said on the tile before anyone starts.
    var requirement: String? {
        switch self {
        case .notification, .screenshot: NotificationTrigger.isAvailable ? nil : L("Butuh iOS 27")
        case .actionButton: L("iPhone 15 Pro ke atas")
        case .backTap: nil
        }
    }

    /// The steps after the install, each a path of places to tap.
    var steps: [[StepPart]] {
        let shortcuts: StepPart = .chip("square.stack.3d.up", L("Pintasan"))
        let mine: StepPart = .chip(shortcut.icon, shortcut.name)
        let settings: StepPart = .chip("gearshape", L("Pengaturan"))
        let newAutomation: [StepPart] = [.chip("square.stack.3d.up", "Shortcuts"), .chip("clock.arrow.2.circlepath", L("Otomatisasi")), .chip("plus", L("Baru"))]
        let run: StepPart = .chip("play.circle", L("Jalankan Segera"))
        let done: StepPart = .chip("checkmark", L("Selesai"))
        switch self {
        case .notification:
            return [newAutomation, [.chip("bell", L("Notifikasi")), .chip("building.columns", L("Aplikasi bank")), run], [mine, done]]
        case .screenshot:
            return [newAutomation, [.chip("camera.viewfinder", "Screenshot"), run], [mine, done]]
        case .backTap:
            return [[settings, .chip("accessibility", L("Aksesibilitas")), .chip("hand.point.up.left", L("Sentuh")), .chip("hand.tap", L("Ketuk Bagian Belakang"))],
                    [.chip("2.circle", L("Ketuk Dua Kali")), .or, .chip("3.circle", L("Ketuk Tiga Kali"))],
                    [shortcuts, mine]]
        case .actionButton:
            return [[settings, .chip("button.programmable", L("Tombol Tindakan"))], [shortcuts, mine]]
        }
    }

    var tryIt: String {
        switch self {
        case .notification: L("Lakukan satu transaksi kecil")
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
            let t = reduceMotion ? 1 : loopTime(context.date, seconds: 2.4)
            let recipe = AutoRecipe.allCases[reduceMotion ? 0 : Int(seconds / 2.4) % AutoRecipe.allCases.count]
            HStack(spacing: 8) {
                tile(recipe.icon, lit: t < 0.34, tint: .appText).id(recipe.id).transition(.opacity)
                track(eased(t, 0.1, 0.45))
                tile("square.stack.3d.up", lit: t >= 0.34 && t < 0.7, tint: .appText)
                track(eased(t, 0.45, 0.8))
                tile("tray.full", lit: t >= 0.7, tint: .stGreen)
            }
        }
        .padding(16).frame(maxWidth: .infinity).background(Color.appFill, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Pemicu, lalu pintasan, lalu draf"))
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
            let t = reduceMotion ? 0.88 : loopTime(context.date, seconds: 4.2)
            VStack(spacing: 14) {
                phone(t).opacity(1 - eased(t, 0.95, 1))
                HStack(spacing: 6) {
                    stage(recipe.icon, recipe.title, on: t < 0.4)
                    stage("square.stack.3d.up", L("Pintasan"), on: t >= 0.4 && t < 0.62)
                    stage("tray.full", L("Draf"), on: t >= 0.62)
                }
            }
        }
        .padding(.vertical, 18).frame(maxWidth: .infinity).background(Color.appFill, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("%@, lalu pintasan, lalu draf", recipe.title))
    }

    private func stage(_ icon: String, _ label: String, on: Bool) -> some View {
        Label(label, systemImage: icon).font(.app(12, weight: .semibold)).lineLimit(1)
            .foregroundStyle(on ? Color.stSuccessText : Color.appTextSecondary)
            .padding(.horizontal, 10).frame(height: 28)
            .background(on ? Color.stSuccessBg : Color.stRaised, in: Capsule())
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

/// Profil › Smart Tracker › Catat otomatis: install the two Shortcuts once, then pick when they run.
struct AutoRecordView: View {
    @ObservedObject private var plus = PlusStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var plusReason: PlusReason?
    /// Bumped when Saku comes back to the front, so "Terakhir jalan" is read again.
    @State private var refresh = 0

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FlowHero().padding(.top, 12)
                Text(L("Pasang pintasan, pilih pemicunya, lalu draf masuk sendiri."))
                    .font(.app(15)).lineSpacing(3).foregroundStyle(Color.appBody).padding(.top, 14)

                if !plus.isPlus { plusNote.padding(.top, 16) }

                sectionLabel(L("1. Pasang pintasan"))
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(SakuShortcut.allCases) { shortcutTile($0) }
                }

                sectionLabel(L("2. Pilih pemicu"))
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(AutoRecipe.allCases) { recipeTile($0) }
                }

                Label(L("Semuanya masuk sebagai draf. Tidak ada yang tercatat sebelum kamu cek."), systemImage: "lock")
                    .font(.app(13)).lineSpacing(3).foregroundStyle(Color.appTextSecondary)
                    .padding(.top, 20).padding(.bottom, 40)
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
            .padding(.top, 24).padding(.bottom, 10)
    }

    /// Reading pictures and notifications is Saku Plus; saying so here saves a failed first try.
    private var plusNote: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle").font(.system(size: 19)).foregroundStyle(Color.appTextSecondary)
            Text(L("Catat otomatis butuh Saku Plus")).font(.app(15, weight: .semibold))
            Spacer(minLength: 8)
            Button { plusReason = .aiHelp } label: {
                Text(L("Lihat")).font(.app(15, weight: .semibold)).foregroundStyle(Color.appPrimaryText).frame(minWidth: 44, minHeight: 44)
            }
        }
        .padding(.leading, 16).padding(.trailing, 8).background(Color.stChip, in: RoundedRectangle(cornerRadius: 16))
    }

    private func shortcutTile(_ shortcut: SakuShortcut) -> some View {
        let ran = shortcut.lastRunText
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: shortcut.icon).font(.system(size: 20)).foregroundStyle(Color.appText)
                    .frame(width: 44, height: 44).background(Color.stRaised, in: RoundedRectangle(cornerRadius: 12))
                Spacer(minLength: 0)
                if ran != nil {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(Color.stGreen)
                        .accessibilityLabel(L("Sudah jalan"))
                }
            }
            Text(shortcut.short).font(.app(17, weight: .semibold)).foregroundStyle(Color.appText).padding(.top, 10)
            Text(ran ?? L("Belum jalan")).font(.app(12)).foregroundStyle(ran == nil ? Color.appTextSecondary : Color.stSuccessText)
                .lineLimit(2).frame(minHeight: 32, alignment: .topLeading).padding(.top, 2)
            InstallButton(shortcut: shortcut, wide: true) { refresh += 1 }.padding(.top, 6)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .contain)
    }

    private func recipeTile(_ recipe: AutoRecipe) -> some View {
        NavigationLink(destination: AutoRecipeDetailView(recipe: recipe).detailPage()) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: recipe.icon).font(.system(size: 20)).foregroundStyle(Color.appText)
                        .frame(width: 44, height: 44).background(Color.stRaised, in: RoundedRectangle(cornerRadius: 12))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.appTextTertiary)
                }
                Text(recipe.title).font(.app(17, weight: .semibold)).foregroundStyle(Color.appText)
                    .lineLimit(1).minimumScaleFactor(0.85).padding(.top, 10)
                Text(recipe.requirement ?? " ").font(.app(12)).foregroundStyle(Color.appTextSecondary).lineLimit(1).padding(.top, 2)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appFill, in: RoundedRectangle(cornerRadius: 20))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(recipe.title)
        .accessibilityHint(recipe.summary)
    }
}

/// Opens the Shortcut's iCloud page; iOS shows its own "Add Shortcut" sheet from there.
private struct InstallButton: View {
    let shortcut: SakuShortcut
    var wide = false
    var opened: () -> Void = {}
    @Environment(\.openURL) private var openURL

    var body: some View {
        let again = shortcut.wasOpened
        Button {
            shortcut.wasOpened = true
            openURL(shortcut.url)
            opened()
        } label: {
            Label(again ? L("Pasang lagi") : L("Pasang"), systemImage: again ? "arrow.clockwise" : "plus")
                .font(.app(15, weight: .semibold))
                .foregroundStyle(again ? Color.appText : Color.appBackground)
                .padding(.horizontal, 16).frame(maxWidth: wide ? .infinity : nil).frame(height: 36)
                .background(again ? (wide ? Color.stRaised : Color.stChip) : Color.appText, in: Capsule())
                .padding(.vertical, 4).contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(L("Pasang pintasan %@", shortcut.name))
    }
}

/// One recipe: the demo on top, then the steps as paths of chips, the first being the one-tap install.
struct AutoRecipeDetailView: View {
    let recipe: AutoRecipe
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var refresh = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RecipeDemo(recipe: recipe).padding(.top, 12)
                Text(recipe.summary).font(.app(15)).lineSpacing(3).foregroundStyle(Color.appBody).padding(.top, 14)

                if recipe.isAvailable {
                    steps.padding(.top, 22)
                    if recipe == .notification {
                        NavigationLink(destination: NotificationSetupGuideView().detailPage()) {
                            HStack(spacing: 8) {
                                Label(L("Pilih aplikasi dan judul"), systemImage: "slider.horizontal.3")
                                    .font(.app(15, weight: .semibold)).foregroundStyle(Color.appPrimaryText)
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

    private var steps: some View {
        let paths = recipe.steps
        let count = paths.count + 2
        return VStack(alignment: .leading, spacing: 0) {
            step(1, of: count) {
                VStack(alignment: .leading, spacing: 6) {
                    chip(recipe.shortcut.icon, recipe.shortcut.name)
                    InstallButton(shortcut: recipe.shortcut) { refresh += 1 }
                }
            }
            ForEach(Array(paths.enumerated()), id: \.offset) { index, parts in
                step(index + 2, of: count) {
                    VStack(alignment: .leading, spacing: 2) {
                        path(parts)
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
                VStack(alignment: .leading, spacing: 6) {
                    chip("play.circle", recipe.tryIt)
                    if let ran = recipe.shortcut.lastRunText {
                        Label(ran, systemImage: "checkmark.circle.fill").font(.app(13)).foregroundStyle(Color.stSuccessText)
                    } else {
                        Text(L("Belum jalan")).font(.app(13)).foregroundStyle(Color.appTextSecondary)
                    }
                }
            }
        }
    }

    /// Places to tap, in order, wrapping onto more lines when they do not fit.
    private func path(_ parts: [StepPart]) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                HStack(spacing: 6) {
                    switch part {
                    case .chip(let icon, let label): chip(icon, label)
                    case .or: Text(L("atau")).font(.app(13)).foregroundStyle(Color.appTextSecondary).frame(height: 32)
                    }
                    if index < parts.count - 1, case .chip = part, case .chip = parts[index + 1] {
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.appTextTertiary)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(parts.map(\.spoken).joined(separator: ", "))
    }

    private func chip(_ icon: String, _ label: String) -> some View {
        Label(label, systemImage: icon).font(.app(14, weight: .semibold)).foregroundStyle(Color.appText)
            .lineLimit(2).padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color.stChip, in: RoundedRectangle(cornerRadius: 10))
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
            content().padding(.bottom, 18)
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
