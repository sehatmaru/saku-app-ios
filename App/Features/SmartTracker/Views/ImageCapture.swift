import AVFoundation
import SwiftUI
import UIKit

/// The camera, for "Foto" in Catat cepat. The photo goes straight to reading and is never saved.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isUsable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    /// False when the user turned the camera off for Saku (or this device has none).
    static var isAllowed: Bool {
        isUsable && ![.denied, .restricted].contains(AVCaptureDevice.authorizationStatus(for: .video))
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let data = (info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.9)
            parent.dismiss()
            if let data { parent.onImage(data) }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

/// The short agreement shown once, the first time pictures are used (K13). When Smart Tracker is
/// not on yet, this same sheet turns it on ("Setuju dan aktifkan", design "Catat dari Gambar").
struct ImageConsentSheet: View {
    var profileId: UUID?
    let onAgree: () -> Void
    /// "Lihat detail": opens the full Smart Tracker agreement.
    var onDetails: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    /// Menu uji: nothing is saved, and `previewNeedsTracker` forces either version of the sheet.
    var isPreview = false
    var previewNeedsTracker: Bool?

    private var needsTracker: Bool { previewNeedsTracker ?? !SmartTrackerConsent.isGranted }

    var body: some View {
        SmartSheet(tone: .consent, icon: "viewfinder", title: L("Catat dari gambar"),
                   message: L("Foto bukti bayar, struk, atau screenshot mutasi. Saku mengubahnya jadi draf transaksi."),
                   promises: [SmartPromise(icon: "iphone", title: L("Dibaca di HP-mu"), detail: L("Gambar tidak disimpan dan tidak dikirim ke mana pun.")),
                              SmartPromise(icon: "textformat", title: L("Hanya teksnya yang diproses"), detail: L("Dihapus setelah draf disimpan atau dibuang, paling lama 30 hari.")),
                              SmartPromise(icon: "eye.slash", title: L("Saldo dan nomor rekening diabaikan"), detail: L("Yang dicatat cuma transaksinya."))],
                   extra: { if needsTracker { trackerNote } }) {
            SmartSheetFooter(primary: L(needsTracker ? "Setuju dan aktifkan" : "Setuju"), secondary: L("Nanti saja"),
                             onPrimary: agree) { dismiss() }
        }
    }

    /// Smart Tracker is off: agreeing here switches it on too. The whole block opens the full agreement.
    private var trackerNote: some View {
        Button { onDetails?() } label: {
            HStack(spacing: 8) {
                (Text(L("Smart Tracker belum aktif. Dengan setuju, kamu juga mengaktifkan Smart Tracker."))
                    + Text(" ") + Text(L("Lihat detail")).foregroundStyle(Color.stGreen).fontWeight(.semibold).underline())
                    .font(.app(14)).lineSpacing(2).foregroundStyle(Color.appText)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.stGreen)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color.stSuccessBg, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
    }

    /// Agreeing also switches Smart Tracker on when it was off; saved on the profile so it follows
    /// the account to every device, like the full agreement does.
    private func agree() {
        if isPreview { dismiss(); return }
        if needsTracker {
            SmartTrackerConsent.isGranted = true
            SmartTrackerConsent.since = Date()
            if let profileId {
                Task {
                    try? await SupabaseSDK.recordSmartTrackerConsent(profileId: profileId)
                    // the agreement above also covers Ingatan on the server; guests stay on the device
                    if !DraftStore.shared.isGuest {
                        try? await SupabaseSDK.recordMemorySyncConsent(profileId: profileId)
                        await DraftStore.shared.syncMemory()
                    }
                }
            }
        }
        ShareInbox.isImageAgreed = true
        dismiss()
        onAgree()
    }
}
