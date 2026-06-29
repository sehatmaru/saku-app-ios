import SwiftUI

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.jakarta(14))
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .background(isSelected ? Color.appPrimary.opacity(0.12) : Color(.systemGray6))
                .foregroundColor(isSelected ? Color.appPrimary : .appText)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
