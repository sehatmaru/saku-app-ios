import UIKit
import UniformTypeIdentifiers

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
        extensionContext?.completeRequest(returningItems: nil)
    }
}
