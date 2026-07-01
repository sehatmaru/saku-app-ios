import SwiftUI

struct ErrorStateView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Image(systemName: "wifi.slash")
                .font(.system(size: 48))
                .foregroundColor(.appTextSecondary)

            Text("Gagal memuat data")
                .font(.jakarta(17, weight: .semibold))
                .foregroundColor(.appText)

            Text(message)
                .font(.jakarta(13))
                .foregroundColor(.appTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xxl)

            Button {
                onRetry()
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "arrow.clockwise")
                        .font(.jakarta(14, weight: .semibold))
                    Text("Coba Lagi")
                        .font(.jakarta(14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.appPrimary)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, Spacing.xxl)

            Spacer()
        }
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.icloud.fill")
                .font(.jakarta(12))
                .foregroundColor(.appWarning)

            Text(message)
                .font(.jakarta(12))
                .foregroundColor(.appTextSecondary)
                .lineLimit(2)

            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.appWarning.opacity(0.1))
    }
}
