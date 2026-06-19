import SwiftUI

struct SplashView: View {
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0

    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Image(systemName: "leaf.fill")
                .font(.system(size: 60))
                .foregroundColor(.appPrimary)

            Text("SakuQ")
                .font(.largeTitle.weight(.bold))
                .foregroundColor(.appPrimary)

            Text("Personal Finance")
                .font(.subheadline)
                .foregroundColor(.appTextSecondary)

            Spacer()

            Text("v1.0")
                .font(.caption)
                .foregroundColor(.appTextSecondary)
                .padding(.bottom, Spacing.xxl)
        }
        .scaleEffect(scale)
        .opacity(opacity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
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
