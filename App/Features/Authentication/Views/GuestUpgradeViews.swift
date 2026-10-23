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

/// "Masuk dengan Google" and, disabled until the Apple provider is configured (as on the sign-in screen), Apple.
struct GuestUpgradeButtons: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    var body: some View {
        VStack(spacing: 10) {
            Button { authViewModel.linkGoogleToGuest() } label: {
                HStack(spacing: 10) {
                    if authViewModel.isLinking {
                        ProgressView().tint(Color.appText)
                    } else {
                        Image("GoogleLogo").resizable().scaledToFit().frame(width: 19, height: 19)
                    }
                    Text("Masuk dengan Google").font(.app(16, weight: .semibold))
                }
                .foregroundStyle(Color.appText)
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(Color.appBackground, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.appBorder, lineWidth: 1))
            }
            .buttonStyle(PressScaleStyle())
            .disabled(authViewModel.isLinking)

            HStack(spacing: 10) {
                Image(systemName: "apple.logo").font(.system(size: 18))
                Text("Masuk dengan Apple").font(.app(16, weight: .semibold))
            }
            .foregroundStyle(Color.appBackground)
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(Color.appText, in: Capsule())
            .opacity(0.35)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(L("Belum tersedia"))
        }
    }
}

/// The card on Beranda that reminds a guest to keep their data, without chasing them.
struct GuestSaveCard: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @AppStorage(GuestCardPolicy.countKey) private var dismissCount = 0
    @AppStorage(GuestCardPolicy.untilKey) private var hiddenUntil = 0.0
    let transactionCount: Int
    @State private var shown = false

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
            }
        }
        .animation(.settle(0.4), value: isVisible)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Amankan datamu").font(.app(17, weight: .semibold)).padding(.trailing, 40)
            Text("Masuk dengan Google agar datamu tersimpan dan ikut ke perangkat lain.")
                .font(.app(15)).foregroundStyle(Color.appTextSecondary).lineSpacing(2)
                .padding(.top, 6).padding(.trailing, 24)
            GuestUpgradeButtons().padding(.top, 14)
        }
        .padding(.leading, 20).padding(.vertical, 18).padding(.trailing, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 20))
        .overlay(alignment: .topTrailing) {
            Button {
                dismissCount += 1
                hiddenUntil = Date().addingTimeInterval(Double(GuestCardPolicy.pauseDays) * 86_400).timeIntervalSince1970
            } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
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

/// The two questions and the failure message of the guest upgrade, shown wherever the guest happens to be.
struct GuestLinkDialogs: ViewModifier {
    @EnvironmentObject private var authViewModel: AuthViewModel

    func body(content: Content) -> some View {
        content
            .alert(L("Akun Google ini sudah terdaftar"), isPresented: Binding(
                get: { authViewModel.guestLinkStep == .askSwitch },
                set: { if !$0, authViewModel.guestLinkStep == .askSwitch { authViewModel.cancelSwitch() } }
            )) {
                Button(L("Beralih ke akun itu")) { authViewModel.askSwitchConfirmation() }
                Button(L("Batal"), role: .cancel) { authViewModel.cancelSwitch() }
            } message: {
                Text("Akun Google ini sudah terdaftar. Mau beralih ke akun itu?")
            }
            .alert(L("Beralih ke akun itu?"), isPresented: Binding(
                get: { authViewModel.guestLinkStep == .confirmSwitch },
                set: { if !$0, authViewModel.guestLinkStep == .confirmSwitch { authViewModel.cancelSwitch() } }
            )) {
                Button(L("Beralih"), role: .destructive) { authViewModel.switchToExistingAccount() }
                Button(L("Batal"), role: .cancel) { authViewModel.cancelSwitch() }
            } message: {
                Text("Data tamu di iPhone ini tidak akan ikut dan tidak bisa dipulihkan.")
            }
            .alert(L("Belum berhasil"), isPresented: Binding(
                get: { authViewModel.linkErrorMessage != nil },
                set: { if !$0 { authViewModel.linkErrorMessage = nil } }
            )) {
                Button(L("OK"), role: .cancel) {}
            } message: {
                Text(authViewModel.linkErrorMessage ?? "")
            }
    }
}

extension View {
    func guestLinkDialogs() -> some View { modifier(GuestLinkDialogs()) }
}
