import SwiftUI

/// The Draf button stacked on Smart Tracker's sparkle button (56pt). It rises out from behind the sparkle button
/// when drafts land, shakes and sends out a ring, and its badge rolls when another draft lands.
struct DraftFab: View {
    let count: Int
    let action: () -> Void

    @State private var landed = 0
    /// True until a second draft lands: the first landing pops the badge in, later ones roll its number.
    @State private var isNew = true
    /// The number the badge shows; it rolls a beat after a draft lands, when the new sheet has dropped.
    @State private var shown = 0
    /// The second grey sheet: with two or more drafts it rests in the tray (filling the notch), as in design 3b.
    @State private var sheetY = 11.0
    @State private var sheetOpacity = 0.0
    @State private var breathe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let bg = Color(light: 0x1C1C1E, dark: 0xE5E5EA)
    private let fg = Color(light: 0xF2F2F4, dark: 0x1C1C1E)

    private struct Beat { var scale = 1.0; var tilt = 0.0; var ring = 1.0; var ringOpacity = 0.0; var badge = 1.0 }

    /// Rise from behind the sparkle button on insert, sink back (no overshoot, shorter) on removal.
    static var emerge: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: Hidden(), identity: Hidden(hidden: false)),
            removal: .modifier(active: Hidden(), identity: Hidden(hidden: false)).animation(.easeIn(duration: 0.35)))
    }

    private struct Hidden: ViewModifier {
        var hidden = true
        func body(content: Content) -> some View {
            content.offset(y: hidden ? 70 : 0).scaleEffect(hidden ? 0.45 : 1).opacity(hidden ? 0 : 1)
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(bg)
                Circle().fill(Color.appPrimary).opacity(breathe ? 0.2 : 0.05)
                    .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: breathe)
                tray.id(landed)
            }
            .frame(width: 56, height: 56)
            .shadow(color: .black.opacity(0.25), radius: 12, y: 8)
            .keyframeAnimator(initialValue: Beat(), trigger: landed) { view, beat in
                view
                    .overlay {
                        Circle().strokeBorder(Color.appPrimary, lineWidth: 2)
                            .scaleEffect(beat.ring).opacity(beat.ringOpacity)
                    }
                    .scaleEffect(beat.scale).rotationEffect(.degrees(beat.tilt))
                    .overlay(alignment: .topTrailing) { CountBadge(count: shown, scale: beat.badge, bg: bg) }
            } keyframes: { _ in
                // design dgShake / dgRing / dgBadge: 1.08s in, the landing is felt
                let settle = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.2, y: 0.9), endControlPoint: UnitPoint(x: 0.25, y: 1))
                let full = !reduceMotion
                KeyframeTrack(\.scale) {
                    MoveKeyframe(1)
                    LinearKeyframe(1, duration: 1.08)
                    LinearKeyframe(full ? 1.2 : 1, duration: 0.144, timingCurve: settle)
                    LinearKeyframe(full ? 1.12 : 1, duration: 0.18, timingCurve: settle)
                    LinearKeyframe(full ? 1.06 : 1, duration: 0.18, timingCurve: settle)
                    LinearKeyframe(full ? 1.03 : 1, duration: 0.18, timingCurve: settle)
                    LinearKeyframe(1, duration: 0.252, timingCurve: settle)
                }
                KeyframeTrack(\.tilt) {
                    MoveKeyframe(0)
                    LinearKeyframe(0, duration: 1.08)
                    LinearKeyframe(full ? -14 : 0, duration: 0.144, timingCurve: settle)
                    LinearKeyframe(full ? 11 : 0, duration: 0.18, timingCurve: settle)
                    LinearKeyframe(full ? -7 : 0, duration: 0.18, timingCurve: settle)
                    LinearKeyframe(full ? 4 : 0, duration: 0.18, timingCurve: settle)
                    LinearKeyframe(0, duration: 0.252, timingCurve: settle)
                }
                KeyframeTrack(\.ring) {
                    MoveKeyframe(1)
                    LinearKeyframe(1, duration: 1.224)
                    LinearKeyframe(1.9, duration: 1.296, timingCurve: settle)
                }
                KeyframeTrack(\.ringOpacity) {
                    MoveKeyframe(0)
                    LinearKeyframe(0, duration: 1.224)
                    LinearKeyframe(full ? 0.7 : 0, duration: 0.144, timingCurve: settle)
                    LinearKeyframe(0, duration: 1.152, timingCurve: settle)
                }
                KeyframeTrack(\.badge) {
                    MoveKeyframe(isNew && full ? 0 : 1)
                    LinearKeyframe(isNew && full ? 0 : 1, duration: 1.08)
                    LinearKeyframe(1.3, duration: 0.432)
                    LinearKeyframe(1, duration: 0.36)
                }
            }
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(L("Konfirmasi transaksi"))
        .accessibilityValue("\(count)")
        .onAppear { breathe = true; shown = count; sheetOpacity = count >= 2 ? 1 : 0; landed += 1 }
        .onChange(of: count) { old, new in
            guard new > old else {
                shown = new
                if new < 2 { sheetOpacity = 0 }
                return
            }
            isNew = false
            landed += 1
            Task { await drop(to: new) }
        }
    }

    /// Design 3a: a grey sheet falls into the tray and stays; the number rolls when it lands.
    private func drop(to new: Int) async {
        guard new >= 2, !reduceMotion else { shown = new; sheetY = 11; sheetOpacity = new >= 2 ? 1 : 0; return }
        var reset = SwiftUI.Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { sheetY = -18; sheetOpacity = 0 }
        try? await Task.sleep(for: .seconds(0.29))
        withAnimation(.timingCurve(0.2, 0.9, 0.25, 1, duration: 1.44)) { sheetY = 9 }
        withAnimation(.linear(duration: 0.5)) { sheetOpacity = 1 }
        try? await Task.sleep(for: .seconds(0.79))
        withAnimation(.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.5)) { shown = new }
        try? await Task.sleep(for: .seconds(0.94))
        withAnimation(.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.288)) { sheetY = 11 }
    }

    private struct Life { var gold = 0.0; var grey = 0.0; var greyOpacity = 1.0; var trayX = 1.0; var trayY = 1.0 }

    /// Design dgIcA / dgIcB / dgIcT, with 3s of rest between plays: the gold sheet bobs, a grey sheet drops in and lifts out, the tray gives.
    private var tray: some View {
        ZStack(alignment: .topLeading) {
            // behind the gold sheet, grey sheet and tray, so it fills the notch of the tray
            RoundedRectangle(cornerRadius: 3).fill(Color(light: 0x8E8E93, dark: 0x8E8E93))
                .frame(width: 22, height: 14).offset(x: 6, y: 4 + sheetY).opacity(sheetOpacity)
            Color.clear.frame(width: 34, height: 34)
            .keyframeAnimator(initialValue: Life(), repeating: !reduceMotion) { [fg] _, l in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 2.5).fill(Color(light: 0xD9A93A, dark: 0xD9A93A))
                        .frame(width: 16, height: 16).offset(x: 9, y: 5 + l.gold)
                    RoundedRectangle(cornerRadius: 2.5).fill(Color(light: 0x8E8E93, dark: 0x8E8E93))
                        .frame(width: 22, height: 12).offset(x: 6, y: 9 + l.grey).opacity(l.greyOpacity)
                    TrayShape().fill(fg)
                        .scaleEffect(x: l.trayX, y: l.trayY, anchor: .bottom)
                }
                .frame(width: 34, height: 34, alignment: .topLeading)
            } keyframes: { _ in
                // Plays on every landing (the view restarts), then rests 3s and plays again, like the Dompet pile.
                // Segments ease like the CSS keyframes: ease-in-out for dgIcA and dgIcT, cubic-bezier(.2,.9,.25,1) for dgIcB.
                // A quick 0.2s lift-out comes first, so the grey sheet lands with the one that drops from above (design dpDrop).
                let inOut = UnitCurve.easeInOut
                let settle = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.2, y: 0.9), endControlPoint: UnitPoint(x: 0.25, y: 1))
                KeyframeTrack(\.gold) {
                    MoveKeyframe(0)
                    LinearKeyframe(0, duration: 0.2)
                    LinearKeyframe(-3, duration: 0.72, timingCurve: inOut)
                    LinearKeyframe(1, duration: 0.6, timingCurve: inOut)
                    LinearKeyframe(0, duration: 0.48, timingCurve: inOut)
                    LinearKeyframe(0, duration: 3)
                }
                KeyframeTrack(\.grey) {
                    MoveKeyframe(0)
                    LinearKeyframe(-10, duration: 0.2, timingCurve: settle)
                    LinearKeyframe(1.5, duration: 1.2, timingCurve: settle)
                    LinearKeyframe(0, duration: 0.288, timingCurve: settle)
                    LinearKeyframe(0, duration: 3.312)
                }
                KeyframeTrack(\.greyOpacity) {
                    MoveKeyframe(1)
                    LinearKeyframe(0, duration: 0.2, timingCurve: settle)
                    LinearKeyframe(1, duration: 0.6, timingCurve: settle)
                    LinearKeyframe(1, duration: 4.2)
                }
                KeyframeTrack(\.trayX) {
                    LinearKeyframe(1, duration: 1.28)
                    LinearKeyframe(1.06, duration: 0.24, timingCurve: inOut)
                    LinearKeyframe(1, duration: 0.312, timingCurve: inOut)
                    LinearKeyframe(1, duration: 3.168)
                }
                KeyframeTrack(\.trayY) {
                    LinearKeyframe(1, duration: 1.28)
                    LinearKeyframe(0.92, duration: 0.24, timingCurve: inOut)
                    LinearKeyframe(1, duration: 0.312, timingCurve: inOut)
                    LinearKeyframe(1, duration: 3.168)
                }
            }
        }
        .frame(width: 34, height: 34, alignment: .topLeading)
    }
}

private struct CountBadge: View {
    let count: Int
    let scale: Double
    let bg: Color

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.app(count > 9 ? 11 : 12, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .contentTransition(.numericText())
            .animation(.spring(duration: 0.5, bounce: 0.3), value: count)
            .frame(minWidth: 22, minHeight: 22)
            .padding(.horizontal, count > 9 ? 3 : 0)
            .background(Color.appPrimary, in: Capsule())
            .overlay(Capsule().strokeBorder(bg, lineWidth: 2))
            .scaleEffect(scale)
            .offset(x: 4, y: -4)
    }
}

struct TrayShape: Shape {
    func path(in rect: CGRect) -> Path {
        let k = rect.width / 34
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * k, y: rect.minY + y * k) }
        var path = Path()
        path.move(to: pt(3, 18))
        path.addLine(to: pt(12, 18))
        path.addQuadCurve(to: pt(17, 24), control: pt(13, 24))
        path.addQuadCurve(to: pt(22, 18), control: pt(21, 24))
        path.addLine(to: pt(31, 18))
        path.addLine(to: pt(31, 26))
        path.addQuadCurve(to: pt(26, 31), control: pt(31, 31))
        path.addLine(to: pt(8, 31))
        path.addQuadCurve(to: pt(3, 26), control: pt(3, 31))
        path.closeSubpath()
        return path
    }
}

