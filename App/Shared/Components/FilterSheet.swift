import SwiftUI

/// Every sheet behaves like the transaction filter: half height, drag up to full, system corners and grabber.
/// The content scrolls when the half height is too short for it.
/// The action buttons go in `footer`: they stay at the bottom of the sheet and never scroll away with the content.
extension View {
    /// The gap from the buttons to the bottom edge of the screen is the same 24 pt as on their sides. The home
    /// indicator's safe area is already part of that gap, so the difference is taken off (the buttons reach into it).
    static var footerBottomPadding: CGFloat {
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

    /// `showsMoreCue` adds a fade and a down arrow above the footer while there is more content below.
    func filterSheet<Footer: View>(showsMoreCue: Bool = false, @ViewBuilder footer: () -> Footer) -> some View {
        let bar = footer()
        return ScrollView { self }
            .background(Color.appBackground)
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .modifier(MoreCue(enabled: showsMoreCue))
            .pinnedFooter { bar }
            .presentationDetents([.medium, .large])
    }

    /// The footer pinned at the bottom of a sheet, 24 pt from the screen edge and from the sides.
    func pinnedFooter<Footer: View>(separator: Bool = false, @ViewBuilder _ footer: () -> Footer) -> some View {
        modifier(PinnedFooter(bar: footer(), separator: separator, initial: Self.footerBottomPadding))
    }
}

/// The home indicator's safe area counts toward the 24 pt gap, so it is read from the sheet's own geometry: reading
/// the window instead left the buttons off the screen whenever the sheet's inset differed from the window's.
private struct PinnedFooter<Bar: View>: ViewModifier {
    let bar: Bar
    let separator: Bool
    @State private var padding: CGFloat

    init(bar: Bar, separator: Bool, initial: CGFloat) {
        self.bar = bar
        self.separator = separator
        _padding = State(initialValue: initial)
    }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bar
                    .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, padding)
                    .frame(maxWidth: .infinity)
                    .background(Color.appBackground)
                    .overlay(alignment: .top) { if separator { Rectangle().fill(Color.appSeparator).frame(height: 1) } }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { padding = 24 - proxy.safeAreaInsets.bottom }
                        .onChange(of: proxy.safeAreaInsets.bottom) { _, bottom in padding = 24 - bottom }
                }
            }
    }
}

private struct MoreCue: ViewModifier {
    let enabled: Bool
    @State private var hasMore = false

    func body(content: Content) -> some View {
        if enabled {
            content
                .onScrollGeometryChange(for: Bool.self) { g in
                    g.contentOffset.y + g.containerSize.height < g.contentSize.height - 1
                } action: { _, more in hasMore = more }
                .overlay(alignment: .bottom) {
                    if hasMore {
                        LinearGradient(colors: [Color.appBackground.opacity(0), Color.appBackground], startPoint: .top, endPoint: .center)
                            .frame(height: 56).allowsHitTesting(false)
                            .overlay(alignment: .bottom) {
                                Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color.appTextSecondary)
                                    .frame(width: 28, height: 28).background(Color.appFill, in: Circle()).padding(.bottom, 4)
                            }
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: hasMore)
        } else {
            content
        }
    }
}
