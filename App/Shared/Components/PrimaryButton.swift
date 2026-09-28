import SwiftUI

/// 52pt green pill; turns grey when disabled.
struct PrimaryButton: View {
    let title: String
    var isLoading = false
    var isEnabled = true
    var trailingIcon: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                }
                Text(title)
                    .contentTransition(.numericText())
                if let trailingIcon {
                    Image(systemName: trailingIcon)
                        .font(.system(size: 15, weight: .bold))
                }
            }
            .font(.app(17, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(isEnabled ? Color.appPrimary : Color.appTextTertiary, in: Capsule())
            .foregroundStyle(.white)
            .animation(.easeInOut(duration: 0.24), value: isEnabled)
        }
        .buttonStyle(.plain)
        .disabled(isLoading || !isEnabled)
    }
}
