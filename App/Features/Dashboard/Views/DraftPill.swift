import SwiftUI

/// The Draf pill beside Dompet on Beranda: the tray, "Draf" (over "Kosong" while empty), and on the right a circle
/// with the number of drafts (a chevron while empty). When drafts land, a sheet drops into the tray, the tray gives,
/// and the circle rings: it grows, wobbles and sends out a wave. While drafts wait the background breathes.
struct DraftPill: View {
    let count: Int
    /// The green tint that follows a landing.
    let isFresh: Bool
    /// Changes every time drafts land; each change plays the motion once.
    let landed: Int
    let compact: Bool
    let action: () -> Void

    @State private var start: Date?
    @State private var running = false
    @State private var breathe = false
    @State private var previous = 0

    /// Seconds the landing motion lasts.
    private static let length = 2.6

    var body: some View {
        Button(action: action) {
            TimelineView(.animation(paused: !running)) { context in
                content(start.map { context.date.timeIntervalSince($0) } ?? 99)
            }
            .padding(.leading, compact ? 6 : 8)
            .padding(.trailing, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background { background }
            .clipShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(L("Konfirmasi transaksi"))
        .accessibilityValue(count == 0 ? L("Kosong") : "\(count)")
        .onAppear { breathe = true; previous = count }
        .onChange(of: landed) { _, _ in
            start = Date()
            running = true
            Task {
                try? await Task.sleep(for: .seconds(Self.length + 0.1))
                running = false
                start = nil
            }
        }
        .onChange(of: count) { old, _ in previous = old }
    }

    private var background: some View {
        ZStack {
            Capsule().fill(Color.appFill)
            Capsule().fill(Color.appPrimary.opacity(isFresh ? 0.12 : 0))
                .animation(.easeInOut(duration: 0.4), value: isFresh)
            Capsule().fill(Color.appPrimary)
                .opacity(count > 0 && !isFresh ? (breathe ? 0.2 : 0.05) : 0)
                .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: breathe)
        }
    }

    private func content(_ t: Double) -> some View {
        HStack(spacing: compact ? 6 : 8) {
            DraftTray(count: count, t: t)
                .frame(width: 34, height: 34)
                .scaleEffect(compact ? 0.88 : 1)
                .frame(width: compact ? 30 : 34, height: compact ? 30 : 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("Draf")
                    .font(.app(14, weight: .semibold))
                    .foregroundStyle(Color.appText)
                if count == 0 {
                    Text("Kosong")
                        .font(.app(11))
                        .foregroundStyle(Color.appTextSecondary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            if count > 0 {
                countCircle(t)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(light: 0x8E8E93, dark: 0x8E8E93))
            }
        }
    }

    /// The number in a green circle: it appears with the ring, or rolls up when one more draft lands.
    private func countCircle(_ t: Double) -> some View {
        let appearing = previous == 0 && t < Self.length
        let ring = DraftMotion.at(t, [(1.25, 1), (1.35, 1.3), (1.46, 1.2), (1.56, 1.12), (1.66, 1.06), (1.77, 1.02), (1.93, 1)])
        let tilt = DraftMotion.at(t, [(1.25, 0), (1.35, -16), (1.46, 13), (1.56, -10), (1.66, 6), (1.77, -3), (1.93, 0)])
        let pop = appearing ? DraftMotion.at(t, [(1.2, 0), (1.35, 1)], out: true) : 1
        let waveScale = DraftMotion.at(t, [(1.3, 1), (2.2, 2.1)], out: true)
        let waveOpacity = DraftMotion.at(t, [(1.3, 0), (1.35, 0.7), (2.2, 0)])
        return ZStack {
            Circle().strokeBorder(Color.appPrimary, lineWidth: 2)
                .scaleEffect(waveScale)
                .opacity(waveOpacity)
            Text(count > 99 ? "99+" : "\(count)")
                .font(.app(count > 9 ? 11 : 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.5, bounce: 0.3), value: count)
                .frame(width: 26, height: 26)
                .background(Color.appPrimary, in: Circle())
                .scaleEffect(ring * pop)
                .rotationEffect(.degrees(tilt))
                .opacity(appearing ? DraftMotion.at(t, [(1.2, 0), (1.3, 1)]) : 1)
        }
        .frame(width: 26, height: 26)
    }
}

/// The tray with the sheets standing in it; the newest sheet drops in while `t` runs.
private struct DraftTray: View {
    let count: Int
    let t: Double

    private let gold = Color(light: 0xD9A93A, dark: 0xD9A93A)
    private let purple = Color(light: 0x472B91, dark: 0x472B91)

    var body: some View {
        let landing = t < 2.6
        // the sheet that is falling now: the first one is gold, the next ones purple
        let dropsGold = landing && count == 1
        let dropsPurple = landing && count >= 2
        let newOpacity = DraftMotion.at(t, [(1.4, 0), (1.5, 1)])
        let dropY = DraftMotion.at(t, [(0.2, -18), (1.25, 9), (1.46, 11)], out: true)
        let dropOpacity = DraftMotion.at(t, [(0.2, 0), (0.57, 1), (1.46, 1), (1.5, 0)])
        let squishX = DraftMotion.at(t, [(1.25, 1), (1.46, 0.88), (1.77, 1.08), (2.08, 1)])
        let squishY = DraftMotion.at(t, [(1.25, 1), (1.46, 0.94), (1.77, 1.08), (2.08, 1)])
        return ZStack(alignment: .topLeading) {
            if count >= 1 {
                RoundedRectangle(cornerRadius: 2.5).fill(gold)
                    .frame(width: 16, height: 16).offset(x: 9, y: 5)
                    .opacity(dropsGold ? newOpacity : 1)
            }
            if count >= 2 {
                RoundedRectangle(cornerRadius: 2.5).fill(purple)
                    .frame(width: 22, height: 12).offset(x: 6, y: 9)
                    .opacity(dropsPurple ? newOpacity : 1)
            }
            if dropsGold {
                RoundedRectangle(cornerRadius: 3).fill(gold)
                    .frame(width: 16, height: 16).offset(x: 9, y: 4 + dropY).opacity(dropOpacity)
            }
            if dropsPurple {
                RoundedRectangle(cornerRadius: 3).fill(purple)
                    .frame(width: 22, height: 14).offset(x: 6, y: 4 + dropY).opacity(dropOpacity)
            }
            TrayShape().fill(count > 0 ? Color.appPrimary : Color.appTextTertiary)
                .animation(.easeInOut(duration: 0.4), value: count > 0)
        }
        .frame(width: 34, height: 34, alignment: .topLeading)
        .scaleEffect(x: squishX, y: squishY)
        .accessibilityHidden(true)
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

/// Values over time, eased between keys like CSS keyframes. Before the first key and after the last, the end values hold.
enum DraftMotion {
    static func at(_ t: Double, _ keys: [(Double, Double)], out: Bool = false) -> Double {
        guard let first = keys.first, let last = keys.last else { return 0 }
        if t <= first.0 { return first.1 }
        if t >= last.0 { return last.1 }
        for i in 1..<keys.count where t <= keys[i].0 {
            let (t0, v0) = keys[i - 1], (t1, v1) = keys[i]
            let x = (t - t0) / (t1 - t0)
            let eased = out ? 1 - pow(1 - x, 3) : x * x * (3 - 2 * x)
            return v0 + (v1 - v0) * eased
        }
        return last.1
    }
}
