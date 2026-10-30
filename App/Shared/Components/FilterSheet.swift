import SwiftUI

/// Every sheet behaves like the transaction filter: half height, drag up to full, system corners and grabber.
/// The content scrolls when the half height is too short for it.
/// The action buttons go in `footer`: they stay at the bottom of the sheet and never scroll away with the content.
extension View {
    /// The gap from the buttons to the bottom edge of the screen is the same 24 pt as on their sides. The home
    /// indicator's safe area is already part of that gap, so the difference is taken off (the buttons reach into it).
    private static var footerBottomPadding: CGFloat {
        let safe = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first?.keyWindow?.safeAreaInsets.bottom ?? 0
        return 24 - safe
    }

    func filterSheet() -> some View {
        ScrollView { self }
            .background(Color.appBackground)
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .presentationDetents([.medium, .large])
    }

    func filterSheet<Footer: View>(@ViewBuilder footer: () -> Footer) -> some View {
        let bar = footer()
        return ScrollView { self }
            .background(Color.appBackground)
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bar
                    .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, Self.footerBottomPadding)
                    .frame(maxWidth: .infinity)
                    .background(Color.appBackground)
            }
            .presentationDetents([.medium, .large])
    }
}
