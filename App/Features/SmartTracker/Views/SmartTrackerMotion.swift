import SwiftUI

/// Motion of the Smart Tracker design (SakuQ Smart Tracker, "Putar ulang animasi"): everything on a screen
/// rises in one after another, icons of empty states float, and the button pulses until the first use.
extension View {
    /// Fades in and rises 16pt, 45ms after the previous element (design `playIn`: 560ms, capped at 540ms delay).
    func stEnter(_ index: Int = 0) -> some View { modifier(STEnter(index: index)) }

    /// Empty-state icons drift up and down by 6pt (3.4s, forever), each one offset a little from the last.
    func stFloat(_ index: Int = 0) -> some View { modifier(STFloat(index: index)) }
}

private struct STEnter: ViewModifier {
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 16)
            .onAppear {
                withAnimation(.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.56).delay(min(Double(index) * 0.045, 0.54))) { shown = true }
            }
    }
}

private struct STFloat: ViewModifier {
    let index: Int
    @State private var up = false

    func body(content: Content) -> some View {
        content
            .offset(y: up ? -6 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true).delay(Double(index) * 0.4)) { up = true }
            }
    }
}

/// A ring that grows out of a round button and fades (keyframes `stp`: scale 1 → 1.9, opacity .5 → 0).
struct STPulse: View {
    let color: Color
    var duration = 1.8
    @State private var out = false

    var body: some View {
        Circle().fill(color)
            .scaleEffect(out ? 1.9 : 1)
            .opacity(out ? 0 : 0.5)
            .onAppear { withAnimation(.easeOut(duration: duration).repeatForever(autoreverses: false)) { out = true } }
            .allowsHitTesting(false)
    }
}

/// The round icon, title and sentence at the top of an empty state.
struct STEmptyHero: View {
    let icon: String
    var tint: Color = .appTextSecondary
    var fill: Color = .stChip
    let title: String
    let message: String
    var size: CGFloat = 72

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: icon).font(.system(size: size * 0.44)).foregroundStyle(tint)
                .frame(width: size, height: size).background(fill, in: Circle())
                .stFloat()
                .stEnter(0)
            Text(L(title)).font(.app(20, weight: .semibold)).padding(.top, 18).stEnter(1)
            Text(L(message)).font(.app(15)).lineSpacing(3).foregroundStyle(Color.appTextSecondary)
                .multilineTextAlignment(.center).padding(.top, 6).stEnter(2)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity)
    }
}

/// The black pill button of empty states.
struct STInkButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(L(title), systemImage: icon)
                .font(.app(17, weight: .semibold)).foregroundStyle(Color.stInkText)
                .frame(maxWidth: .infinity).frame(height: 52).background(Color.stInk, in: Capsule())
        }
        .buttonStyle(PressScaleStyle())
    }
}
