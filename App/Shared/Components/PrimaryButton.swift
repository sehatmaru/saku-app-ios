import SwiftUI

struct PrimaryButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                }
                Text(title)
                    .font(.jakarta(17, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isLoading ? Color.appSecondary : Color.appPrimary)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}
