import SwiftUI

/// When Beranda asks a guest to save their account (Enhancement 3, US3): after 5 transactions or 3 days, whichever
/// comes first; closing it pauses it for 3 days and the third close ends it for good (Profil stays the way in).
enum GuestCardPolicy {
    static let minTransactions = 5
    static let minDays = 3
    static let pauseDays = 3
    static let maxDismissals = 3
    static let countKey = "guestCardDismissCount"
    static let untilKey = "guestCardHiddenUntil"

    static func shows(isGuest: Bool, transactionCount: Int, signedUpAt: Date?, dismissCount: Int, hiddenUntil: Date?,
                      now: Date = Date()) -> Bool {
        guard isGuest, dismissCount < maxDismissals else { return false }
        if let hiddenUntil, now < hiddenUntil { return false }
        if transactionCount >= minTransactions { return true }
        guard let signedUpAt else { return false }
        return now.timeIntervalSince(signedUpAt) >= Double(minDays) * 86_400
    }

    /// The counters belong to this device's guest, so they start over for another account.
    static func resetCounters() {
        UserDefaults.standard.removeObject(forKey: countKey)
        UserDefaults.standard.removeObject(forKey: untilKey)
    }
}

/// The sign-in screen's two buttons: Apple (dark; off until the Apple provider is configured) and Google (outlined).
struct GuestUpgradeButtons: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "apple.logo").font(.system(size: 20))
                Text("Masuk dengan Apple")
            }
            .font(.app(17, weight: .semibold))
            .foregroundStyle(Color.appBackground)
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(Color.appText, in: Capsule())
            .opacity(0.5)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(L("Belum tersedia"))

            Button { authViewModel.linkGoogleToGuest() } label: {
                HStack(spacing: 10) {
                    if authViewModel.isLinking {
                        ProgressView().tint(Color.appText)
                    } else {
                        Image("GoogleLogo").resizable().scaledToFit().frame(width: 19, height: 19)
                        Text("Masuk dengan Google")
                    }
                }
                .font(.app(17, weight: .semibold))
                .foregroundStyle(Color.appText)
                .frame(maxWidth: .infinity).frame(height: 52)
                .overlay(Capsule().stroke(Color.appBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(authViewModel.isLinking)
        }
    }
}

/// The card on Beranda that reminds a guest to keep their data, without chasing them. Closing it leaves a line that
/// says where to find it again.
struct GuestSaveCard: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @AppStorage(GuestCardPolicy.countKey) private var dismissCount = 0
    @AppStorage(GuestCardPolicy.untilKey) private var hiddenUntil = 0.0
    let transactionCount: Int
    @State private var shown = false
    /// Closed just now: the card is replaced by a note until Beranda is left.
    @State private var justClosed = false

    private var isVisible: Bool {
        authViewModel.welcome == nil && GuestCardPolicy.shows(
            isGuest: authViewModel.currentUser?.isGuest == true,
            transactionCount: transactionCount,
            signedUpAt: SupabaseSDK.client.auth.currentUser?.createdAt,
            dismissCount: dismissCount,
            hiddenUntil: hiddenUntil > 0 ? Date(timeIntervalSince1970: hiddenUntil) : nil)
    }

    var body: some View {
        Group {
            if isVisible {
                card.transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            } else if justClosed, authViewModel.currentUser?.isGuest == true {
                closedNote.transition(.opacity)
            }
        }
        .animation(.settle(0.4), value: isVisible)
        .animation(.settle(0.4), value: justClosed)
    }

    private var closedNote: some View {
        (Text("Kartu ditutup. Kamu bisa masuk kapan saja dari Profil. ")
            + Text("Tampilkan lagi").foregroundStyle(Color.appPrimary))
            .font(.app(13)).foregroundStyle(Color.appTextSecondary)
            .padding(.horizontal, 24).padding(.top, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                dismissCount = max(0, dismissCount - 1)
                hiddenUntil = 0
                justClosed = false
            }
            .accessibilityAddTraits(.isButton)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Amankan datamu").font(.app(17, weight: .semibold)).padding(.trailing, 40)
            Text("Masuk supaya datamu tetap ada kalau ganti iPhone.")
                .font(.app(15)).foregroundStyle(Color.appTextSecondary).lineSpacing(2)
                .padding(.top, 6).padding(.trailing, 24)
            GuestUpgradeButtons().padding(.top, 16)
        }
        .padding(.leading, 20).padding(.vertical, 20).padding(.trailing, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(light: 0xF7F7F8, dark: 0x1C1C1E), in: RoundedRectangle(cornerRadius: 20))
        .overlay(alignment: .topTrailing) {
            Button {
                dismissCount += 1
                hiddenUntil = Date().addingTimeInterval(Double(GuestCardPolicy.pauseDays) * 86_400).timeIntervalSince1970
                justClosed = true
            } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.appTextTertiary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(L("Tutup"))
            .padding(4)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .rise(shown, y: 14, delay: 0.3, fade: 0.5, move: 0.6)
        .onAppear { shown = true }
    }
}

// MARK: - The sheet

/// One sheet for the whole question (design "Tautkan akun" 2a-2d): the account already exists, a second warning,
/// the wait, and a failure that leaves the guest account as it was.
struct GuestLinkSheet: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch authViewModel.guestLinkStep {
            case .askSwitch: ask
            case .confirmSwitch: confirm
            case .working(let text): working(text)
            case .failed(let message): failed(message)
            case .none: Color.clear.frame(height: 1)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.settle(0.35), value: authViewModel.guestLinkStep)
    }

    private func badge(_ symbol: String, tint: Color, fill: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 22, weight: .semibold)).foregroundStyle(tint)
            .frame(width: 48, height: 48).background(fill, in: Circle())
    }

    private func primary(_ title: String, color: Color = .appPrimary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.app(17, weight: .semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 52).background(color, in: Capsule())
        }
        .buttonStyle(PressScaleStyle())
    }

    private func plain(_ title: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.app(17, weight: .semibold))
                .foregroundStyle(enabled ? Color.appPrimary : Color.appTextTertiary)
                .frame(maxWidth: .infinity).frame(height: 52)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var ask: some View {
        VStack(alignment: .leading, spacing: 0) {
            badge("arrow.left.arrow.right", tint: .appPrimary, fill: Color.appPrimary.opacity(0.12))
            Text("Akun Google ini sudah terdaftar. Mau beralih ke akun itu?")
                .font(.app(22, weight: .semibold)).lineSpacing(2).padding(.top, 16)
                .fixedSize(horizontal: false, vertical: true)
            if let email = authViewModel.switchTargetEmail {
                HStack(spacing: 12) {
                    Image("GoogleLogo").resizable().scaledToFit().frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Akun tujuan").font(.app(13)).foregroundStyle(Color.appTextSecondary)
                        Text(email).font(.app(16, weight: .semibold))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16))
                .padding(.top, 18)
            }
            primary(L("Beralih ke akun itu")) { authViewModel.askSwitchConfirmation() }.padding(.top, 24)
            plain(L("Batal")) { authViewModel.cancelSwitch() }.padding(.top, 6)
        }
    }

    private var confirm: some View {
        VStack(alignment: .leading, spacing: 0) {
            badge("exclamationmark.triangle", tint: .appError, fill: Color(light: 0xFDECEC, dark: 0x3A1D1F))
            Text("Sebelum beralih").font(.app(22, weight: .semibold)).padding(.top, 16)
            Text(L("Data tamu di iPhone ini tidak akan ikut dan tidak bisa dipulihkan.")
                 + (authViewModel.switchTargetEmail.map { " " + L("Kamu akan masuk ke %@ dengan datanya sendiri.", $0) } ?? ""))
                .font(.app(16)).foregroundStyle(Color.appBody).lineSpacing(3).padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)
            primary(L("Beralih"), color: .appError) { authViewModel.switchToExistingAccount() }.padding(.top, 28)
            plain(L("Batal")) { authViewModel.cancelSwitch() }.padding(.top, 6)
        }
    }

    private func working(_ text: String) -> some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large).tint(Color.appPrimary).padding(.top, 20)
            Text(text).font(.app(20, weight: .semibold))
            Text("Sebentar ya, jangan tutup Saku.").font(.app(15)).foregroundStyle(Color.appTextSecondary)
            plain(L("Batal"), enabled: false) {}.padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private func failed(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            badge("wifi.slash", tint: .appTextSecondary, fill: Color.appFill)
            Text("Belum berhasil menautkan").font(.app(22, weight: .semibold)).padding(.top, 16)
            Text(message).font(.app(16)).foregroundStyle(Color.appTextSecondary).lineSpacing(3).padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)
            primary(L("Coba lagi")) { authViewModel.retryLink() }.padding(.top, 28)
            plain(L("Tutup")) { authViewModel.cancelSwitch() }.padding(.top, 6)
        }
    }
}

/// Shows the sheet while there is something to ask or tell, and the toast once a guest has saved their account.
struct GuestLinkPresentation: ViewModifier {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var sheetHeight: CGFloat = 380

    private var isWorking: Bool {
        if case .working = authViewModel.guestLinkStep { return true }
        return false
    }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(
                get: { authViewModel.guestLinkStep != .none },
                set: { if !$0 { authViewModel.cancelSwitch() } }
            )) {
                GuestLinkSheet()
                    .environmentObject(authViewModel)
                    .background(GeometryReader { geo in
                        Color.clear.onAppear { sheetHeight = geo.size.height }
                            .onChange(of: geo.size.height) { _, height in sheetHeight = height }
                    })
                    .presentationDetents([.height(sheetHeight + 16)])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
                    // solid white as in the design, not the system's translucent sheet
                    .presentationBackground(Color.appBackground)
                    .interactiveDismissDisabled(isWorking)
            }
            .toast(L("Akun tertaut"), isShown: Binding(
                get: { authViewModel.linkSucceeded },
                set: { authViewModel.linkSucceeded = $0 }
            ))
    }
}

extension View {
    func guestLinkDialogs() -> some View { modifier(GuestLinkPresentation()) }
}
