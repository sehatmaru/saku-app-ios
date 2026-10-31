import SwiftUI

/// Confirm dialog on the shared sheet frame (`SmartSheet`): title, a large badge, the message, then Batal and the action
/// on one row. A normal sheet (half height, drag to full, buttons pinned), not the system alert. While `isBusy` the primary button shows a spinner and the sheet cannot be dismissed or tapped. The caller
/// closes it (`isPresented = false`). Attach it inside a sheet's own content when the dialog belongs to the sheet.
private struct ConfirmDialogModifier: ViewModifier {
    @Binding var isPresented: Bool
    let icon: String
    let destructive: Bool
    let inkButton: Bool
    let title: String
    let message: String
    let confirmTitle: String?
    let cancelTitle: String
    let isBusy: Bool
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            SmartSheet(tone: destructive ? .destructive : .neutral, icon: icon, title: title, message: message) {
                SmartSheetFooter(primary: confirmTitle, destructive: destructive, ink: inkButton, isBusy: isBusy, secondary: cancelTitle,
                                 onPrimary: onConfirm) { isPresented = false }
            }
            .interactiveDismissDisabled(isBusy)
        }
    }
}

extension View {
    /// `confirmTitle` nil makes it an info dialog with only the cancel button (use "Tutup").
    func confirmDialog(isPresented: Binding<Bool>, icon: String, destructive: Bool = false, inkButton: Bool = false, title: String,
                       message: String, confirmTitle: String?, cancelTitle: String = L("Batal"),
                       isBusy: Bool = false, onConfirm: @escaping () -> Void = {}) -> some View {
        modifier(ConfirmDialogModifier(isPresented: isPresented, icon: icon, destructive: destructive, inkButton: inkButton, title: title,
                                       message: message, confirmTitle: confirmTitle, cancelTitle: cancelTitle,
                                       isBusy: isBusy, onConfirm: onConfirm))
    }
}
