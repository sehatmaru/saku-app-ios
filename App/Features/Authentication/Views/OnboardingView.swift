import SwiftUI

/// Fixed sample data for the demo on slide 1 (Enhancement 5): nothing is parsed, sent or saved.
struct IntroSample: Equatable {
    let sentence: String
    let name: String
    let isIncome: Bool
    let amount: Double
    let wallet: String
    let category: String

    static let all = [
        IntroSample(sentence: "kopi 25rb gopay", name: "Kopi", isIncome: false, amount: 25_000, wallet: "GoPay", category: "Makan & minum"),
        IntroSample(sentence: "bensin 50rb", name: "Bensin", isIncome: false, amount: 50_000, wallet: "Tunai", category: "Transportasi"),
        IntroSample(sentence: "gajian 5jt", name: "Gaji", isIncome: true, amount: 5_000_000, wallet: "BCA", category: "Pemasukan"),
    ]
}

private extension Animation {
    /// A spring from the prototype's stiffness and damping.
    static func sp(_ stiffness: Double, _ damping: Double) -> Animation {
        .interpolatingSpring(mass: 1, stiffness: stiffness, damping: damping)
    }
}

/// Three slides before sign-in: type one sentence, all wallets and budgets on one screen, you stay in control.
/// Swiping follows the finger with a different parallax for each layer; each slide plays its own little scene
/// while it is current. Reduce Motion swaps the movement for a short fade.
struct OnboardingView: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduce
    /// The page as a fraction: dragged live, then settled by a spring.
    @State private var pos = 0.0
    @State private var act = 0
    @State private var started = false
    @State private var dragBase: Double?

    private static let slideCount = 3

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let column = min(342, w - 48)
            // the artwork is drawn for a 844pt screen: shorter ones shrink it
            let scale = max(0.6, min(column / 342, 1, (geo.size.height - 321) / 372))
            VStack(spacing: 0) {
                skipBar
                ZStack {
                    ForEach(0..<Self.slideCount, id: \.self) { i in
                        IntroSlide(index: i, pos: pos, isActive: started && act == i, width: w, column: column, scale: scale, reduce: reduce)
                    }
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(swipe(w))
                .clipped()
                footer
            }
        }
        .background(Color.appBackground)
        .sensoryFeedback(.selection, trigger: act)
        .task {
            try? await Task.sleep(for: .milliseconds(150))
            started = true
        }
    }

    // MARK: - Paging

    private func swipe(_ w: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let base = dragBase ?? pos
                dragBase = base
                guard !reduce else { return }
                var p = base - value.translation.width / w
                if p < 0 { p *= 0.35 }
                if p > 2 { p = 2 + (p - 2) * 0.35 }
                pos = p
                act = min(max(Int(p.rounded()), 0), Self.slideCount - 1)
            }
            .onEnded { value in
                let base = dragBase ?? pos
                dragBase = nil
                let flick = -(value.predictedEndTranslation.width - value.translation.width) / w
                let from = reduce ? base - value.translation.width / w : pos
                go(Int((from + flick * 0.9).rounded()))
            }
    }

    private func go(_ index: Int) {
        let target = min(max(index, 0), Self.slideCount - 1)
        withAnimation(reduce ? .easeOut(duration: 0.25) : .sp(190, 21)) { pos = Double(target) }
        act = target
    }

    // MARK: - Chrome

    private var skipBar: some View {
        HStack {
            Spacer()
            Button("Lewati") { onFinish() }
                .font(.app(16, weight: .medium))
                .foregroundStyle(Color.appPrimary)
                .frame(minWidth: 64, minHeight: 44)
        }
        .padding(.horizontal, 12)
    }

    private var footer: some View {
        let t = min(max(pos - 1, 0), 1)
        return VStack(spacing: 28) {
            HStack(spacing: 26) {
                ForEach(0..<Self.slideCount, id: \.self) { i in
                    let near = reduce ? (act == i ? 1.0 : 0) : max(0, 1 - abs(pos - Double(i)))
                    Capsule()
                        .fill(Color.appPrimary)
                        .frame(width: 7, height: 7)
                        .scaleEffect(x: 1 + 2.4 * near)
                        .opacity(0.22 + 0.78 * near)
                        .contentShape(Rectangle().inset(by: -14))
                        .onTapGesture { go(i) }
                }
            }
            .animation(reduce ? .easeOut(duration: 0.2) : nil, value: act)
            .accessibilityElement()
            .accessibilityLabel(L("Halaman %lld dari 3", act + 1))

            Button { if act < Self.slideCount - 1 { go(act + 1) } else { onFinish() } } label: {
                ZStack {
                    Text("Lanjut").opacity(1 - t).offset(y: reduce ? 0 : -12 * t)
                    Text("Yuk, masuk").opacity(t).offset(y: reduce ? 0 : 12 * (1 - t))
                }
                .font(.app(17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.appPrimary, in: Capsule())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel(act < Self.slideCount - 1 ? L("Lanjut") : L("Yuk, masuk"))
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
    }
}

// MARK: - One slide

private struct IntroSlide: View {
    let index: Int
    let pos: Double
    let isActive: Bool
    let width: CGFloat
    let column: CGFloat
    let scale: CGFloat
    let reduce: Bool

    private var d: Double { Double(index) - pos }

    private struct Copy { let title: String; let text: String }
    private var copy: Copy {
        switch index {
        case 0: Copy(title: L("Catat cukup satu kalimat."), text: L("Ketik atau ucapkan, misalnya “kopi 25rb gopay”. Sisanya Saku yang rapikan."))
        case 1: Copy(title: L("Semua dompet dan budgetmu, satu layar."), text: L("Bank, e-wallet, tunai, sampai kartu kredit. Sisa budget kelihatan jelas, dari hijau sampai merah."))
        default: Copy(title: L("Kamu yang pegang kendali."), text: L("Tiap catatan kamu cek dulu sebelum tersimpan. Datamu bisa kamu hapus kapan saja."))
        }
    }

    var body: some View {
        let visible = reduce ? true : abs(d) < 1.05
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                Circle()
                    .fill(Color.appPrimary.opacity(index == 1 ? 0.0 : 0.10))
                    .overlay { if index == 1 { Circle().fill(Color.appFill) } }
                    .frame(width: 320, height: 320)
                    .offset(x: 11, y: 26)
                    .enters(isActive, y: 0, zoom: true, delay: 0, k: 90, c: 14, reduce: reduce)
                    .parallax(d, width, 0.55, reduce: reduce)
                IntroDots(index: index, reduce: reduce)
                    .enters(isActive, y: -20, zoom: false, delay: 0.1, k: 110, c: 11, reduce: reduce)
                    .parallax(d, width, 1.7, reduce: reduce)
                Group {
                    switch index {
                    case 0: IntroTypeDemo(isActive: isActive, reduce: reduce)
                    case 1: IntroWalletsScene(isActive: isActive, reduce: reduce)
                    default: IntroControlScene(isActive: isActive, reduce: reduce)
                    }
                }
                .enters(isActive, y: 26, zoom: true, delay: 0, k: 120, c: 15, reduce: reduce)
                .parallax(d, width, 1.12, reduce: reduce)
            }
            .frame(width: 342, height: 372, alignment: .topLeading)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: 342 * scale, height: 372 * scale, alignment: .topLeading)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 0) {
                IntroTitle(text: copy.title, isActive: isActive, reduce: reduce)
                    .parallax(d, width, 1, reduce: reduce)
                    .padding(.top, 16)
                Text(copy.text)
                    .font(.app(16))
                    .lineSpacing(4)
                    .foregroundStyle(Color.appTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .enters(isActive, y: 18, zoom: false, delay: 0.16, k: 220, c: 22, reduce: reduce)
                    .parallax(d, width, 0.88, reduce: reduce)
                    .padding(.top, 12)
            }
            .frame(width: column, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 4)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(isActive)
    }
}

private extension View {
    /// Rises in (and zooms a little) when `on`; leaves quicker than it came.
    func enters(_ on: Bool, y: CGFloat, zoom: Bool, delay: Double, k: Double, c: Double, reduce: Bool) -> some View {
        opacity(on ? 1 : 0)
            .offset(y: reduce || on ? 0 : y)
            .scaleEffect(zoom && !reduce && !on ? 0.92 : 1)
            .animation(on ? (reduce ? .easeOut(duration: 0.25) : .sp(k, c).delay(delay)) : (reduce ? .easeOut(duration: 0.15) : .sp(k * 2.2, c * 1.6)), value: on)
    }

    /// Slides sideways at its own pace while the page is dragged, and fades away from the centre.
    func parallax(_ d: Double, _ width: CGFloat, _ factor: Double, reduce: Bool) -> some View {
        offset(x: reduce ? 0 : CGFloat(d) * width * factor)
            .opacity(reduce ? 1 : min(max(1 - abs(d) * 1.25, 0), 1))
    }
}

// MARK: - Title with words rising one after another

private struct IntroTitle: View {
    let text: String
    let isActive: Bool
    let reduce: Bool

    var body: some View {
        FlowLayout(spacing: 7) {
            ForEach(Array(text.split(separator: " ").enumerated()), id: \.offset) { j, word in
                Text(String(word))
                    .font(.app(30, weight: .bold)).tracking(-0.7)
                    .foregroundStyle(Color.appText)
                    // lines sit 35pt apart as in the design (the flow layout's gap is added to this)
                    .frame(height: 28)
                    .opacity(isActive ? 1 : 0)
                    .offset(y: reduce || isActive ? 0 : 34)
                    .rotationEffect(.degrees(reduce || isActive ? 0 : 5), anchor: .bottomLeading)
                    .animation(isActive ? (reduce ? .easeOut(duration: 0.25) : .sp(200, 16).delay(0.08 + Double(j) * 0.055)) : .sp(440, 26), value: isActive)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Floating dots

private struct IntroDots: View {
    let index: Int
    let reduce: Bool

    private var dots: [(x: CGFloat, y: CGFloat, size: CGFloat, color: Color)] {
        let tint = Color.appPrimary.opacity(0.12), grey = Color(light: 0xE5E5EA, dark: 0x38383A)
        switch index {
        case 0: return [(208, 338, 18, tint), (302, 350, 10, grey), (-20, 70, 14, tint), (346, 196, 12, .appPrimary)]
        case 1: return [(-18, 150, 22, grey), (336, 96, 14, tint), (-14, 60, 10, .appPrimary)]
        default: return []
        }
    }

    var body: some View {
        TimelineView(.animation(paused: reduce)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .topLeading) {
                ForEach(Array(dots.enumerated()), id: \.offset) { j, dot in
                    Circle().fill(dot.color)
                        .frame(width: dot.size, height: dot.size)
                        .offset(x: dot.x + (reduce ? 0 : sin(t * 0.7 + Double(j) * 2.1) * 5),
                                y: dot.y + (reduce ? 0 : sin(t * 0.9 + Double(j) * 1.7) * 9))
                }
            }
            .frame(width: 342, height: 372, alignment: .topLeading)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Slide 1: tap a sentence, get a draft

private struct IntroTypeDemo: View {
    let isActive: Bool
    let reduce: Bool

    @State private var selected: Int?
    @State private var shown = 0
    @State private var typed = ""
    @State private var cardIn = false
    @State private var typedMoved = false
    @State private var task: Task<Void, Never>?
    @State private var landed = 0

    private var sample: IntroSample { IntroSample.all[shown] }
    private let soft = Color(light: 0xF7F7F8, dark: 0x1C1C1E)

    var body: some View {
        ZStack(alignment: .topLeading) {
            draftCard
                .opacity(cardIn ? 1 : 0)
                .offset(y: reduce || cardIn ? 0 : 70)
                .scaleEffect(reduce || cardIn ? 1 : 0.86, anchor: .bottom)
                .animation(reduce ? .easeOut(duration: 0.2) : cardIn ? .sp(200, 13) : .sp(420, 34), value: cardIn)
            field.offset(y: 176)
            Text("Coba ketuk salah satu:")
                .font(.app(13)).foregroundStyle(Color.appTextSecondary)
                .offset(x: 2, y: 248)
            FlowLayout(spacing: 8) {
                ForEach(Array(IntroSample.all.enumerated()), id: \.offset) { i, s in chip(i, s) }
            }
            .frame(width: 342, alignment: .leading)
            .offset(y: 272)
        }
        .frame(width: 342, height: 372, alignment: .topLeading)
        .sensoryFeedback(.impact(weight: .light), trigger: landed)
        .task(id: isActive) {
            if isActive {
                try? await Task.sleep(for: .milliseconds(550))
                guard !Task.isCancelled else { return }
                run(0, delay: 0)
            } else {
                task?.cancel()
                withAnimation(.sp(300, 26)) { cardIn = false; typedMoved = false }
                typed = ""
                selected = nil
            }
        }
    }

    private var draftCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L(sample.name)).font(.app(20, weight: .semibold)).tracking(-0.3)
                Spacer()
                Text("Draf")
                    .font(.app(12, weight: .semibold)).foregroundStyle(Color.appPrimary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.appPrimary.opacity(0.12), in: Capsule())
            }
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: 0) {
                Text(sample.isIncome ? "+" : "−").font(.app(44, weight: .light))
                Text("Rp").font(.app(17)).foregroundStyle(Color.appTextSecondary).padding(.top, 6).padding(.horizontal, 3)
                Text(sample.amount.formattedAsDigits()).font(.app(44, weight: .light)).tracking(-1.5)
            }
            .monospacedDigit()
            .foregroundStyle(sample.isIncome ? Color.appPrimary : Color.appText)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                pill(L(sample.wallet))
                pill(L(sample.category))
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .frame(width: 342, height: 160)
        .background(soft, in: RoundedRectangle(cornerRadius: 20))
        .foregroundStyle(Color.appText)
    }

    private func pill(_ text: String) -> some View {
        Text(text).font(.app(13, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.appBackground, in: Capsule())
    }

    private var field: some View {
        HStack {
            ZStack(alignment: .leading) {
                if typed.isEmpty { Text("Ketik atau ucapkan…").font(.app(17)).foregroundStyle(Color.appTextTertiary) }
                Text(typed).font(.app(17)).foregroundStyle(Color.appText).lineLimit(1)
                    .opacity(typedMoved ? 0 : 1)
                    .offset(y: reduce || !typedMoved ? 0 : -58)
                    .scaleEffect(reduce || !typedMoved ? 1 : 0.65, anchor: .leading)
                    .animation(reduce ? .easeOut(duration: 0.2) : .sp(260, 26), value: typedMoved)
            }
            Spacer(minLength: 8)
            micButton
        }
        .padding(.leading, 18).padding(.trailing, 14)
        .frame(width: 342, height: 56)
        .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.appBorder, lineWidth: 1))
    }

    private var micButton: some View {
        TimelineView(.animation(paused: reduce || !typed.isEmpty)) { context in
            let ph = (context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8)) / 1.8
            ZStack {
                Circle().stroke(Color.appPrimary, lineWidth: 2)
                    .opacity(typed.isEmpty && !reduce ? (1 - ph) * 0.55 : 0)
                    .scaleEffect(1 + ph * 0.5)
                Circle().fill(Color.appPrimary.opacity(0.12))
                Image(systemName: "mic").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.appPrimary)
            }
            .frame(width: 32, height: 32)
        }
        .accessibilityHidden(true)
    }

    private func chip(_ i: Int, _ s: IntroSample) -> some View {
        let on = selected == i
        return Button { run(i, delay: 0.04) } label: {
            Text(s.sentence)
                .font(.app(15))
                .foregroundStyle(on ? Color.appBackground : Color.appText)
                .padding(.horizontal, 16).frame(height: 44)
                .background(on ? Color.appText : Color.appBackground, in: Capsule())
                .overlay(Capsule().strokeBorder(on ? Color.appText : Color.appBorder, lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle())
        .animation(.easeOut(duration: 0.2), value: on)
    }

    /// Types the sentence letter by letter, lifts it into a draft, then clears the field.
    private func run(_ i: Int, delay: Double) {
        task?.cancel()
        task = Task { @MainActor in
            selected = i
            let sentence = IntroSample.all[i].sentence
            if cardIn {
                withAnimation { cardIn = false }
                try? await Task.sleep(for: .milliseconds(reduce ? 150 : 240))
                guard !Task.isCancelled else { return }
            }
            typedMoved = false
            typed = ""
            try? await Task.sleep(for: .milliseconds(Int(delay * 1000) + 80))
            guard !Task.isCancelled else { return }
            for n in 1...sentence.count {
                typed = String(sentence.prefix(n))
                try? await Task.sleep(for: .milliseconds(reduce ? 12 : Int.random(in: 34...62)))
                guard !Task.isCancelled else { return }
            }
            try? await Task.sleep(for: .milliseconds(240))
            guard !Task.isCancelled else { return }
            shown = i
            typedMoved = true
            try? await Task.sleep(for: .milliseconds(reduce ? 0 : 110))
            guard !Task.isCancelled else { return }
            withAnimation { cardIn = true }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            landed += 1
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            typed = ""
            typedMoved = false
        }
    }
}

// MARK: - Slide 2: wallets fan out, budgets fill

private struct IntroWalletsScene: View {
    let isActive: Bool
    let reduce: Bool

    private struct Wallet { let name: String; let kind: String; let amount: String; let color: Color }
    private let wallets = [
        Wallet(name: "Kartu kredit", kind: "Kredit", amount: "Rp2.400.000", color: Color(hex: "111111")),
        Wallet(name: "Tunai", kind: "Tunai", amount: "Rp350.000", color: Color(hex: "6E6E73")),
        Wallet(name: "GoPay", kind: "E-wallet", amount: "Rp875.000", color: Color(hex: "16875A")),
        Wallet(name: "BCA", kind: "Bank", amount: "Rp4.250.000", color: Color(hex: "143A73")),
    ]
    private struct Row { let name: String; let label: String; let color: Color; let labelColor: Color; let filled: Int }
    private let rows = [
        Row(name: "Makan", label: "Sisa Rp1.250.000", color: .appPrimary, labelColor: .appTextSecondary, filled: 12),
        Row(name: "Belanja", label: "Hampir habis", color: .appWarning, labelColor: .appWarning, filled: 26),
        Row(name: "Hiburan", label: "Lewat Rp120.000", color: .appError, labelColor: .appError, filled: 30),
    ]

    /// 0 hidden below, 1 fanned out, 2 stacked.
    @State private var stages = [0, 0, 0, 0]
    @State private var barsOn = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(wallets.indices, id: \.self) { i in card(i) }
            ForEach(rows.indices, id: \.self) { j in budgetRow(j).offset(y: 244 + CGFloat(j) * 44) }
        }
        .frame(width: 342, height: 372, alignment: .topLeading)
        .task(id: isActive) {
            if isActive {
                if reduce {
                    stages = [2, 2, 2, 2]; barsOn = true
                    return
                }
                try? await Task.sleep(for: .milliseconds(200))
                for i in wallets.indices {
                    guard !Task.isCancelled else { return }
                    withAnimation(.sp(150, 15)) { stages[i] = 1 }
                    try? await Task.sleep(for: .milliseconds(45))
                }
                try? await Task.sleep(for: .milliseconds(800))
                for i in wallets.indices {
                    guard !Task.isCancelled else { return }
                    withAnimation(.sp(150, 15)) { stages[i] = 2 }
                    try? await Task.sleep(for: .milliseconds(45))
                }
                try? await Task.sleep(for: .milliseconds(250))
                barsOn = true
            } else {
                withAnimation(reduce ? .easeOut(duration: 0.15) : .sp(300, 26)) { stages = [0, 0, 0, 0] }
                barsOn = false
            }
        }
    }

    private func pose(_ i: Int, _ stage: Int) -> (x: CGFloat, y: CGFloat, angle: Double, scale: CGFloat, opacity: Double) {
        let o = Double(i) - 1.5
        switch stage {
        case 1: return (CGFloat(o * 42), 56, o * 11, 1, 1)
        case 2: return (0, CGFloat(i) * 30, 0, 0.85 + 0.05 * CGFloat(i), 1)
        default: return (0, 110, 0, 0.9, 0)
        }
    }

    private func card(_ i: Int) -> some View {
        let w = wallets[i], p = pose(i, stages[i])
        return VStack(alignment: .leading) {
            HStack {
                Text(L(w.name)).font(.app(15, weight: .semibold))
                Spacer()
                Text(L(w.kind)).font(.app(12, weight: .medium))
            }
            Spacer(minLength: 0)
            Text(w.amount).font(.app(26, weight: .light)).tracking(-0.6)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18).padding(.vertical, 12)
        .frame(width: 280, height: 132)
        .background(w.color, in: RoundedRectangle(cornerRadius: 20))
        .rotationEffect(.degrees(p.angle), anchor: UnitPoint(x: 0.5, y: 1.3))
        .scaleEffect(p.scale)
        .opacity(p.opacity)
        .offset(x: 31 + p.x, y: p.y)
    }

    private func budgetRow(_ j: Int) -> some View {
        let r = rows[j]
        return VStack(spacing: 6) {
            HStack {
                Text(L(r.name)).font(.app(15, weight: .medium))
                Spacer()
                Text(L(r.label)).font(.app(13, weight: j == 0 ? .regular : .medium)).foregroundStyle(r.labelColor)
            }
            SegmentTrack(count: 30, filled: barsOn ? r.filled : 0, color: r.color, track: Color(light: 0xE5E5EA, dark: 0x38383A),
                         delay: reduce ? 0 : Double(j) * 0.14, step: reduce ? 0 : 0.016)
                .frame(height: 8)
        }
        .foregroundStyle(Color.appText)
        .frame(width: 342)
    }
}

// MARK: - Slide 3: the draft waits for you

private struct IntroControlScene: View {
    let isActive: Bool
    let reduce: Bool

    @State private var saved = false
    @State private var popped = false
    @State private var savedCount = 0
    @State private var barsOn = false
    @State private var shakes = 0
    @State private var revert: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .topLeading) {
            draft.offset(y: 20)
            stamp.offset(x: 342 - 34, y: 0)
            budget.offset(y: 296)
        }
        .frame(width: 342, height: 372, alignment: .topLeading)
        .sensoryFeedback(.success, trigger: savedCount)
        .task(id: isActive) {
            if isActive {
                try? await Task.sleep(for: .milliseconds(reduce ? 0 : 700))
                guard !Task.isCancelled else { return }
                barsOn = true
                if !reduce {
                    try? await Task.sleep(for: .milliseconds(1100))
                    guard !Task.isCancelled else { return }
                    withAnimation(.settle(0.5)) { shakes += 1 }
                    try? await Task.sleep(for: .milliseconds(1000))
                }
                while !Task.isCancelled {
                    save()
                    try? await Task.sleep(for: .milliseconds(4600))
                }
            } else {
                revert?.cancel()
                unsave()
                barsOn = false
            }
        }
    }

    private var draft: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(saved ? "Tersimpan" : "Draf")
                    .transaction { $0.animation = nil }
                    .font(.app(12, weight: .semibold)).foregroundStyle(Color.appPrimary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.appPrimary.opacity(0.12), in: Capsule())
                Spacer()
                Text(saved ? "Sudah masuk catatan" : "Menunggu kamu").font(.app(13)).foregroundStyle(Color.appTextSecondary)
                    .transaction { $0.animation = nil }
            }
            Text("Kopi").font(.app(20, weight: .semibold)).tracking(-0.3).padding(.top, 12)
            HStack(alignment: .top, spacing: 0) {
                Text("−").font(.app(44, weight: .light))
                Text("Rp").font(.app(17)).foregroundStyle(Color.appTextSecondary).padding(.top, 6).padding(.horizontal, 3)
                Text(25_000.0.formattedAsDigits()).font(.app(44, weight: .light)).tracking(-1.5)
            }
            .monospacedDigit()
            Text("GoPay · Makan & minum").font(.app(13)).foregroundStyle(Color.appTextSecondary).padding(.top, 2).padding(.bottom, 16)
            HStack(spacing: 10) {
                Button {} label: {
                    Text("Batal").font(.app(15, weight: .medium)).foregroundStyle(Color.appText)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .overlay(Capsule().strokeBorder(Color.appBorder, lineWidth: 1))
                }
                .buttonStyle(PressScaleStyle())
                ZStack {
                    halo
                    Button { save() } label: {
                        Text(saved ? "Tersimpan" : "Simpan").font(.app(15, weight: .semibold)).foregroundStyle(.white)
                    .transaction { $0.animation = nil }
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(Color.appPrimary, in: Capsule())
                    }
                    .buttonStyle(PressScaleStyle())
                }
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(Color.appText)
        .padding(20)
        .frame(width: 342)
        .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(saved ? Color.appPrimary : Color(light: 0xA1A1A6, dark: 0x636366),
                              style: StrokeStyle(lineWidth: 1.5, dash: saved ? [] : [6, 4]))
        )
        .scaleEffect(popped ? 1.03 : 1)
        .animation(.easeOut(duration: 0.25), value: saved)
    }

    /// A soft green ring breathing around "Simpan" until it is pressed.
    private var halo: some View {
        TimelineView(.animation(paused: reduce || saved)) { context in
            let ph = (context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.2)) / 2.2
            Capsule().fill(Color.appPrimary)
                .frame(height: 44)
                .opacity(saved || reduce ? 0 : (1 - ph) * 0.35)
                .scaleEffect(x: 1 + ph * 0.14, y: 1 + ph * 0.4)
        }
        .allowsHitTesting(false)
    }

    private var stamp: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 18, weight: .heavy)).foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(Color.appPrimary, in: Circle())
            .scaleEffect(saved ? 1 : 0.01)
            .rotationEffect(.degrees(saved || reduce ? 0 : -25))
            .opacity(saved ? 1 : 0)
            .animation(reduce ? .easeOut(duration: 0.2) : saved ? .sp(260, 11) : .sp(400, 30), value: saved)
            .allowsHitTesting(false)
    }

    private var budget: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Budget Makan").font(.app(15, weight: .medium))
                Spacer()
                Text("Sisa Rp1.225.000").font(.app(13)).foregroundStyle(Color.appTextSecondary)
            }
            SegmentTrack(count: 30, filled: barsOn ? 19 : 0, color: .appPrimary, track: Color(light: 0xE5E5EA, dark: 0x38383A),
                         delay: 0, step: reduce ? 0 : 0.016)
                .frame(height: 8)
        }
        .foregroundStyle(Color.appText)
        .frame(width: 342)
        .modifier(ShakeEffect(shakes: CGFloat(shakes)))
    }

    private func save() {
        guard !saved else { return }
        revert?.cancel()
        withAnimation(.easeOut(duration: 0.25)) { saved = true }
        savedCount += 1
        if !reduce {
            withAnimation(.sp(320, 9)) { popped = true }
            Task { try? await Task.sleep(for: .milliseconds(90)); withAnimation(.sp(320, 12)) { popped = false } }
        }
        revert = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            unsave()
        }
    }

    private func unsave() {
        withAnimation(.easeOut(duration: 0.25)) { saved = false }
    }
}

#Preview {
    OnboardingView {}
}
