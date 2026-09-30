import SwiftUI
import UserNotifications

/// Handles taps on the overdue-bill notification: "Belum" snoozes it until tomorrow morning,
/// "Sudah, catat" (or the notification itself) asks Beranda to open Catat tagihan for that card.
@MainActor
final class NotificationRouter: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    /// The card whose bill the user wants to record; Beranda clears it once the sheet is open.
    @Published var pendingCardId: String?

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        guard content.categoryIdentifier == NotificationManager.lateCategory,
              let cardId = content.userInfo["cardId"] as? String else { return }
        let statementTime = content.userInfo["statementDate"] as? Double ?? 0
        let action = response.actionIdentifier
        let title = content.title
        let body = content.body

        if action == NotificationManager.notYetAction {
            await NotificationManager.shared.snoozeLateReminder(
                cardId: cardId, statementDate: Date(timeIntervalSince1970: statementTime), title: title, body: body)
        } else {
            await MainActor.run { NotificationRouter.shared.pendingCardId = cardId }
        }
    }
}

/// Installs the notification delegate before the first notification can arrive.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        NotificationManager.shared.registerCategories()
        return true
    }
}
