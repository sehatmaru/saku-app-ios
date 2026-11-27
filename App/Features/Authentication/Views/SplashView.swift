import SwiftUI

/// ~1 s: the pocket pops in, three cards spring out and fan, the pocket breathes, three coins
/// pop above it, then the wordmark slides out from the pocket's right. The rising cards are the
/// loading cue; `onComplete` only says the animation is over, the session check runs alongside.
struct SplashView: View {
    let onComplete: () -> Void
    @State private var pocketIn = false
    @State private var cardsOut = false
    @State private var breath = false
    @State private var coinPhase = 0
    @State private var wordIn = false

    private let logoSize: CGFloat = 120
    /// Coin end points on the logo's 180pt grid (design "Splash Saku", variant D).
    private let coinEnds: [(x: CGFloat, y: CGFloat)] = [(-70, -48), (-40, -72), (0, -84)]
    private let coinColors: [Color] = [Color(hex: "F3D48A"), Color(hex: "D9A93A"), .white]

    var body: some View {
        ZStack {
            Color.appBrand.ignoresSafeArea()

            HStack(spacing: 12) {
                logo
                Text("Saku")
                    .font(.wordmark(40))
                    .tracking(-1.4)
                    .foregroundStyle(.white)
                    .opacity(wordIn ? 1 : 0)
                    .offset(x: wordIn ? 0 : -28)
                    .animation(.settle(0.48), value: wordIn)
            }
            .offset(y: -40)
        }
        .task {
            let start = ContinuousClock.now
            let steps: [(ms: Int, run: @MainActor () -> Void)] = [
                (0, { pocketIn = true }),
                (100, { cardsOut = true }),
                (240, { breath = true }),
                (300, { coinPhase = 1 }),
                (390, { breath = false }),
                (461, { coinPhase = 2 }),
                (520, { wordIn = true }),
            ]
            for step in steps {
                try? await Task.sleep(until: start + .milliseconds(step.ms), clock: .continuous)
                step.run()
            }
            try? await Task.sleep(until: start + .milliseconds(1000), clock: .continuous)
            onComplete()
        }
    }

    private var logo: some View {
        let s = logoSize / 180
        return ZStack {
            PocketLogo(isOpen: cardsOut, stagger: 0.05, duration: 0.5,
                       motion: { .timingCurve(0.34, 1.45, 0.5, 1, duration: $0) })
                .frame(width: logoSize, height: logoSize)
                .scaleEffect(breath ? 1.04 : 1)
                .animation(.timingCurve(0.45, 0, 0.25, 1, duration: 0.15), value: breath)
                .scaleEffect(pocketIn ? 1 : 0.9)
                .offset(y: pocketIn ? 0 : 24 * s)
                .opacity(pocketIn ? 1 : 0)
                .animation(.settle(0.34), value: pocketIn)

            ForEach(coinEnds.indices, id: \.self) { i in
                let k: CGFloat = [0, 0.7, 1][coinPhase]
                Circle()
                    .fill(coinColors[i])
                    .frame(width: 8 * s, height: 8 * s)
                    // The coin starts at the pocket's opening, (90, 56) on the 180pt grid.
                    .offset(x: coinEnds[i].x * k * s, y: (-34 + coinEnds[i].y * k) * s)
                    .scaleEffect([0.4, 1, 0.5][coinPhase])
                    .opacity(coinPhase == 1 ? 1 : 0)
                    .animation(.settle(coinPhase == 1 ? 0.16 : 0.3), value: coinPhase)
            }
        }
        .frame(width: logoSize, height: logoSize)
    }
}
