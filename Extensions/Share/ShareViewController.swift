import UIKit
import UniformTypeIdentifiers
import UserNotifications

/// "Bagikan ke Saku": takes the shared text and drops it in the inbox for the app to turn into drafts.
final class ShareViewController: UIViewController {
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        label.text = "Mengirim ke Saku…"
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .headline)
        label.frame = view.bounds.insetBy(dx: 24, dy: 0)
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(label)
        Task { await receive() }
    }

    /// Tells the user right away; tapping it opens Saku on Konfirmasi transaksi. Works once the app has notification permission.
    private func announce(title: String, body: String, route: String?) async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let route { content.userInfo = ["route": route] }
        try? await center.add(UNNotificationRequest(identifier: "share-\(UUID().uuidString)", content: content,
                                                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
    }

    private func receive() async {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        var received = Set<String>()
        var added = 0
        func take(_ text: String) {
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            // WhatsApp and others hand over the same text as an attachment and as contentText
            if !text.isEmpty, received.insert(text).inserted { ShareInbox.append(text); added += 1 }
        }
        var imagesSeen = 0
        var needsPlus = false
        for provider in items.flatMap({ $0.attachments ?? [] }) {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                // reading pictures is a Saku Plus feature, like Catat dari gambar in the app
                guard ShareInbox.isPlus else { needsPlus = true; continue }
                imagesSeen += 1
                if let data = await imageData(from: provider), let image = ImageReader.downscaled(data) {
                    let lines = await ImageReader.lines(in: image)
                    if !lines.isEmpty { ShareInbox.append(ShareInbox.photoMark + lines.joined(separator: "\n")); added += 1 }
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
        // say what happened on screen too: the notification only shows when the app has permission
        let message: String
        if needsPlus && added == 0 { message = "Membaca gambar butuh Saku Plus. Teks tetap bisa dibagikan ke Saku." }
        else if imagesSeen > 0 && added == 0 { message = "Tidak ada tulisan yang terbaca di gambarnya, jadi belum ada yang masuk ke Konfirmasi transaksi." }
        else if added == 0 { message = "Tidak ada yang bisa dikirim ke Saku." }
        else { message = "Masuk ke Konfirmasi transaksi. Ketuk untuk memeriksa drafnya." }
        label.text = message
        // only what the owner can act on gets a notification; an empty picture or nothing to send stays on the sheet
        if added > 0 {
            await announce(title: "Terkirim ke Saku, cek sekarang!", body: "Ketuk untuk membaca dan memeriksa drafnya.", route: "drafts")
        } else if needsPlus {
            await announce(title: "Baca gambar butuh Saku Plus", body: "Teks tetap bisa dibagikan ke Saku.", route: nil)
        }
        if added == 0 { try? await Task.sleep(for: .seconds(3)) }
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
