import SwiftUI

/// Pocket pops in, three cards rise and fan out, the wordmark lifts, then the
/// segment bar fills as a ~2.5 s loader before `onComplete`.
struct SplashView: View {
    let onComplete: () -> Void
    @State private var stage = 0

    var body: some View {
        ZStack(alignment: .top) {
            Color.appBrand.ignoresSafeArea()

            VStack(spacing: 34) {
                PocketLogo(isOpen: stage >= 2)
                    .frame(width: 180, height: 180)
                    .opacity(stage >= 1 ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: stage >= 1)
                    .scaleEffect(stage >= 1 ? 1 : 0.6)
                    .animation(.timingCurve(0.3, 1.4, 0.5, 1, duration: 0.7), value: stage >= 1)

                VStack(spacing: 10) {
                    Text("Saku")
                        .font(.wordmark(40))
                        .tracking(-1.4)
                    Text("Semua dompet, satu kantong.")
                        .font(.app(15))
                        .opacity(0.82)
                }
                .foregroundStyle(.white)
                .rise(stage >= 3, y: 14)
            }
            .padding(.top, 196)
        }
        .overlay(alignment: .bottom) {
            SegmentTrack(count: 20, filled: stage >= 4 ? 20 : 0, color: .white, track: .white.opacity(0.25),
                         gap: 3, step: 0.04, duration: 0.16)
                .frame(width: 140, height: 6)
                .opacity(stage >= 3 ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: stage >= 3)
                .padding(.bottom, 62)
        }
        .task {
            let start = ContinuousClock.now
            for (s, t) in [(1, 0.15), (2, 0.65), (3, 1.25), (4, 1.6)] {
                try? await Task.sleep(until: start + .seconds(t), clock: .continuous)
                stage = s
            }
            try? await Task.sleep(until: start + .seconds(2.6), clock: .continuous)
            onComplete()
        }
    }
}
