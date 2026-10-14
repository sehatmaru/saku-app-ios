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

/// The short agreement shown once, the first time pictures are used (K13).
struct ImageConsentSheet: View {
    let onAgree: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "photo.badge.checkmark").font(.system(size: 30)).foregroundStyle(Color.stGreen)
            Text("Catat dari gambar").font(.app(22, weight: .semibold))
            Text("Saku membaca tulisan di gambar langsung di HP-mu. Gambarnya tidak disimpan dan tidak dikirim ke mana pun; hanya teks hasil bacaan yang diproses, lalu dihapus setelah drafnya disimpan atau dibuang (paling lama 30 hari). Saldo dan nomor rekening diabaikan.")
                .font(.app(15)).lineSpacing(3).foregroundStyle(Color.appBody)
            Spacer(minLength: 0)
            PrimaryButton(title: L("Setuju")) {
                ShareInbox.isImageAgreed = true
                dismiss()
                onAgree()
            }
            Button("Nanti saja") { dismiss() }.font(.app(16, weight: .medium)).frame(maxWidth: .infinity)
        }
        .padding(24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
