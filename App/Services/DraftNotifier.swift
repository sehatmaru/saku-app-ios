import Foundation
import UserNotifications

/// Tells the user there are new drafts (local notification and app badge).
enum DraftNotifier {
    /// userInfo value that makes a tap open Konfirmasi transaksi.
    static let route = "drafts"

    /// "Uang masuk, cek sekarang!" with "BCA sebesar Rp25.000"; several drafts say how many. Still a draft, so the tap opens the queue.
    @MainActor static func announce(_ drafts: [Draft]) async {
        guard let first = drafts.first else { return }
        guard drafts.count == 1, let amount = first.amount else {
            await post(title: L("%lld draf baru, cek sekarang!", drafts.count), body: L("Ketuk untuk memeriksa dan menyimpan."), route: route)
            return
        }
        let title: String
        switch first.kind {
        case .expense: title = L("Uang keluar, cek sekarang!")
        case .income: title = L("Uang masuk, cek sekarang!")
        case .transfer: title = L("Uang pindah, cek sekarang!")
        case .cardPayment: title = L("Bayar kartu, cek sekarang!")
        }
        let wallet = DraftStore.shared.accounts.first { $0.id == first.accountId }?.name ?? first.sourceName
        let body = wallet.map { L("%@ sebesar %@", $0, amount.formattedAsCurrency()) } ?? amount.formattedAsCurrency()
        await post(title: title, body: body, route: route)
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
