import SwiftUI

struct SplashView: View {
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0

    let onComplete: () -> Void

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: Spacing.lg) {
                Spacer()

                SakuQLogoIcon()
                    .frame(width: 80, height: 80)

                Text("SakuQ")
                    .font(.app(34, weight: .bold))
                    .foregroundColor(.appPrimary)

                Spacer()
            }
            .scaleEffect(scale)
            .opacity(opacity)

            VStack {
                Spacer()
                Text("v1.0")
                    .font(.app(12))
                    .foregroundColor(.appTextSecondary)
                    .padding(.bottom, Spacing.xxl)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                scale = 1.0
                opacity = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                onComplete()
            }
        }
    }
}
