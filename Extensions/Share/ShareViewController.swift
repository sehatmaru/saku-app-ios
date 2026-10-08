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

    /// Tells the user right away; tapping it opens Saku on Perlu dicek. Works once the app has notification permission.
    private func announce() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Dikirim ke Saku"
        content.body = "Teksnya masuk ke Perlu dicek. Ketuk untuk memeriksa drafnya."
        content.sound = .default
        content.userInfo = ["route": "drafts"]
        try? await center.add(UNNotificationRequest(identifier: "share-\(UUID().uuidString)", content: content,
                                                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
    }

    private func receive() async {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        for provider in items.flatMap({ $0.attachments ?? [] }) {
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                ShareInbox.append(text)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                      let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                ShareInbox.append(url.absoluteString)
            }
        }
        for item in items {
            if let text = item.attributedContentText?.string, !text.isEmpty { ShareInbox.append(text) }
        }
        await announce()
        extensionContext?.completeRequest(returningItems: nil)
    }
}
