import SwiftUI

/// "Siap": the screen after setup is saved (design v4). Green for everyone, black and gold when the Plus trial
/// started. "Buka Sakumu" lets it slide away over Beranda; "Catat pengeluaran pertamamu" does the same and then
/// opens where the first entry is made.
struct SetupWelcomeView: View {
    let welcome: SetupWelcome
    /// `startsEntry` is true for "Catat pengeluaran pertamamu".
    let onOpen: (_ startsEntry: Bool) -> Void
    @State private var logoOpen = false

    private var isPlus: Bool { welcome.joinedPlus }
    private var shownName: String { welcome.name.isEmpty ? "Saku" : welcome.name }

    var body: some View {
        ZStack {
            (isPlus ? Color(hex: "0B0B0C") : Color.appBrand).ignoresSafeArea()
            VStack(spacing: 0) {
                if isPlus { plusHero } else { greenHero }
                VStack(alignment: .leading, spacing: 0) {
                    if isPlus { plusText } else { greenText }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                VStack(spacing: 4) {
                    Button { onOpen(false) } label: {
                        Text("Buka Sakumu")
                            .font(.app(17, weight: .semibold))
                            .foregroundStyle(isPlus ? Color(hex: "111111") : Color(hex: "0F6B46"))
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(isPlus ? Color(hex: "E3B34F") : .white, in: Capsule())
                    }
                    .buttonStyle(PressScaleStyle())
                    Button { onOpen(true) } label: {
                        Text("Catat pengeluaran pertamamu")
                            .font(.app(17, weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 48)
                    }
                }
                .padding(.horizontal, 24).padding(.bottom, 24).padding(.top, 12)
                .rise(true, y: 16, delay: isPlus ? 2.3 : 2.2, fade: 0.6, move: 0.6)
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            logoOpen = true
        }
    }

    // MARK: Green

    private var greenHero: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { index in
                Halo(color: .white, size: 130, lineWidth: 2, duration: 1.6, delay: 0.5 + Double(index) * 0.3)
            }
            ForEach(0..<28, id: \.self) { index in ConfettiParticle(index: index) }
            PocketLogo(isOpen: logoOpen, motion: { .timingCurve(0.34, 1.45, 0.5, 1, duration: $0) })
                .frame(width: 130, height: 130)
                .popIn(duration: 0.7, delay: 0.1)
                .drifting(delay: 1.2)
        }
        .frame(height: 230)
        .frame(maxWidth: .infinity)
    }

    private var greenText: some View {
        VStack(alignment: .leading, spacing: 0) {
            Words(text: L("Selamat datang, %@", shownName), size: 38, tracking: -0.6, spacing: 10, start: 0.7, step: 0.11)
            Text("Sakumu sudah siap dipakai.")
                .font(.app(17)).foregroundStyle(.white)
                .padding(.top, 8)
                .rise(true, y: 16, delay: 1.1, fade: 0.6, move: 0.6)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { index, tile in
                    SummaryTile(tile: tile).popIn(duration: 0.55, delay: 1.25 + Double(index) * 0.12)
                }
            }
            .padding(.top, 18)
            Text(plan)
                .font(.app(15)).foregroundStyle(.white).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
                .rise(true, y: 16, delay: 2.0, fade: 0.6, move: 0.6)
        }
    }

    struct Tile: Equatable {
        var number: Double?
        var text: String
        var label: String
    }

    var tiles: [Tile] {
        var result = [Tile(number: Double(welcome.wallets), text: "", label: L("dompet")),
                      Tile(number: Double(welcome.categories), text: "", label: L("kategori"))]
        switch welcome.paydayDay {
        case .some(31): result.append(Tile(number: nil, text: L("Akhir"), label: L("bulan, tanggal gajian")))
        case .some(let day) where day > 1: result.append(Tile(number: Double(day), text: "", label: L("tanggal gajian")))
        default: result.append(Tile(number: nil, text: L("Tgl 1"), label: L("tanggal mulai periode")))
        }
        if welcome.budgetTotal > 0 {
            result.append(Tile(number: nil, text: "Rp" + welcome.budgetTotal.abbreviatedRupiah(), label: L("budget per periode")))
        }
        return result
    }

    private var plan: String {
        if let until = welcome.plusUntil, isPlus {
            return L("Uji coba Plus aktif sampai %@. Batalkan kapan saja.", Self.dayMonth(until))
        }
        return L("Paket Gratis: %lld dompet uang, %lld budget, %lld kategori pengeluaran.",
                 FreeLimits.moneyWallets, FreeLimits.budgets, FreeLimits.expenseCategories)
    }

    private static func dayMonth(_ date: Date) -> String { PaydayCycle.dayMonth.string(from: date) }

    // MARK: Plus

    private var plusHero: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { index in
                Halo(color: Color(hex: "E3B34F"), size: 200, lineWidth: 1, duration: 2.2, delay: 0.5 + Double(index) * 0.5)
            }
            ZStack {
                Circle().strokeBorder(Color(hex: "2A2A2D"), lineWidth: 2)
                ForEach(0..<7, id: \.self) { index in
                    let angle = (-90 + Double(index) * 360 / 7) * .pi / 180
                    Circle().fill(Color(hex: "E3B34F")).frame(width: 14, height: 14)
                        .background(Circle().fill(Color(hex: "0B0B0C")).frame(width: 22, height: 22))
                        .offset(x: 99 * cos(angle), y: 99 * sin(angle))
                        .popIn(duration: 0.5, delay: 0.6 + Double(index) * 0.12)
                }
                VStack(spacing: 2) {
                    CountUp(target: 7, duration: 1.2, delay: 0.3)
                        .font(.app(88, weight: .ultraLight)).tracking(-3)
                        .foregroundStyle(Color(hex: "E3B34F")).monospacedDigit()
                    Text("hari Plus gratis").font(.app(15)).foregroundStyle(.white)
                }
            }
            .frame(width: 200, height: 200)
            .popIn(duration: 0.8, delay: 0.1)
            ForEach(Array([(-150.0, -78.0, 0.0), (110.0, -100.0, 0.6), (140.0, 60.0, 1.1), (-130.0, 80.0, 1.6)].enumerated()), id: \.offset) { _, spot in
                Image(systemName: "sparkles").font(.system(size: 16)).foregroundStyle(Color(hex: "E3B34F"))
                    .offset(x: spot.0, y: spot.1)
                    .twinkling(delay: spot.2)
            }
        }
        .frame(height: 236)
        .frame(maxWidth: .infinity)
    }

    private var plusText: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SAKU PLUS AKTIF")
                .font(.app(11, weight: .bold)).tracking(2.4).foregroundStyle(Color(hex: "E3B34F"))
                .rise(true, y: 16, delay: 0.5, fade: 0.6, move: 0.6)
            Words(text: L("Selamat datang di Plus, %@", shownName), size: 34, tracking: -0.5, spacing: 9, start: 0.8, step: 0.1)
                .padding(.top, 8)
            VStack(spacing: 0) {
                ForEach(Array(["Bantuan AI tanpa batas", "Laporan PDF", "Analisis keuangan"].enumerated()), id: \.offset) { index, perk in
                    HStack(spacing: 14) {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Color(hex: "111111"))
                            .frame(width: 26, height: 26).background(Color(hex: "E3B34F"), in: Circle())
                            .popIn(duration: 0.5, delay: 1.7 + Double(index) * 0.2)
                        Text(L(perk)).font(.app(16, weight: .semibold)).foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .rise(true, y: 16, delay: 1.5 + Double(index) * 0.2, fade: 0.5, move: 0.5)
                }
            }
            .padding(.top, 20)
            Text(plan)
                .font(.app(14)).foregroundStyle(Color(hex: "A1A1A6")).lineSpacing(2)
                .padding(.top, 6)
                .rise(true, y: 16, delay: 2.1, fade: 0.6, move: 0.6)
        }
    }
}

// MARK: - Pieces

/// A ring that grows from the middle and fades out.
private struct Halo: View {
    let color: Color
    let size: CGFloat
    let lineWidth: CGFloat
    let duration: Double
    let delay: Double
    @State private var spread = false
    @State private var started = false

    var body: some View {
        Circle().strokeBorder(color, lineWidth: lineWidth)
            .frame(width: size, height: size)
            .scaleEffect(spread ? 2.2 : 0.4)
            .opacity(started ? (spread ? 0 : 0.5) : 0)
            .task {
                try? await Task.sleep(for: .seconds(delay))
                started = true
                withAnimation(.settle(duration)) { spread = true }
            }
    }
}

/// One piece of confetti: a small tick or dot that flies out from the pocket along its own angle and fades.
private struct ConfettiParticle: View {
    let index: Int
    @State private var phase = 0

    private static let colors = [Color.white, Color(hex: "E8F5EE"), Color(hex: "3DDC97")]

    var body: some View {
        let isTick = index.isMultiple(of: 2)
        let distance: CGFloat = [150, 210, 280][index % 3]
        let spin: Double = [200, -240, 320][index % 3]
        let duration = 1.4 + Double(index % 4) * 0.15
        let delay = 0.45 + Double(index % 5) * 0.04
        RoundedRectangle(cornerRadius: isTick ? 2 : 99)
            .fill(Self.colors[index % 3])
            .frame(width: isTick ? 4 : 8, height: isTick ? 14 : 8)
            .scaleEffect(phase == 2 ? 1 : 0.5)
            .rotationEffect(.degrees(phase == 2 ? spin : 0))
            .offset(y: phase == 2 ? -distance : -10)
            .opacity(phase == 1 ? 1 : 0)
            .rotationEffect(.degrees(Double(index) * (360 / 28) + Double(index % 3) * 4), anchor: .center)
            .task {
                try? await Task.sleep(for: .seconds(delay))
                phase = 1
                withAnimation(.settle(duration)) { phase = 2 }
            }
    }
}

/// Words that rise in one after the other.
private struct Words: View {
    let text: String
    let size: CGFloat
    let tracking: CGFloat
    let spacing: CGFloat
    let start: Double
    let step: Double

    var body: some View {
        FlowLayout(spacing: spacing) {
            ForEach(Array(text.split(separator: " ").enumerated()), id: \.offset) { index, word in
                Text(String(word))
                    .font(.app(size, weight: .bold)).tracking(tracking)
                    .foregroundStyle(.white)
                    .rise(true, y: 16, delay: start + Double(index) * step, fade: 0.7, move: 0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SummaryTile: View {
    let tile: SetupWelcomeView.Tile
    @State private var counted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if let number = tile.number {
                    CountingText(value: counted ? number : 0) { $0.formattedAsDigits() }
                        .font(.app(44, weight: .ultraLight)).tracking(-1)
                        .animation(.timingCurve(0.33, 1, 0.68, 1, duration: 0.9), value: counted)
                } else {
                    Text(tile.text).font(.app(32, weight: .ultraLight)).tracking(-1)
                }
            }
            .foregroundStyle(.white).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            .frame(height: 52, alignment: .leading)
            Text(tile.label).font(.app(13)).foregroundStyle(Color(hex: "E8F5EE"))
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 20))
        .task {
            try? await Task.sleep(for: .milliseconds(1400))
            counted = true
        }
    }
}

/// A whole number counting up from zero.
private struct CountUp: View {
    let target: Double
    let duration: Double
    let delay: Double
    @State private var value = 0.0

    var body: some View {
        CountingText(value: value) { $0.formattedAsDigits() }
            .task {
                try? await Task.sleep(for: .seconds(delay))
                withAnimation(.timingCurve(0.33, 1, 0.68, 1, duration: duration)) { value = target }
            }
    }
}

private extension View {
    /// Springs in from small, with a little overshoot (design "pop").
    func popIn(duration: Double, delay: Double) -> some View { modifier(PopIn(duration: duration, delay: delay)) }
    /// Floats up and down slowly, starting after `delay`.
    func drifting(delay: Double) -> some View { modifier(Drift(delay: delay)) }
    func twinkling(delay: Double) -> some View { modifier(Twinkle(delay: delay)) }
}

private struct PopIn: ViewModifier {
    let duration: Double
    let delay: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown ? 1 : 0.3)
            .opacity(shown ? 1 : 0)
            .animation(.timingCurve(0.3, 1.6, 0.5, 1, duration: duration).delay(delay), value: shown)
            .onAppear { shown = true }
    }
}

private struct Drift: ViewModifier {
    let delay: Double
    @State private var start = Date.distantFuture

    func body(content: Content) -> some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(start)
            content.offset(y: t > 0 ? -6 * (0.5 - 0.5 * cos(t * 2 * .pi / 4)) : 0)
        }
        .onAppear { start = Date().addingTimeInterval(delay) }
    }
}

private struct Twinkle: ViewModifier {
    let delay: Double
    @State private var start = Date.distantFuture

    func body(content: Content) -> some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(start)
            let phase = t > 0 ? 0.5 - 0.5 * cos(t * 2 * .pi / 2.4) : 0
            content.opacity(0.2 + 0.8 * phase).scaleEffect(0.6 + 0.5 * phase)
        }
        .onAppear { start = Date().addingTimeInterval(delay) }
    }
}
