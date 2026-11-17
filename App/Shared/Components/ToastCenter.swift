import SwiftUI

/// The one toast of the app. Any screen calls `ToastCenter.shared.show(...)`; `.toastHost()` on the root view draws it,
/// always at the top under the status bar, so it never meets the tab bar, the floating buttons or a Simpan button.
/// A new toast replaces the one on screen.
@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()

    enum Icon {
        case success, error, trash

        var symbol: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .error: "exclamationmark.circle.fill"
            case .trash: "trash.fill"
            }
        }

        var tint: Color {
            switch self {
            case .success: Color(hex: "3DDC97")
            case .error: Color(hex: "FF8A80")
            case .trash: Color(hex: "3DDC97")
            }
        }
    }

    /// "Urungkan" and what it does. The toast closes when it is tapped.
    struct Undo {
        var title = L("Urungkan")
        let run: () -> Void
    }

    struct Item: Identifiable {
        let id = UUID()
        let text: String
        let icon: Icon
        let undo: Undo?
    }

    @Published private(set) var item: Item?
    private var hideTask: Task<Void, Never>?

    /// `duration` defaults to 1.9 s, or 3.8 s when there is an Urungkan to reach.
    func show(_ text: String, icon: Icon = .success, undo: Undo? = nil, duration: Double? = nil) {
        hideTask?.cancel()
        let new = Item(text: text, icon: icon, undo: undo)
        withAnimation(.spring(duration: 0.48, bounce: 0.35)) { item = new }
        let seconds = duration ?? (undo == nil ? 1.9 : 3.8)
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.dismiss(new.id)
        }
    }

    func dismiss(_ id: UUID? = nil) {
        guard id == nil || item?.id == id else { return }
        hideTask?.cancel()
        withAnimation(.easeOut(duration: 0.26)) { item = nil }
    }
}

/// Black pill, icon, text and an optional Urungkan. The only toast design in the app.
struct ToastView: View {
    let item: ToastCenter.Item
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: item.undo == nil ? 8 : 14) {
            // with Urungkan the words stand alone: a check mark would read as "done" for a delete or an ignore
            if item.undo == nil {
                Image(systemName: item.icon.symbol)
                    .font(.system(size: 17))
                    .foregroundStyle(item.icon.tint)
            }
            Text(item.text).font(.app(15, weight: .medium)).lineLimit(1)
            if let undo = item.undo {
                Button(action: onUndo) {
                    Text(undo.title).font(.app(15, weight: .semibold)).foregroundStyle(Color(hex: "3DDC97"))
                        .padding(.horizontal, 14).frame(height: 36)
                        .background(Color.white.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(.white)
        .padding(.leading, item.undo == nil ? 12 : 20)
        .padding(.trailing, item.undo == nil ? 16 : 6)
        .frame(height: item.undo == nil ? 40 : 48)
        .background(Color(hex: "111111"), in: Capsule())
        // dark mode: the pill would melt into a black screen without an edge
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 8)
        .padding(.horizontal, 24)
        .accessibilityElement(children: item.undo == nil ? .ignore : .contain)
        .accessibilityLabel(item.text)
    }
}

private struct ToastHost: ViewModifier {
    @ObservedObject private var center = ToastCenter.shared

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let item = center.item {
                ToastView(item: item) {
                    item.undo?.run()
                    center.dismiss(item.id)
                }
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(item.id)
                .allowsHitTesting(item.undo != nil)
                .zIndex(100)
            }
        }
    }
}

extension View {
    /// Draws the app's toast. Put it once on the root view.
    func toastHost() -> some View { modifier(ToastHost()) }
}
