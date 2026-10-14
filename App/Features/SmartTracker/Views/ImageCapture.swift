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
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "doc.viewfinder").font(.system(size: 24)).foregroundStyle(Color.stGreen)
                .frame(width: 48, height: 48).background(Color.stGreen.opacity(0.14), in: Circle()).padding(.top, 14)
            Text("Catat dari gambar").font(.app(24, weight: .bold)).padding(.top, 16)
            Text("Foto bukti bayar, struk, atau screenshot mutasi. Saku mengubahnya jadi draf transaksi.")
                .font(.app(15)).lineSpacing(3).foregroundStyle(Color.appTextSecondary).padding(.top, 6)
            VStack(alignment: .leading, spacing: 16) {
                point("iphone", "Dibaca di HP-mu", "Gambar tidak disimpan dan tidak dikirim ke mana pun.")
                point("textformat", "Hanya teksnya yang diproses", "Dihapus setelah draf disimpan atau dibuang, paling lama 30 hari.")
                point("eye.slash", "Saldo dan nomor rekening diabaikan", "Yang dicatat cuma transaksinya.")
            }
            .padding(.top, 22)
            Spacer(minLength: 16)
            PrimaryButton(title: L("Setuju")) {
                ShareInbox.isImageAgreed = true
                dismiss()
                onAgree()
            }
            Button("Nanti saja") { dismiss() }.font(.app(16, weight: .medium)).foregroundStyle(Color.appTextSecondary)
                .frame(maxWidth: .infinity).frame(height: 44).padding(.top, 6)
        }
        .padding(.horizontal, 24).padding(.bottom, 12)
        .presentationDetents([.height(560)])
        .presentationDragIndicator(.visible)
    }

    private func point(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.system(size: 19)).foregroundStyle(Color.appTextSecondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(L(title)).font(.app(15, weight: .semibold))
                Text(L(detail)).font(.app(14)).lineSpacing(2).foregroundStyle(Color.appTextSecondary)
            }
        }
    }
}
