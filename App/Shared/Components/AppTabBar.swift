import SwiftUI

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

// MARK: - Detail pages

/// Lets a detail page hide the floating + while something covers the bottom of the screen.
struct HidesDetailAddButton: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

extension View {
    /// A page pushed over the tabs: the tab bar slides away. With `onAdd`, a lone glass +
    /// takes its place at the bottom right.
    func detailPage(addLabel: String = "Tambah", onAdd: (() -> Void)? = nil) -> some View {
        modifier(DetailPageChrome(addLabel: addLabel, onAdd: onAdd))
    }

    /// Hides the detail page's + while `hidden` is true.
    func hidesDetailAddButton(_ hidden: Bool) -> some View {
        preference(key: HidesDetailAddButton.self, value: hidden)
    }
}

private struct DetailPageChrome: ViewModifier {
    let addLabel: String
    let onAdd: (() -> Void)?
    @State private var isShown = false
    @State private var isHiddenByPage = false

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .tabBar)
            .onPreferenceChange(HidesDetailAddButton.self) { hidden in
                withAnimation(.spring(duration: 0.3)) { isHiddenByPage = hidden }
            }
            .overlay(alignment: .bottomTrailing) {
                if let onAdd, isShown && !isHiddenByPage {
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.appText)
                            .frame(width: 56, height: 56)
                            .contentShape(Circle())
                            .glassCircle()
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 20)
                    .padding(.bottom, 8)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                    .accessibilityLabel(Text(LocalizedStringKey(addLabel)))
                }
            }
            // Appears as the tab bar slides away, so the + reads as what's left of it.
            .onAppear { withAnimation(.spring(duration: 0.4, bounce: 0.25).delay(0.12)) { isShown = true } }
            .onDisappear { isShown = false }
    }
}

extension View {
    /// Liquid Glass circle on iOS 26, material before.
    @ViewBuilder
    fileprivate func glassCircle() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.interactive(), in: Circle())
        } else {
            background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
        }
    }
}

// Keeps the edge swipe-back working on pages that hide the system back button
// (e.g. Ubah dompet, which puts "Batal" there instead).
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
