import SwiftUI

struct ErrorStateView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "wifi.slash")
                .font(.system(size: 34))
                .foregroundStyle(Color.appError)
                .frame(width: 72, height: 72)
                .background(Color.appError.opacity(0.12), in: Circle())

            Text("Gagal memuat data")
                .font(.app(20, weight: .semibold))
                .foregroundStyle(Color.appText)

            Text(message)
                .font(.app(15))
                .foregroundStyle(Color.appTextSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 32)

            NoticeButton(title: L("Coba lagi"), icon: "arrow.clockwise", action: onRetry)
                .padding(.top, 8)

            Spacer()
        }
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.icloud.fill")
                .font(.app(12))
                .foregroundColor(.appWarning)

            Text(message)
                .font(.app(12))
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
