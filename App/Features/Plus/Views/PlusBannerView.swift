import SwiftUI

/// The Saku Plus banner on Beranda: one at a time, closable (design 5a).
struct PlusBannerView: View {
    @ObservedObject private var plus = PlusStore.shared
    @Environment(\.openURL) private var openURL
    @AppStorage("plusBannersClosed") private var closed = ""
    @State private var showsStatus = false

    private var dismissed: Set<String> { Set(closed.split(separator: "|").map(String.init)) }

    var body: some View {
        if let banner = PlusBanner.pick(for: plus.entitlement, dismissed: dismissed) {
            let isGrace = banner.kind == .grace
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isGrace ? "creditcard" : "calendar").font(.system(size: 18))
                    .foregroundStyle(isGrace ? Color.appError : Color.appTextSecondary).padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(banner.title).font(.app(14, weight: .semibold)).foregroundStyle(Color.appText)
                    Text(banner.body).font(.app(13)).foregroundStyle(Color.appTextSecondary).fixedSize(horizontal: false, vertical: true)
                    Button { act(banner) } label: {
                        Text(banner.action).font(.app(14, weight: .semibold)).foregroundStyle(Color.appPrimary)
                    }
                    .buttonStyle(.plain).padding(.top, 5)
                }
                Spacer(minLength: 0)
                Button { closed = (dismissed.union([banner.key])).sorted().joined(separator: "|") } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.appTextTertiary).padding(4)
                }
                .buttonStyle(.plain).accessibilityLabel(L("Tutup"))
            }
            .padding(.vertical, 14).padding(.leading, 16).padding(.trailing, 12)
            .background(isGrace ? Color.appError.opacity(0.1) : Color.stChip, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24).padding(.top, 8)
            .transition(.opacity.combined(with: .offset(y: -12)))
            .sheet(isPresented: $showsStatus) { NavigationStack { PlusStatusView() } }
        }
    }

    private func act(_ banner: PlusBanner) {
        if banner.kind == .trialEnding(days: 2) { showsStatus = true }
        else if let url = URL(string: "https://apps.apple.com/account/subscriptions") { openURL(url) }
    }
}
