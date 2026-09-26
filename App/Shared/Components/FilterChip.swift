import SwiftUI

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.app(14, weight: isSelected ? .medium : .regular))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .foregroundStyle(isSelected ? Color.appBackground : Color.appText)
                .background(isSelected ? Color.appText : Color.clear, in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Color.appBorder))
        }
        .buttonStyle(.plain)
    }
}
