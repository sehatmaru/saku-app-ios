import SwiftUI

/// Hides the tab bar while scrolling down and brings it back on scroll up.
@MainActor @Observable
final class TabBarScroll {
    var isHidden = false
    private var lastY: CGFloat = 0

    func track(_ y: CGFloat) {
        if y > lastY + 6, y > 40 {
            isHidden = true
        } else if y < lastY - 6 || y <= 40 {
            isHidden = false
        }
        if abs(y - lastY) > 6 || y <= 40 { lastY = y }
    }

    func reset() {
        isHidden = false
        lastY = 0
    }
}

extension View {
    /// Hides the system tab bar and leaves room at the bottom for the glass bar.
    func glassTabBarSpace() -> some View {
        toolbar(.hidden, for: .tabBar)
            .safeAreaPadding(.bottom, 64)
    }

    /// Reports this scroll view's offset to the tab bar; no effect outside it.
    func tracksTabBarScroll() -> some View {
        modifier(TabBarScrollReporter())
    }
}

private struct TabBarScrollReporter: ViewModifier {
    @Environment(TabBarScroll.self) private var scroll: TabBarScroll?

    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: CGFloat.self) { geo in
            // Clamped so the bounce at either end doesn't read as a direction change.
            let y = geo.contentOffset.y + geo.contentInsets.top
            let maxY = geo.contentSize.height + geo.contentInsets.top + geo.contentInsets.bottom - geo.containerSize.height
            return min(max(y, 0), max(maxY, 0))
        } action: { _, y in
            scroll?.track(y)
        }
    }
}

/// Compact icon-only Liquid Glass tab bar with + in the middle. When `isHidden` the
/// icons fade, the glass shrinks to a circle and the + slides to the right edge, so
/// adding a transaction stays one tap away.
struct GlassTabBar<Tab: Hashable>: View {
    struct Item {
        let tab: Tab
        let label: String
        let icon: String
        /// Shows these initials in a round avatar instead of the icon.
        var avatar: String?
    }

    /// Tabs left and right of the +.
    let leading: [Item]
    let trailing: [Item]
    @Binding var selection: Tab
    let isHidden: Bool
    let onAdd: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private static var barHeight: CGFloat { 60 }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Fades content out under the bar so icons stay readable.
            LinearGradient(stops: [.init(color: Color.appBackground.opacity(0), location: 0),
                                   .init(color: Color.appBackground.opacity(0.8), location: 0.7)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 130)
                .opacity(isHidden ? 0.5 : 1)
                .animation(.easeInOut(duration: 0.3), value: isHidden)
                .allowsHitTesting(false)

            bar
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
        }
    }

    /// One glass capsule: hiding collapses every tab to zero width, so the capsule
    /// shrinks around the + and glides to the right edge in a single motion.
    private var bar: some View {
        HStack(spacing: 0) {
            ForEach(leading, id: \.tab) { tabButton($0) }
            addButton
            ForEach(trailing, id: \.tab) { tabButton($0) }
        }
        .padding(.horizontal, isHidden ? 0 : 4)
        .frame(height: Self.barHeight)
        .glassSurface(Capsule())
        .frame(maxWidth: .infinity, alignment: isHidden ? .trailing : .center)
        .animation(.settle(0.5), value: isHidden)
    }

    private var addButton: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.appText)
                .frame(width: isHidden ? Self.barHeight : 56, height: 50)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("Tambah transaksi")
    }

    private func tabButton(_ item: Item) -> some View {
        let isOn = item.tab == selection
        let highlight: Color = isOn ? Color.white.opacity(colorScheme == .dark ? 0.14 : 0.6) : .clear
        return Button { selection = item.tab } label: {
            Group {
                if let initials = item.avatar {
                    InitialsAvatar(initials: initials, size: 28, fontSize: 11)
                        .padding(2)
                        .overlay(Circle().strokeBorder(isOn ? Color.appPrimary : Color.appText.opacity(0.12), lineWidth: isOn ? 2 : 0.5))
                } else {
                    Image(systemName: item.icon)
                        .font(.system(size: 21))
                        .foregroundStyle(isOn ? Color.appPrimary : Color.appText)
                }
            }
            .frame(width: 60, height: 50)
            .background(highlight, in: Capsule())
            .contentShape(Capsule())
            .animation(.easeInOut(duration: 0.22), value: isOn)
        }
        .buttonStyle(.plain)
        // Hidden tabs fade and fold to zero width so the bar closes around the +.
        .opacity(isHidden ? 0 : 1)
        .animation(.easeOut(duration: isHidden ? 0.18 : 0.3).delay(isHidden ? 0 : 0.15), value: isHidden)
        .frame(width: isHidden ? 0 : 60)
        .clipped()
        .allowsHitTesting(!isHidden)
        .accessibilityHidden(isHidden)
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

extension View {
    /// Liquid Glass on iOS 26, material before.
    @ViewBuilder
    fileprivate func glassSurface(_ shape: some Shape) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.interactive(), in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .shadow(color: .black.opacity(0.14), radius: 14, y: 8)
        }
    }
}

/// Short taps of feedback for the moments that matter.
@MainActor
enum Haptics {
    /// Opening the add-transaction form.
    static func add() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    /// Landing on Beranda after the app opens.
    static func welcome() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    /// Signing out.
    static func logout() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
