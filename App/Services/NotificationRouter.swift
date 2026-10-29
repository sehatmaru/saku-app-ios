import SwiftUI
import UserNotifications

/// Handles taps on the overdue-bill notification: "Belum" snoozes it until tomorrow morning,
/// "Sudah, catat" (or the notification itself) asks Beranda to open Catat tagihan for that card.
@MainActor
final class NotificationRouter: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    /// The card whose bill the user wants to record; Beranda clears it once the sheet is open.
    @Published var pendingCardId: String?
    /// Set when the user taps the "new drafts" notification; Beranda opens Konfirmasi transaksi and clears it.
    @Published var opensDrafts = false
    /// Set when the user taps "setujui baca gambar" from the share extension; Beranda opens the agreement sheet and clears it.
    @Published var opensImageConsent = false
    /// The investment wallet whose "Perbarui nilai" the user was reminded of; Dompet opens it and clears this.
    @Published var pendingInvestmentId: String?

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Uses the completion-handler form and calls it on the main thread on purpose: when the `async` form
    /// finished on a background thread, UIKit's snapshot step after the tap asserted "main thread" and the
    /// app aborted (every notification tap crashed, visible in the device crash logs).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let content = response.notification.request.content
        let route = content.userInfo["route"] as? String
        let category = content.categoryIdentifier
        let cardId = content.userInfo["cardId"] as? String
        let investmentId = content.userInfo["accountId"] as? String
        let statementTime = content.userInfo["statementDate"] as? Double ?? 0
        let action = response.actionIdentifier
        let title = content.title
        let body = content.body
        nonisolated(unsafe) let finish = completionHandler

        Task { @MainActor in
            defer { finish() }
            if route == "imageConsent" {
                NotificationRouter.shared.opensImageConsent = true
                return
            }
            if route == DraftNotifier.route {
                NotificationRouter.shared.opensDrafts = true
                return
            }
            if route == NotificationManager.investmentRoute, let investmentId {
                NotificationRouter.shared.pendingInvestmentId = investmentId
                return
            }
            guard category == NotificationManager.lateCategory, let cardId else { return }
            if action == NotificationManager.notYetAction {
                await NotificationManager.shared.snoozeLateReminder(
                    cardId: cardId, statementDate: Date(timeIntervalSince1970: statementTime), title: title, body: body)
            } else {
                NotificationRouter.shared.pendingCardId = cardId
            }
        }
    }
}

/// Installs the notification delegate before the first notification can arrive.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        NotificationManager.shared.registerCategories()
        _ = UIViewController.sakuWatchesPops
        return true
    }
}
