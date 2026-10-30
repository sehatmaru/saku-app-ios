import SwiftUI

/// Every sheet behaves like the transaction filter: half height, drag up to full, system corners and grabber.
/// The content scrolls when the half height is too short for it.
/// The action buttons go in `footer`: they stay at the bottom of the sheet and never scroll away with the content.
extension View {
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
                    .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 12)
                    .frame(maxWidth: .infinity)
                    .background(Color.appBackground)
            }
            .presentationDetents([.medium, .large])
    }
}
