import UIKit
import UniformTypeIdentifiers
import UserNotifications

/// "Bagikan ke Saku": takes the shared text and drops it in the inbox for the app to turn into drafts.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let label = UILabel()
        label.text = "Mengirim ke Saku…"
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .headline)
        label.frame = view.bounds
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(label)
        Task { await receive() }
    }

    /// Tells the user right away; tapping it opens Saku on Konfirmasi transaksi. Works once the app has notification permission.
    private func announce(_ body: String = "Teksnya masuk ke Konfirmasi transaksi. Ketuk untuk memeriksa drafnya.") async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Dikirim ke Saku"
        content.body = body
        content.sound = .default
        content.userInfo = ["route": "drafts"]
        try? await center.add(UNNotificationRequest(identifier: "share-\(UUID().uuidString)", content: content,
                                                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
    }

    private func receive() async {
        guard ShareInbox.isEnabled else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        var received = Set<String>()
        func take(_ text: String) {
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            // WhatsApp and others hand over the same text as an attachment and as contentText
            if !text.isEmpty, received.insert(text).inserted { ShareInbox.append(text) }
        }
        var imagesRefused = false
        for provider in items.flatMap({ $0.attachments ?? [] }) {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                // the short agreement for pictures is given in the app; until then nothing is read
                guard ShareInbox.isImageAgreed else { imagesRefused = true; continue }
                if let data = await imageData(from: provider), let image = ImageReader.downscaled(data) {
                    let lines = await ImageReader.lines(in: image)
                    if !lines.isEmpty { ShareInbox.append(ShareInbox.photoMark + lines.joined(separator: "\n")) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                take(text)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                      let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                take(url.absoluteString)
            }
        }
        for item in items {
            if let text = item.attributedContentText?.string { take(text) }
        }
        await announce(imagesRefused ? "Buka Saku dan setujui membaca gambar dulu, lalu bagikan lagi." : "Teksnya masuk ke Konfirmasi transaksi. Ketuk untuk memeriksa drafnya.")
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func imageData(from provider: NSItemProvider) async -> Data? {
        let item = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier)
        if let url = item as? URL { return try? Data(contentsOf: url) }
        if let data = item as? Data { return data }
        if let image = item as? UIImage { return image.jpegData(compressionQuality: 0.9) }
        return nil
    }
}
