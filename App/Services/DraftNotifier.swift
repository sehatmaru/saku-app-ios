import Foundation
import UserNotifications

/// Tells the user there are new drafts (local notification and app badge).
enum DraftNotifier {
    /// userInfo value that makes a tap open Konfirmasi transaksi.
    static let route = "drafts"

    /// "Pemasukan - Rp25.000 tercatat!" for one draft, "3 transaksi tercatat!" for several. The body says it is still a draft.
    static func announce(_ drafts: [Draft]) async {
        guard let first = drafts.first else { return }
        let title: String
        if drafts.count == 1, let amount = first.amount {
            let kind: String
            switch first.kind {
            case .expense: kind = L("Pengeluaran")
            case .income: kind = L("Pemasukan")
            case .transfer: kind = L("Transfer")
            case .cardPayment: kind = L("Bayar kartu")
            }
            title = L("%@ - %@ tercatat!", kind, amount.formattedAsCurrency())
        } else {
            title = L("%lld transaksi tercatat!", drafts.count)
        }
        await post(title: title, body: L("Masih draf. Ketuk untuk memeriksa dan menyimpan."), route: route)
    }

    /// Why an automation could not read anything. A Shortcuts automation runs in the background and its dialog is never shown.
    static func explain(title: String, body: String) async { await post(title: title, body: body, route: nil) }

    private static func post(title: String, body: String, route: String?) async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .badge])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let route { content.userInfo = ["route": route] }
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: "draft-\(UUID().uuidString)", content: content,
                                                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
    }
}
