import SwiftUI

struct ToastModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    let icon: String
    let duration: Double

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if isPresented {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: icon)
                            .font(.app(14))
                            .foregroundColor(.appPrimary)
                        Text(message)
                            .font(.app(14, weight: .medium))
                            .foregroundColor(.appText)
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.regularMaterial)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                    .padding(.bottom, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                            withAnimation { isPresented = false }
                        }
                    }
                }
            }
    }
}

extension View {
    func toast(isPresented: Binding<Bool>, message: String, icon: String = "checkmark.circle.fill", duration: Double = 1.5) -> some View {
        modifier(ToastModifier(isPresented: isPresented, message: message, icon: icon, duration: duration))
    }
}
