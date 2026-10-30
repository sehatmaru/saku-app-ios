import SwiftUI

extension Notification.Name {
    /// "Catat pengeluaran pertamamu" on the welcome screen: Beranda opens where the first entry is made.
    static let openFirstEntry = Notification.Name("openFirstEntry")
}

/// A card on Beranda for accounts that have not turned Smart Tracker on (Enhancement 2, US7). It asks for the usual
/// agreement and can be closed for good; once Smart Tracker is on it never shows again.
struct TrySmartTrackerCard: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @AppStorage(SmartTrackerConsent.key) private var consented = false
    @AppStorage("smartTrackerCardDismissed") private var dismissed = false
    @State private var showsConsent = false
    /// Test builds show the card whatever the account has done (HomePreview).
    var isForced = false

    var body: some View {
        Group {
            if isForced || (!consented && !dismissed && authViewModel.currentUser != nil) {
                card
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .animation(.settle(0.4), value: dismissed)
        .animation(.settle(0.4), value: consented)
        .sheet(isPresented: $showsConsent) {
            SmartTrackerConsentSheet(profileId: authViewModel.currentUser.flatMap { UUID(uuidString: $0.id) }) {
                showsConsent = false
            }
        }
    }

    private var card: some View {
        NoticeCard(icon: "sparkle", title: L("Coba Smart Tracker"),
                   message: L("Catat transaksi otomatis dari notifikasi bank dan e-wallet."),
                   onClose: { dismissed = true }) {
            NoticeButton(title: L("Aktifkan")) { showsConsent = true }
        }
    }
}
