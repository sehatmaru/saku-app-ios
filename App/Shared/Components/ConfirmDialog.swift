import SwiftUI

/// Bottom confirm dialog in the style of "Hapus dompet ini?": badge, title, message, a filled
/// primary button and Batal. Not the system alert. While `isBusy` the primary button shows a
/// spinner and nothing can be dismissed or tapped. The caller closes it (`isPresented = false`).
/// Attach it inside a sheet's own content when the dialog belongs to the sheet.
private struct ConfirmDialogModifier: ViewModifier {
    @Binding var isPresented: Bool
    let icon: String
    let destructive: Bool
    let title: String
    let message: String
    let confirmTitle: String?
    let cancelTitle: String
    let isBusy: Bool
    let onConfirm: () -> Void

    private static let background = Color(light: 0xFFFFFF, dark: 0x1C1C1E)

    func body(content: Content) -> some View {
        content.overlay {
            ZStack(alignment: .bottom) {
                Color.black.opacity(isPresented ? 0.3 : 0)
                    .ignoresSafeArea()
                    .onTapGesture { if !isBusy { isPresented = false } }
                    .allowsHitTesting(isPresented)

                VStack(spacing: 6) {
                    Circle()
                        .fill(destructive ? Color(light: 0xFDECEC, dark: 0x3A1D1F) : Color.appFill)
                        .frame(width: 52, height: 52)
                        .overlay {
                            Image(systemName: icon)
                                .font(.system(size: 22))
                                .foregroundStyle(destructive ? Color(light: 0xD1343A, dark: 0xFF6B6B) : Color.appText)
                        }
                    Text(title)
                        .font(.app(17, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                    Text(message)
                        .font(.app(15))
                        .foregroundStyle(Color.appTextSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 8) {
                        if let confirmTitle {
                            Button(action: onConfirm) {
                                ZStack {
                                    Text(confirmTitle).opacity(isBusy ? 0 : 1)
                                    if isBusy { ProgressView().tint(destructive ? .white : Color.appBackground) }
                                }
                                .font(.app(16, weight: .semibold))
                                .foregroundStyle(destructive ? Color.white : Color.appBackground)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(destructive ? Color(hex: "D93636") : Color.appText, in: Capsule())
                            }
                        }
                        Button { isPresented = false } label: {
                            Text(cancelTitle)
                                .font(.app(16, weight: .medium))
                                .foregroundStyle(Color.appText)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color(light: 0xF2F2F4, dark: 0x2C2C2E), in: Capsule())
                        }
                    }
                    .buttonStyle(PressScaleStyle())
                    .disabled(isBusy)
                    .padding(.top, 14)
                }
                .foregroundStyle(Color.appText)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 20)
                .background(Self.background, in: UnevenRoundedRectangle(topLeadingRadius: 28, bottomLeadingRadius: 38, bottomTrailingRadius: 38, topTrailingRadius: 28))
                .padding(.horizontal, 8)
                .offset(y: isPresented ? 0 : 760)
            }
            .animation(.settle(0.44), value: isPresented)
        }
    }
}

extension View {
    /// `confirmTitle` nil makes it an info dialog with only the cancel button (use "Tutup").
    func confirmDialog(isPresented: Binding<Bool>, icon: String, destructive: Bool = false, title: String,
                       message: String, confirmTitle: String?, cancelTitle: String = L("Batal"),
                       isBusy: Bool = false, onConfirm: @escaping () -> Void = {}) -> some View {
        modifier(ConfirmDialogModifier(isPresented: isPresented, icon: icon, destructive: destructive, title: title,
                                       message: message, confirmTitle: confirmTitle, cancelTitle: cancelTitle,
                                       isBusy: isBusy, onConfirm: onConfirm))
    }
}
