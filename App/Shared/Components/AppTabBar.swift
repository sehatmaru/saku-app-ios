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

/// Icon-only Liquid Glass tab bar with + in the middle. When `isHidden`, the bar
/// morphs down into just the + so adding a transaction is always one tap away.
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
    @Namespace private var glass

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

    @ViewBuilder
    private var bar: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer {
                if isHidden {
                    addButton
                        .frame(width: 64, height: 64)
                        .glassEffect(.regular.interactive(), in: Circle())
                        .glassEffectID("bar", in: glass)
                } else {
                    items
                        .padding(.horizontal, 6)
                        .frame(height: 64)
                        .glassEffect(.regular.interactive(), in: Capsule())
                        .glassEffectID("bar", in: glass)
                }
            }
            .animation(.settle(0.42), value: isHidden)
        } else {
            Group {
                if isHidden {
                    addButton
                        .frame(width: 64, height: 64)
                        .background(.regularMaterial, in: Circle())
                } else {
                    items
                        .padding(.horizontal, 6)
                        .frame(height: 64)
                        .background(.regularMaterial, in: Capsule())
                }
            }
            .shadow(color: .black.opacity(0.14), radius: 18, y: 12)
            .animation(.settle(0.42), value: isHidden)
        }
    }

    private var items: some View {
        HStack(spacing: 0) {
            ForEach(leading, id: \.tab) { tabButton($0) }
            addButton.frame(maxWidth: .infinity)
            ForEach(trailing, id: \.tab) { tabButton($0) }
        }
    }

    private var addButton: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.appText)
                .frame(width: 58, height: 52)
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
                    InitialsAvatar(initials: initials, size: 30, fontSize: 11)
                        .padding(2)
                        .overlay(Circle().strokeBorder(isOn ? Color.appPrimary : Color.appText.opacity(0.12), lineWidth: isOn ? 2 : 0.5))
                } else {
                    Image(systemName: item.icon)
                        .font(.system(size: 22))
                        .foregroundStyle(isOn ? Color.appPrimary : Color.appText)
                }
            }
            .frame(width: 58, height: 52)
            .background(highlight, in: Capsule())
            .contentShape(Capsule())
            .animation(.easeInOut(duration: 0.22), value: isOn)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
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
