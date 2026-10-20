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
    /// A page pushed over the tabs: the tab bar slides away and the Smart Tracker button hides
    /// with it. With `onAdd`, a lone glass + takes its place at the bottom right.
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
            .hidesTabBarWhilePushed()
            // A pushed page is not a tab root: the Smart Tracker button belongs to the tab pages only.
            .hidesSmartButton()
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

// MARK: - Tab bar and sparkle button move with the push and the pop

extension View {
    /// Hides the tab bar while the page is pushed, and brings it back the moment the pop begins. Hiding it only
    /// through `.toolbar(.hidden, for: .tabBar)` let the bar return after the pop had finished, about half a second
    /// late, because SwiftUI drops that setting when the page is removed.
    func hidesTabBarWhilePushed() -> some View { modifier(HidesTabBarWhilePushed()) }
}

private struct HidesTabBarWhilePushed: ViewModifier {
    @State private var isPopping = false

    func body(content: Content) -> some View {
        content
            .toolbar(isPopping ? .visible : .hidden, for: .tabBar)
            .background(PopWatcher(onPopBegins: { isPopping = true }, onPopCancelled: { isPopping = false }))
    }
}

extension Notification.Name {
    /// A page in a navigation stack starts to be popped (object: its view controller).
    static let pagePopBegins = Notification.Name("sakuPagePopBegins")
    /// A swipe back was let go halfway and the page stays.
    static let pagePopCancelled = Notification.Name("sakuPagePopCancelled")
}

extension UIViewController {
    /// Installed once at launch. UIKit calls `viewWillDisappear` on a page the moment its pop begins; SwiftUI's own
    /// `onDisappear` (and the SwiftUI side of the page) only hears about it when the pop is over.
    static let sakuWatchesPops: Void = {
        guard let original = class_getInstanceMethod(UIViewController.self, #selector(UIViewController.viewWillDisappear(_:))),
              let replacement = class_getInstanceMethod(UIViewController.self, #selector(UIViewController.saku_viewWillDisappear(_:))) else { return }
        method_exchangeImplementations(original, replacement)
    }()

    // After the exchange this name runs UIKit's own implementation.
    @objc fileprivate func saku_viewWillDisappear(_ animated: Bool) {
        saku_viewWillDisappear(animated)
        guard animated, isMovingFromParent, parent is UINavigationController else { return }
        NotificationCenter.default.post(name: .pagePopBegins, object: self)
        transitionCoordinator?.notifyWhenInteractionChanges { [weak self] context in
            if context.isCancelled { NotificationCenter.default.post(name: .pagePopCancelled, object: self) }
        }
    }
}

/// Tells when the page it sits in starts to be popped, which is when UIKit starts to bring the tab bar back.
struct PopWatcher: UIViewControllerRepresentable {
    let onPopBegins: () -> Void
    let onPopCancelled: () -> Void

    func makeUIViewController(context: Context) -> PopWatcherController {
        let controller = PopWatcherController()
        controller.onPopBegins = onPopBegins
        controller.onPopCancelled = onPopCancelled
        return controller
    }

    func updateUIViewController(_ controller: PopWatcherController, context: Context) {
        controller.onPopBegins = onPopBegins
        controller.onPopCancelled = onPopCancelled
    }
}

final class PopWatcherController: UIViewController {
    var onPopBegins: (() -> Void)?
    var onPopCancelled: (() -> Void)?
    private var tokens: [NSObjectProtocol] = []

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // the page's own controller is the one sitting directly in the navigation stack
        var page: UIViewController = self
        while let parent = page.parent, !(parent is UINavigationController) { page = parent }
        guard page.parent is UINavigationController else { return }
        tokens.forEach(NotificationCenter.default.removeObserver)
        tokens = [
            NotificationCenter.default.addObserver(forName: .pagePopBegins, object: page, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onPopBegins?() }
            },
            NotificationCenter.default.addObserver(forName: .pagePopCancelled, object: page, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onPopCancelled?() }
            },
        ]
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        tokens.forEach(NotificationCenter.default.removeObserver)
        tokens = []
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
        // Never start a swipe-back while this stack is still pushing or popping: a second pop on top of a running
        // transition leaves the stack half-popped (tab bar gone, navigation stuck).
        viewControllers.count > 1 && transitionCoordinator == nil
    }
}
