import SwiftUI

/// The Saku Plus banner on Beranda: one at a time, closable (design 5a).
struct PlusBannerView: View {
    @ObservedObject private var plus = PlusStore.shared
    @Environment(\.openURL) private var openURL
    @AppStorage("plusBannersClosed") private var closed = ""
    @State private var showsStatus = false
    /// Test builds show a made-up banner here (HomePreview).
    var preview: PlusBanner?

    private var dismissed: Set<String> { Set(closed.split(separator: "|").map(String.init)) }

    var body: some View {
        if let banner = preview ?? PlusBanner.pick(for: plus.entitlement, dismissed: dismissed) {
            NoticeCard(icon: banner.kind == .grace ? "creditcard.fill" : "clock.fill", tone: .warning, title: banner.title,
                       message: banner.body, onClose: { closed = (dismissed.union([banner.key])).sorted().joined(separator: "|") }) {
                NoticeButton(title: banner.action) { act(banner) }
            }
            .transition(.opacity.combined(with: .offset(y: -12)))
            .sheet(isPresented: $showsStatus) { NavigationStack { PlusStatusView() } }
        }
    }

    private func act(_ banner: PlusBanner) {
        if banner.kind == .trialEnding(days: 2) { showsStatus = true }
        else if let url = URL(string: "https://apps.apple.com/account/subscriptions") { openURL(url) }
    }
}
