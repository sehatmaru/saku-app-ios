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

/// Opens the add-transaction form; set once by the tab host so any page can reach it.
struct AddTransactionAction {
    var run: () -> Void = {}
    func callAsFunction() { run() }
}

extension EnvironmentValues {
    @Entry var addTransaction = AddTransactionAction()
}

/// Lets a detail page hide the floating + while something covers the bottom of the screen.
struct HidesDetailAddButton: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

extension View {
    /// A page pushed over the tabs: the tab bar slides away and a lone glass + takes its
    /// place at the bottom right.
    func detailPage() -> some View {
        modifier(DetailPageChrome())
    }

    /// Hides the detail page's + while `hidden` is true.
    func hidesDetailAddButton(_ hidden: Bool) -> some View {
        preference(key: HidesDetailAddButton.self, value: hidden)
    }
}

private struct DetailPageChrome: ViewModifier {
    @Environment(\.addTransaction) private var addTransaction
    @State private var isShown = false
    @State private var isHiddenByPage = false

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .tabBar)
            .onPreferenceChange(HidesDetailAddButton.self) { hidden in
                withAnimation(.spring(duration: 0.3)) { isHiddenByPage = hidden }
            }
            .overlay(alignment: .bottomTrailing) {
                if isShown && !isHiddenByPage {
                    Button { addTransaction() } label: {
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
                    .accessibilityLabel("Tambah transaksi")
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
