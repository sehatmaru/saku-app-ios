import Foundation
import UserNotifications

/// Tells the user there are new drafts (local notification and app badge).
enum DraftNotifier {
    /// userInfo value that makes a tap open Perlu dicek.
    static let route = "drafts"

    static func announce(count: Int) async {
        guard count > 0 else { return }
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .badge])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = L("Perlu dicek")
        content.body = L("%lld draf transaksi menunggu dicek di Saku.", count)
        content.userInfo = ["route": route]
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: "draft-\(UUID().uuidString)", content: content,
                                                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
    }
}
