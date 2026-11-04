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
