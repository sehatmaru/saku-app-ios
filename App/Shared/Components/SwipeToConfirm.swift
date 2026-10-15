import SwiftUI

/// Slide-the-knob confirm control (design "Geser untuk …"): a 60pt track with a 52pt knob.
/// Released past 80% it snaps to the end, shows a check and calls `onConfirm` ~0.28s later; it then
/// stays in that done state until `resetToken` changes. Disabled, any touch calls `onBlocked`.
struct SwipeToConfirm: View {
    let label: String
    var color: Color
    var isEnabled = true
    /// Change it to send the knob back to the start (e.g. after a failed save).
    var resetToken = 0
    var onBlocked: () -> Void = {}
    let onConfirm: () -> Void

    @State private var dx: CGFloat = 0
    @State private var isDragging = false
    @State private var isDone = false
    @State private var didBlock = false

    private static let height: CGFloat = 60
    private static let knob: CGFloat = 52
    private static let inset: CGFloat = 4
    private static let greyKnob = Color(light: 0xC7C7CC, dark: 0x48484A)
    private static let greyLabel = Color(light: 0xA1A1A6, dark: 0x8E8E93)

    private var knobColor: Color { isEnabled || isDone ? color : Self.greyKnob }
    private var release: Animation { .spring(duration: 0.46, bounce: 0.35) }

    var body: some View {
        GeometryReader { geo in
            let maxX = max(geo.size.width - Self.knob - Self.inset * 2, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.appFill)

                Capsule()
                    .fill(knobColor.opacity(0.16))
                    .frame(width: min(dx + Self.height, geo.size.width))

                HStack(spacing: 8) {
                    Text(label)
                        .font(.app(16, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                    Image(systemName: "chevron.right.2")
                        .font(.system(size: 14, weight: .bold))
                        .opacity(isEnabled ? 0.45 : 0)
                }
                .foregroundStyle(isEnabled ? Color.appText : Self.greyLabel)
                .frame(maxWidth: .infinity)
                .padding(.leading, 56)
                .padding(.trailing, 12)
                .opacity(isDone ? 0 : max(0, 1 - dx / (maxX * 0.55)))
                .animation(.easeInOut(duration: 0.2), value: isEnabled)

                Circle()
                    .fill(knobColor)
                    .frame(width: Self.knob, height: Self.knob)
                    .overlay {
                        ZStack {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 20, weight: .bold))
                                .opacity(isDone ? 0 : 1)
                            Image(systemName: "checkmark")
                                .font(.system(size: 22, weight: .bold))
                                .opacity(isDone ? 1 : 0)
                                .scaleEffect(isDone ? 1 : 0.3)
                                .animation(.spring(duration: 0.42, bounce: 0.55), value: isDone)
                        }
                        .foregroundStyle(.white)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 4)
                    .scaleEffect(isDone ? 1.04 : 1)
                    .offset(x: Self.inset + dx)
                    .animation(.easeInOut(duration: 0.3), value: knobColor)
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
            .gesture(drag(maxX: maxX))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(isEnabled ? L("Ketuk dua kali untuk konfirmasi") : "")
            .accessibilityAction { isEnabled ? finish(maxX: maxX) : onBlocked() }
        }
        .frame(height: Self.height)
        .onChange(of: resetToken) { _, _ in
            withAnimation(release) { dx = 0; isDone = false }
        }
    }

    private func drag(maxX: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isDone else { return }
                guard isEnabled else {
                    if !didBlock { didBlock = true; onBlocked() }
                    return
                }
                isDragging = true
                dx = min(max(value.translation.width, 0), maxX)
            }
            .onEnded { _ in
                didBlock = false
                guard isDragging, !isDone else { return }
                isDragging = false
                if dx >= maxX * 0.8 {
                    finish(maxX: maxX)
                } else {
                    withAnimation(release) { dx = 0 }
                }
            }
    }

    private func finish(maxX: CGFloat) {
        guard !isDone else { return }
        withAnimation(release) { dx = maxX; isDone = true }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task {
            try? await Task.sleep(for: .milliseconds(280))
            onConfirm()
        }
    }
}
