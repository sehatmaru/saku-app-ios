import SwiftUI

/// Which tab bar to show; chosen in Profil while both versions are being compared.
enum TabBarStyle: String, CaseIterable {
    /// iOS's own Liquid Glass tab bar, which shrinks on scroll.
    case native = "Native"
    /// The revamp's icon-only bar that slides away on scroll, with a separate green +.
    case custom = "Custom"
}

/// Hides the custom tab bar while scrolling down and brings it back on scroll up.
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
    /// With the custom bar on, hides the system tab bar and leaves room for ours.
    func customTabBarSpace(_ isOn: Bool) -> some View {
        toolbar(isOn ? .hidden : .automatic, for: .tabBar)
            .safeAreaPadding(.bottom, isOn ? 64 : 0)
    }

    /// Reports this scroll view's offset to the custom tab bar; no effect without it.
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

/// Icon-only glass tab bar with a solid green + beside it. The bar slides away when
/// `isHidden`; the + always stays.
struct CustomTabBar<Tab: Hashable>: View {
    struct Item {
        let tab: Tab
        let label: String
        let icon: String
    }

    let items: [Item]
    @Binding var selection: Tab
    let isHidden: Bool
    let onAdd: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            // Fades content out under the bar so icons stay readable.
            LinearGradient(stops: [.init(color: Color.appBackground.opacity(0), location: 0),
                                   .init(color: Color.appBackground, location: 0.6)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 120)
                .opacity(isHidden ? 0.6 : 1)
                .animation(.easeInOut(duration: 0.3), value: isHidden)
                .allowsHitTesting(false)

            HStack(spacing: 8) {
                bar
                addButton
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
    }

    private var bar: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.tab) { tabButton($0) }
        }
        .padding(.horizontal, 4)
        .frame(height: 56)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.5), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 15, y: 10)
        .offset(y: isHidden ? 110 : 0)
        .opacity(isHidden ? 0 : 1)
        .animation(.settle(0.38), value: isHidden)
        .allowsHitTesting(!isHidden)
    }

    private func tabButton(_ item: Item) -> some View {
        let isOn = item.tab == selection
        let highlight: Color = isOn ? Color.appText.opacity(0.06) : .clear
        return Button { selection = item.tab } label: {
            Image(systemName: item.icon)
                .font(.system(size: 21))
                .foregroundStyle(isOn ? Color.appPrimary : Color.appText)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(highlight, in: Capsule())
                .contentShape(Capsule())
                .animation(.easeInOut(duration: 0.22), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    private var addButton: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.appBrand, in: Circle())
                .shadow(color: Color.appBrand.opacity(0.28), radius: 11, y: 8)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("Tambah transaksi")
    }
}
