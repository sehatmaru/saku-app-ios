import SwiftUI
import UserNotifications

// The steps added or redrawn for Enhancement 2 ("Setup awal pendaftaran", design v4): 1 Nama on a pocket,
// 5 Budget, 6 Cara mencatat, 7 Gajian, 8 Saku Plus. Steps 2 to 4 stay as they were.

/// Title and subtitle of a step, rising in one after the other.
struct SetupHeading: View {
    let title: String
    var subtitle: String?
    var size: CGFloat = 30
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: size == 34 ? 12 : 10) {
            Text(title)
                .font(.app(size, weight: .bold))
                .tracking(0.2)
                .foregroundStyle(Color.appText)
                .rise(shown, y: 16, delay: 0, fade: 0.4, move: 0.5)
            if let subtitle {
                Text(subtitle)
                    .font(.app(size == 34 ? 17 : 16))
                    .lineSpacing(2.6)
                    .foregroundStyle(Color.appTextSecondary)
                    .rise(shown, y: 16, delay: 0.06, fade: 0.4, move: 0.5)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .onAppear { shown = true }
    }
}

// MARK: - 1 · Nama (kantong)

/// What the code side of the pocket knows: nothing yet, accepted, or refused.
enum SetupCodeState { case idle, ok, bad }

/// "Siapa namamu?": the name is engraved on a green pocket; "Punya kode ajak?" turns the pocket over to type a
/// friend's code (real accounts only). The code is checked as soon as the sixth character lands.
struct SetupNameStep: View {
    @Binding var name: String
    @Binding var referralCode: String
    var isGuest: Bool
    var codeState: SetupCodeState
    var message: String?
    var isFocused: FocusState<Bool>.Binding
    /// A full code was typed: check it.
    var onCodeComplete: () -> Void
    /// A refused code was shown long enough: clear it.
    var onBadCodeShown: () -> Void
    @State private var flipped = false
    @State private var shakes = 0
    /// The keyboard is up: the pocket shrinks so the switch button stays in the room left above it.
    @State private var compact = false

    private static let engraveInk = Color(hex: "032A1B")

    var body: some View {
        ScrollViewReader { proxy in
            scroll
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                    withAnimation(.settle(0.3)) { compact = true }
                    Task { try? await Task.sleep(for: .milliseconds(350)); withAnimation { proxy.scrollTo("switch", anchor: .bottom) } }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                    withAnimation(.settle(0.3)) { compact = false }
                }
        }
    }

    private var scroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SetupHeading(title: L("Siapa namamu?"), subtitle: L("Kami pakai untuk menyapamu di Beranda."), size: 34)
                    .padding(.top, 8)

                ZStack {
                    pocket(isOpen: !trimmed.isEmpty, side: .name)
                        .scaleEffect(x: flipped ? 0.001 : 1)
                        .animation(.easeIn(duration: 0.35), value: flipped)
                        .allowsHitTesting(!flipped)
                    pocket(isOpen: codeState == .ok, side: .code)
                        .scaleEffect(x: flipped ? 1 : 0.001)
                        .animation(.easeOut(duration: 0.35).delay(flipped ? 0.35 : 0), value: flipped)
                        .allowsHitTesting(flipped)
                }
                .frame(width: 240, height: 256)
                .scaleEffect(compact ? 0.7 : 1, anchor: .top)
                .frame(maxWidth: .infinity)
                .frame(height: compact ? 256 * 0.7 : 256, alignment: .top)
                .padding(.top, 4)

                Text(flipped ? L("Ketik 6 karakter dari temanmu") : L("Ketuk kantong untuk mengetik namamu"))
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, -6)

                if isGuest {
                    guestNote
                } else {
                    Button { toggleSide() } label: {
                        Text(flipped ? L("Kembali ke nama") : L("Punya kode ajak dari teman?"))
                            .font(.app(15, weight: .semibold))
                            .foregroundStyle(Color.appPrimary)
                            .padding(.horizontal, 20)
                            .frame(height: 48)
                            .overlay(Capsule().strokeBorder(Color.appBorder, lineWidth: 1))
                    }
                    .buttonStyle(PressScaleStyle())
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                    .id("switch")

                    status
                }
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .onChange(of: referralCode) { _, value in
            if value.count == 6 { onCodeComplete() }
        }
        .onChange(of: codeState) { _, state in
            switch state {
            case .ok:
                Task { try? await Task.sleep(for: .milliseconds(1400)); if codeState == .ok { toggleSide(to: false) } }
            case .bad:
                withAnimation(.settle(0.5)) { shakes += 1 }
                Task { try? await Task.sleep(for: .seconds(1)); if codeState == .bad { onBadCodeShown() } }
            case .idle:
                break
            }
        }
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func toggleSide(to value: Bool? = nil) {
        let target = value ?? !flipped
        withAnimation(.default) { flipped = target }
        isFocused.wrappedValue = false
    }

    private var guestNote: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "iphone").font(.system(size: 20)).foregroundStyle(Color.appTextSecondary)
            Text("Akun tamu hanya ada di iPhone ini. Jika keluar atau app dihapus, datanya tidak bisa dibuka lagi.")
                .font(.app(14)).lineSpacing(3).foregroundStyle(Color.appBody)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16))
        .padding(.top, 20)
        .padding(.horizontal, 24)
    }

    @ViewBuilder private var status: some View {
        Group {
            if codeState == .ok {
                Text("Kode diterima. Kamu dan temanmu dapat bonus setelah transaksi pertama.")
                    .foregroundStyle(Color.appPrimary)
            } else if let message {
                Text(message).foregroundStyle(Color.appError)
            }
        }
        .font(.app(13))
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .transition(.opacity.combined(with: .offset(y: 8)))
        .animation(.settle(0.35), value: message)
        .animation(.settle(0.35), value: codeState)
    }

    private enum Side { case name, code }

    /// The green pocket with its three cards, floating gently, and the engraved line on its body.
    private func pocket(isOpen: Bool, side: Side) -> some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let drift = -6 * (0.5 - 0.5 * cos(t * 2 * .pi / 4))
            ZStack(alignment: .topLeading) {
                PocketLogo(isOpen: isOpen, motion: { .timingCurve(0.34, 1.45, 0.5, 1, duration: $0) }, pocketColor: .appBrand,
                           stitchColor: .white.opacity(0.5), isPlain: false)
                    .frame(width: 220, height: 220)
                    .offset(x: 10, y: 26)
                engraving(side)
            }
            .frame(width: 240, height: 256, alignment: .topLeading)
            .offset(y: drift)
        }
    }

    @ViewBuilder private func engraving(_ side: Side) -> some View {
        switch side {
        case .name: nameEngraving
        case .code: codeEngraving
        }
    }

    private var nameSize: CGFloat { min(26, max(12, 150 / (CGFloat(max(1, trimmed.count)) * 0.95))) }

    private var nameEngraving: some View {
        ZStack {
            if name.isEmpty {
                Text("NAMAMU").font(.system(size: 26, weight: .heavy)).kerning(1).opacity(0.6).engraved()
            }
            HStack(spacing: 0) {
                ForEach(Array(name.enumerated()), id: \.offset) { _, character in
                    EngravedCharacter(character: character, size: nameSize, kerning: 1)
                }
            }
            // the real field sits on top: invisible text, visible caret
            TextField("", text: $name)
                .focused(isFocused)
                .font(.system(size: nameSize, weight: .heavy))
                .kerning(1)
                .multilineTextAlignment(.center)
                .foregroundStyle(.clear)
                .tint(.white)
                .textContentType(.givenName)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .accessibilityLabel("Nama panggilan")
                .onChange(of: name) { _, value in if value.count > 12 { name = String(value.prefix(12)) } }
        }
        .frame(width: 172, height: 46)
        // the tap area is set before the offset so it moves with the text, and is a bit bigger than it
        .contentShape(Rectangle().inset(by: -14))
        .onTapGesture { isFocused.wrappedValue = true }
        .offset(x: 34, y: 158)
    }

    private var codeEngraving: some View {
        ZStack {
            if referralCode.isEmpty {
                Text("KODE AJAK").font(.system(size: 20, weight: .heavy)).kerning(3).opacity(0.6).engraved()
            }
            HStack(spacing: 0) {
                ForEach(Array(referralCode.enumerated()), id: \.offset) { _, character in
                    EngravedCharacter(character: character, size: 24, kerning: 5)
                }
            }
            TextField("", text: $referralCode)
                .font(.system(size: 24, weight: .heavy))
                .kerning(5)
                .multilineTextAlignment(.center)
                .foregroundStyle(.clear)
                .tint(.white)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .accessibilityLabel("Kode ajak")
                .onChange(of: referralCode) { _, value in
                    let cleaned = String(value.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                    if cleaned != value { referralCode = cleaned }
                }
        }
        .frame(width: 172, height: 46)
        .offset(x: 34, y: 158)
        .modifier(ShakeEffect(shakes: CGFloat(shakes)))
    }
}

private extension View {
    /// The pressed-into-the-metal look of the engraved line.
    func engraved() -> some View {
        // pressed into the green: darker than the pocket, shaded inside along the top edge, lit along the bottom edge
        foregroundStyle(Color(hex: "0B5C3C").shadow(.inner(color: .black.opacity(0.55), radius: 1.2, x: 0, y: 1.6)))
            .shadow(color: .white.opacity(0.4), radius: 0, x: 0, y: 1)
    }
}

/// One letter of the engraved line: it lands large and blurred, then settles into the pocket.
private struct EngravedCharacter: View {
    let character: Character
    let size: CGFloat
    let kerning: CGFloat
    @State private var settled = false

    var body: some View {
        Text(String(character).replacingOccurrences(of: " ", with: "\u{00A0}"))
            .font(.system(size: size, weight: .heavy))
            .kerning(kerning)
            .engraved()
            .opacity(settled ? 1 : 0)
            .blur(radius: settled ? 0 : 5)
            .scaleEffect(settled ? 1 : 1.35)
            .onAppear { withAnimation(.settle(0.45)) { settled = true } }
    }
}

/// A short sideways shake, driven by a counter that goes up each time it should play.
struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(shakes * .pi * 4) * (1 - shakes.truncatingRemainder(dividingBy: 1)), y: 0))
    }
}

// MARK: - 5 · Budget awal

/// Same cards as the starting balances, one per chosen expense category. Every amount may stay empty.
struct SetupBudgetStep: View {
    let categories: [OnboardingCategory]
    @Binding var amounts: [String: Double]
    @Binding var focused: String?

    private static let chips: [(label: String, value: Double)] = [("+100 rb", 100_000), ("+500 rb", 500_000), ("+1 jt", 1_000_000), ("Reset", 0)]
    private var total: Double { categories.reduce(0) { $0 + (amounts[$1.key] ?? 0) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SetupHeading(title: L("Budget awal"), subtitle: L("Isi nominal per kategori. Boleh dikosongkan, bisa diubah nanti."))
                    .padding(.top, 20)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Total budget per periode")
                        .font(.app(15))
                        .foregroundStyle(Color.appTextSecondary)
                    HStack(alignment: .top, spacing: 4) {
                        Text("Rp").font(.app(22)).foregroundStyle(Color.appTextSecondary).padding(.top, 8)
                        CountingText(value: total) { $0.formattedAsDigits() }
                            .font(.app(52, weight: .light))
                            .tracking(-2)
                            .foregroundStyle(Color.appText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .animation(.timingCurve(0.33, 1, 0.68, 1, duration: 0.6), value: total)
                    }
                    .monospacedDigit()
                }
                .padding(.horizontal, 24)
                .padding(.top, 26)

                if categories.isEmpty {
                    Text("Belum ada kategori. Pilih di langkah 4 untuk mengisi budget.")
                        .font(.app(15)).foregroundStyle(Color.appTextSecondary)
                        .padding(.horizontal, 24).padding(.top, 24)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                            card(category)
                                .padding(.top, index == 0 ? 0 : -10)
                                .zIndex(Double(index))
                        }
                        Text("Ketuk kartu untuk mengubah nominal")
                            .font(.app(13)).foregroundStyle(Color.appTextTertiary)
                            .frame(maxWidth: .infinity).padding(.top, 16)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                }
            }
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }

    private func card(_ category: OnboardingCategory) -> some View {
        let isOpen = focused == category.key
        let amount = amounts[category.key] ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: category.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.2), in: Circle())
                Text(category.name).font(.app(15, weight: .bold)).lineLimit(1)
                Spacer(minLength: 8)
                Text("Rp" + amount.formattedAsDigits())
                    .font(.app(17, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .opacity(isOpen ? 0 : 1)
                    .animation(.easeInOut(duration: 0.2), value: isOpen)
            }
            .frame(height: 64)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 3) {
                    Text("Rp").font(.app(17)).opacity(0.8).padding(.top, 5)
                    Text(amount.formattedAsDigits())
                        .font(.app(36, weight: .light))
                        .tracking(-1.2)
                        .contentTransition(.numericText())
                }
                .monospacedDigit()

                HStack(spacing: 6) {
                    ForEach(Self.chips, id: \.label) { chip in
                        Button {
                            withAnimation(.snappy) {
                                focused = category.key
                                amounts[category.key] = chip.value == 0 ? 0 : amount + chip.value
                            }
                        } label: {
                            Text(L(chip.label))
                                .font(.app(13, weight: .semibold))
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(.white.opacity(0.2), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .opacity(isOpen ? 1 : 0)
            .animation(.easeInOut(duration: 0.28).delay(0.14), value: isOpen)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: isOpen ? 172 : 64, alignment: .top)
        .foregroundStyle(.white)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(category.color)
                .overlay(alignment: .topTrailing) {
                    Circle().stroke(.white.opacity(0.12), lineWidth: 1)
                        .frame(width: 220, height: 220)
                        .offset(x: 50, y: -70)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.14), radius: 6, y: -3)
        .animation(.settle(0.48), value: isOpen)
        .contentShape(Rectangle())
        .onTapGesture { focused = isOpen ? nil : category.key }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(category.name), Rp\(amount.formattedAsDigits())")
    }
}

// MARK: - 6 · Cara mencatat

/// Where the notification permission stands in the step.
enum SetupNotificationState { case idle, allowed, denied }

/// Smart Tracker and notifications: two separate switches, each with a plain reason, both optional.
struct SetupTrackingStep: View {
    var isGuest: Bool
    @Binding var tracker: Bool
    @Binding var memorySync: Bool
    @Binding var notification: SetupNotificationState
    @State private var showsConsent = false
    @State private var bellTurn = 0
    @State private var bellShakes = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SetupHeading(title: L("Cara mencatat"), subtitle: L("Dua pilihan, terpisah. Keduanya boleh dilewati."))
                    .padding(.top, 20)

                VStack(spacing: 0) {
                    row(icon: "sparkles", title: L("Smart Tracker"),
                        text: L("Catat otomatis dari notifikasi bank dan e-wallet. Kamu tetap yang mengonfirmasi."),
                        isOn: Binding(get: { tracker }, set: { toggleTracker($0) }), delay: 0.1)
                    Divider().overlay(Color.appDivider)
                    row(icon: "bell", title: L("Notifikasi"), text: notificationText,
                        isOn: Binding(get: { notification == .allowed }, set: { toggleNotification($0) }), delay: 0.2)
                    Divider().overlay(Color.appDivider)
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)

                demo
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
            }
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .task { await readNotificationStatus() }
        .sheet(isPresented: $showsConsent) {
            SetupTrackerConsentSheet(isGuest: isGuest, memorySync: $memorySync) {
                tracker = true
                showsConsent = false
            } onCancel: { showsConsent = false }
        }
    }

    private var notificationText: String {
        notification == .denied ? L("Ditolak. Aktifkan di Pengaturan iPhone untuk pengingat tagihan.")
                                : L("Pengingat tagihan dan konfirmasi transaksi.")
    }

    private func row(icon: String, title: String, text: String, isOn: Binding<Bool>, delay: Double) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.appPrimary)
                .modifier(BellMotion(isBell: icon == "bell", state: notification))
                .frame(width: 40, height: 40)
                .background(Color.appPrimary.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.app(17, weight: .semibold))
                Text(text).font(.app(13)).foregroundStyle(Color.appTextSecondary).lineSpacing(1.5).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn).labelsHidden().tint(.appPrimary)
        }
        .frame(minHeight: 84)
        .padding(.vertical, 8)
        .rise(true, y: 16, delay: delay)
    }

    private func toggleTracker(_ on: Bool) {
        if on { showsConsent = true } else { tracker = false; memorySync = false }
    }

    private func toggleNotification(_ on: Bool) {
        guard on else { notification = .idle; return }
        Task {
            let center = UNUserNotificationCenter.current()
            switch await center.notificationSettings().authorizationStatus {
            case .notDetermined:
                let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
                withAnimation(.settle(0.4)) { notification = granted ? .allowed : .denied }
            case .denied:
                withAnimation(.settle(0.4)) { notification = .denied }
                if let url = URL(string: UIApplication.openSettingsURLString) { await UIApplication.shared.open(url) }
            default:
                withAnimation(.settle(0.4)) { notification = .allowed }
            }
        }
    }

    /// Opening the step shows what the phone already allows.
    private func readNotificationStatus() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if status == .authorized || status == .provisional || status == .ephemeral { notification = .allowed }
        else if status == .denied { notification = .denied }
    }

    /// A bank notification slides in, then turns into a transaction waiting to be confirmed, again and again.
    private var demo: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 5) / 5
            let notif = Self.window(t, fadeIn: (0, 0.1), hold: (0.1, 0.42), fadeOut: (0.42, 0.52))
            let row = Self.window(t, fadeIn: (0.48, 0.60), hold: (0.60, 0.92), fadeOut: (0.92, 1.0))
            ZStack {
                HStack(spacing: 10) {
                    WalletIconView(icon: WalletIcon.allIcons.first { $0.id == "gopay" }, size: 30)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Notifikasi GoPay").font(.app(12)).foregroundStyle(Color.appTextSecondary)
                        Text("Pembayaran Rp18.000 di Gojek").font(.app(14, weight: .semibold))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity).frame(height: 66)
                .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16))
                .opacity(notif)
                .offset(y: t < 0.1 ? -14 * (1 - notif) : (t > 0.42 ? 10 * (1 - notif) : 0))

                HStack(spacing: 10) {
                    Image(systemName: "car").font(.system(size: 18)).foregroundStyle(Color.appTextSecondary)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Transport").font(.app(15, weight: .semibold))
                        Text("Menunggu konfirmasimu").font(.app(12)).foregroundStyle(Color.appTextSecondary)
                    }
                    Spacer(minLength: 0)
                    Text("−Rp18.000").font(.app(16)).monospacedDigit()
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity).frame(height: 66)
                .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16))
                .opacity(row)
                .offset(y: 12 * (1 - row))
            }
            .frame(height: 66)
        }
        .rise(true, y: 0, delay: 0.4, fade: 0.6)
        .accessibilityHidden(true)
    }

    /// 0...1 through a fade in, a hold and a fade out, by position in the loop.
    private static func window(_ t: Double, fadeIn: (Double, Double), hold: (Double, Double), fadeOut: (Double, Double)) -> Double {
        if t < fadeIn.0 { return 0 }
        if t < fadeIn.1 { return (t - fadeIn.0) / (fadeIn.1 - fadeIn.0) }
        if t < hold.1 { return 1 }
        if t < fadeOut.1 { return 1 - (t - fadeOut.0) / (fadeOut.1 - fadeOut.0) }
        return 0
    }
}

/// The bell rings while notifications are on and shakes when they were refused.
private struct BellMotion: ViewModifier {
    let isBell: Bool
    let state: SetupNotificationState
    @State private var shakes = 0

    func body(content: Content) -> some View {
        if isBell {
            switch state {
            case .allowed:
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3) / 3
                    content.rotationEffect(.degrees(Self.ring(t)), anchor: UnitPoint(x: 0.5, y: 0.1))
                }
            case .denied:
                content.modifier(ShakeEffect(shakes: CGFloat(shakes)))
                    .onAppear { withAnimation(.settle(0.5)) { shakes = 1 } }
            case .idle:
                content
            }
        } else {
            content
        }
    }

    /// The keyframes of the design: swings 16, -14, 10, -7, 3 degrees, then rests.
    private static func ring(_ t: Double) -> Double {
        let points: [(Double, Double)] = [(0, 0), (0.1, 16), (0.2, -14), (0.3, 10), (0.4, -7), (0.5, 3), (0.6, 0), (1, 0)]
        for index in 1..<points.count where t <= points[index].0 {
            let (t0, v0) = points[index - 1], (t1, v1) = points[index]
            return v0 + (v1 - v0) * (t - t0) / (t1 - t0)
        }
        return 0
    }
}

/// "Aktifkan Smart Tracker": what is read, what is kept, and the optional Ingatan on the server.
struct SetupTrackerConsentSheet: View {
    var isGuest: Bool
    @Binding var memorySync: Bool
    var onAgree: () -> Void
    var onCancel: () -> Void
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Aktifkan Smart Tracker").font(.app(24, weight: .bold))
            block(icon: "eye", title: "YANG DIBACA",
                  text: L("Teks notifikasi dari aplikasi bank dan e-wallet yang kamu pilih: nominal, nama toko, dan waktu."), delay: 0.1)
                .padding(.top, 20)
            block(icon: "checkmark", title: "YANG DISIMPAN",
                  text: L("Hanya transaksi yang kamu konfirmasi. Isi notifikasi lain tidak disimpan dan tidak dikirim."), delay: 0.18)
                .padding(.top, 16)
            if isGuest {
                Text("Sebagai tamu, semua data tetap di iPhone ini. Ingatan di server tersedia setelah kamu masuk.")
                    .font(.app(13)).foregroundStyle(Color.appTextSecondary).lineSpacing(2)
                    .padding(.top, 18)
            } else {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Simpan Ingatan di server").font(.app(15, weight: .semibold))
                        Text("Kebiasaan kategori dan toko supaya tebakan makin pas. Opsional.")
                            .font(.app(13)).foregroundStyle(Color.appTextSecondary).lineSpacing(1.5)
                    }
                    Spacer(minLength: 8)
                    Toggle("", isOn: $memorySync).labelsHidden().tint(.appPrimary)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16))
                .padding(.top, 18)
                .rise(shown, y: 12, delay: 0.26)
            }
            Spacer(minLength: 20)
            PrimaryButton(title: L("Setuju dan aktifkan")) { onAgree() }
            Button(action: onCancel) {
                Text("Batal").font(.app(17)).foregroundStyle(Color.appTextSecondary)
                    .frame(maxWidth: .infinity).frame(height: 48)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .presentationDetents([.height(isGuest ? 470 : 540)])
        .presentationBackground(Color.appBackground)
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
        .onAppear { shown = true }
    }

    private func block(icon: String, title: String, text: String, delay: Double) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                .frame(width: 36, height: 36).background(Color.appFill, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.app(13, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
                Text(text).font(.app(15)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
        }
        .rise(shown, y: 12, delay: delay)
    }
}

// MARK: - 7 · Gajian

/// "Kapan kamu gajian?": the day grid that exists elsewhere, with a card that shows the running period filling up.
struct SetupPaydayStep: View {
    @Binding var payday: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SetupHeading(title: L("Kapan kamu gajian?"),
                             subtitle: L("Budget dan ringkasanmu dimulai saat gaji masuk, bukan tanggal 1. Boleh dilewati."))
                    .padding(.top, 20)
                    .padding(.bottom, 18)
                PaydayDayPicker(selection: $payday)
                SetupPeriodCard(day: payday ?? 1)
                    .opacity(payday == nil ? 0.5 : 1)
                    .animation(.easeInOut(duration: 0.26), value: payday == nil)
                    .padding(.top, 14)
            }
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }
}

/// The running period for a payday: its dates, a row of ticks (one per day) filled up to today, and what follows.
struct SetupPeriodCard: View {
    let day: Int
    var now = Date()
    @State private var armed = false

    /// Days of the period, the day it is today (counted from 1) and how many are left to the next payday.
    struct Numbers: Equatable {
        let total: Int
        let elapsed: Int
        let left: Int
    }

    static func numbers(day: Int, now: Date, calendar: Calendar = .current) -> Numbers {
        let period = PaydayCycle(day: day).period(containing: now, calendar: calendar)
        let total = max(calendar.dateComponents([.day], from: period.start, to: period.end).day ?? 30, 1)
        let elapsed = min(max((calendar.dateComponents([.day], from: period.start, to: calendar.startOfDay(for: now)).day ?? 0) + 1, 1), total)
        return Numbers(total: total, elapsed: elapsed, left: total - elapsed + 1)
    }

    var body: some View {
        let cycle = PaydayCycle(day: day)
        let n = Self.numbers(day: day, now: now)
        let period = cycle.period(containing: now)
        let next = PaydayCycle.dayMonth.string(from: period.end)
        let start = PaydayCycle.dayMonth.string(from: period.start)
        VStack(alignment: .leading, spacing: 0) {
            Text("Periode sekarang").font(.app(13)).foregroundStyle(Color.appTextSecondary)
            Text(cycle.rangeLabel(for: now)).font(.app(24, weight: .light)).tracking(-0.3).monospacedDigit().padding(.top, 2)
                .contentTransition(.numericText())

            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(0..<n.total, id: \.self) { index in
                            let isToday = index == n.elapsed - 1
                            RoundedRectangle(cornerRadius: 1)
                                .fill(isToday ? Color.appText : (armed && index < n.elapsed ? Color.appPrimary : Color.appBorder.opacity(0.5)))
                                .frame(height: isToday ? 30 : 22)
                                .animation(.easeInOut(duration: 0.35).delay(Double(index) * 0.01), value: armed)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                    Text("Hari ini")
                        .font(.app(12, weight: .semibold))
                        .foregroundStyle(Color.appBackground)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Color.appText, in: Capsule())
                        .fixedSize()
                        .position(x: proxy.size.width * (CGFloat(n.elapsed) - 0.5) / CGFloat(n.total), y: -4)
                        .animation(.settle(0.5), value: n.elapsed)
                }
            }
            .frame(height: 30)
            .padding(.top, 34)

            HStack {
                Text(L("Gajian %@", start))
                Spacer()
                Text(L("Gajian %@", next))
            }
            .font(.app(12)).foregroundStyle(Color.appTextSecondary).monospacedDigit().padding(.top, 8)

            (Text(L("Hari ke-")) + Text("\(n.elapsed)").fontWeight(.bold) + Text(L(" dari %lld. ", n.total))
                + Text(L("%lld hari lagi", n.left)).fontWeight(.bold) + Text(L(" sampai gajian berikutnya.")))
                .font(.app(14)).lineSpacing(2).padding(.top, 12)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bell").font(.system(size: 16)).foregroundStyle(Color.appPrimary).padding(.top, 1)
                (Text(L("Pengingat menjelang gajian ")) + Text(next).fontWeight(.bold))
                    .font(.app(14)).lineSpacing(2)
            }
            .padding(.top, 12)

            if day >= 29 {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sparkles").font(.system(size: 16)).foregroundStyle(Color.appPrimary).padding(.top, 1)
                    (Text(L("Di bulan yang lebih pendek, dipakai ")) + Text(L("tanggal terakhir")).fontWeight(.bold))
                        .font(.app(14)).lineSpacing(2)
                }
                .padding(.top, 10)
                .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 24)
        .animation(.settle(0.3), value: day)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { armed = true } }
    }
}

// MARK: - 8 · Saku Plus

/// "Coba Plus gratis 7 hari": what Plus gives and a seven-day strip that walks through the trial. The two buttons
/// ("Coba 7 hari", "Nanti saja") are the step's footer, in the parent.
struct SetupPlusStep: View {
    @State private var day = 1
    @State private var autoplay = true

    private static let perks: [(icon: String, title: String, text: String)] = [
        ("sparkles", "Bantuan AI tanpa batas", "Tanya soal uangmu kapan saja."),
        ("doc.text", "Laporan PDF", "Ekspor ringkasan bulanan."),
        ("chart.line.uptrend.xyaxis", "Analisis keuangan", "Pola belanja dan perkiraan sisa periode."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 13, weight: .semibold))
                    Text("Saku Plus").font(.app(13, weight: .semibold))
                }
                .foregroundStyle(Color.appPrimary)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Color.appPrimary.opacity(0.12), in: Capsule())
                .padding(.horizontal, 24)
                .rise(true, y: 16)
                .padding(.top, 20)

                SetupHeading(title: L("Coba Plus gratis 7 hari"),
                             subtitle: L("Uji coba mulai saat kamu memilih bergabung. Batalkan kapan saja sebelum berakhir."))
                    .padding(.top, 10)

                VStack(spacing: 0) {
                    ForEach(Array(Self.perks.enumerated()), id: \.offset) { index, perk in
                        HStack(spacing: 14) {
                            Image(systemName: perk.icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.appPrimary)
                                .frame(width: 40, height: 40).background(Color.appPrimary.opacity(0.12), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L(perk.title)).font(.app(16, weight: .semibold))
                                Text(L(perk.text)).font(.app(13)).foregroundStyle(Color.appTextSecondary).lineSpacing(1.5)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 56).padding(.vertical, 4)
                        .rise(true, y: 16, delay: 0.2 + Double(index) * 0.08)
                    }
                }
                .padding(.horizontal, 24).padding(.top, 14)

                trial
                    .padding(.horizontal, 24).padding(.top, 14)
                    .rise(true, y: 16, delay: 0.4)
            }
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .task(id: autoplay) {
            guard autoplay else { return }
            day = 1
            while day < 7 {
                try? await Task.sleep(for: .milliseconds(850))
                if Task.isCancelled { return }
                withAnimation(.settle(0.5)) { day += 1 }
            }
        }
    }

    private var info: (title: String, text: String) {
        switch day {
        case 1: (L("Hari 1 · Mulai"), L("Semua fitur Plus terbuka. Belum ada tagihan."))
        case 5: (L("Hari 5 · Pengingat"), L("Kami kirim pengingat sebelum uji coba berakhir."))
        case 6: (L("Hari 6 · Besok berakhir"), L("Kamu masih bisa batal kapan saja."))
        case 7: (L("Hari 7 · Uji coba berakhir"), L("Batalkan kapan saja sebelum itu, tanpa biaya."))
        default: (L("Hari %lld · Pakai sepuasnya", day), L("Tanya AI, ekspor laporan, dan lihat analisis tanpa batas."))
        }
    }

    private var trial: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Ketuk hari untuk melihat apa yang terjadi").font(.app(13)).foregroundStyle(Color.appTextSecondary).padding(.horizontal, 2)
            ZStack {
                GeometryReader { proxy in
                    Rectangle().fill(Color.appBorder.opacity(0.4)).frame(height: 2).padding(.horizontal, 14).offset(y: 13)
                    Rectangle().fill(Color.appPrimary).frame(width: (proxy.size.width - 28) * CGFloat(day - 1) / 6, height: 2)
                        .offset(x: 14, y: 13)
                        .animation(.settle(0.5), value: day)
                }
                HStack {
                    ForEach(1...7, id: \.self) { index in
                        let reached = index <= day
                        Button {
                            autoplay = false
                            withAnimation(.settle(0.3)) { day = index }
                        } label: {
                            Text("\(index)")
                                .font(.app(12, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(reached ? .white : Color.appTextSecondary)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(reached ? Color.appPrimary : Color.appBackground))
                                .overlay(Circle().strokeBorder(reached ? Color.appPrimary : Color.appBorder.opacity(0.5), lineWidth: 2))
                                .scaleEffect(index == day ? 1.2 : 1)
                                .animation(.settle(0.3), value: day)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(height: 28)
            .padding(.top, 14)
            VStack(alignment: .leading, spacing: 3) {
                Text(info.title).font(.app(17, weight: .semibold))
                Text(info.text).font(.app(14)).foregroundStyle(Color.appTextSecondary).lineSpacing(2)
            }
            .id(day)
            .transition(.opacity.combined(with: .offset(y: day % 2 == 0 ? 12 : 12)))
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
            .padding(.top, 14)
            .animation(.settle(0.35), value: day)
        }
        .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 16)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 20))
    }
}
