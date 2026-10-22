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
    @State private var shown = false

    var body: some View {
        Group {
            if !consented, !dismissed, authViewModel.currentUser != nil {
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.appPrimary)
                    .frame(width: 32, height: 32)
                    .background(Color.appPrimary.opacity(0.12), in: Circle())
                Text("Coba Smart Tracker").font(.app(17, weight: .semibold))
                Spacer(minLength: 0)
            }
            .padding(.trailing, 40)
            Text("Catat transaksi otomatis dari notifikasi bank dan e-wallet.")
                .font(.app(15)).foregroundStyle(Color.appTextSecondary).lineSpacing(2)
                .padding(.top, 8).padding(.trailing, 24)
            Button { showsConsent = true } label: {
                Text("Aktifkan").font(.app(15, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 22).frame(height: 44)
                    .background(Color.appPrimary, in: Capsule())
            }
            .buttonStyle(PressScaleStyle())
            .padding(.top, 14)
        }
        .padding(.leading, 20).padding(.vertical, 18).padding(.trailing, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 20))
        .overlay(alignment: .topTrailing) {
            Button { dismissed = true } label: {
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
