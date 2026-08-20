import Foundation
import UserNotifications

final class NotificationManager: @unchecked Sendable {
    static let shared = NotificationManager()
    private init() {}

    func requestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    private func identifier(for sub: CardSubscription) -> String {
        "subscription-\(sub.id)"
    }

    func schedule(for sub: CardSubscription) async {
        guard sub.isActive, let billingDate = sub.nextBillingDateAsDate else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let calendar = Calendar.current
        guard let reminderDate = calendar.date(byAdding: .day, value: -1, to: billingDate) else { return }
        var components = calendar.dateComponents([.year, .month, .day], from: reminderDate)
        components.hour = 9
        components.minute = 0

        let content = UNMutableNotificationContent()
        content.title = "Tagihan: \(sub.name)"
        content.body = "Tagihan \(sub.name) sebesar \(sub.amount.formattedAsCurrency()) jatuh tempo besok."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier(for: sub), content: content, trigger: trigger)
        try? await center.add(request)
    }

    func cancel(for sub: CardSubscription) async {
        await UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier(for: sub)])
    }

    func resyncAll(subscriptions: [CardSubscription]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let activeIds = Set(subscriptions.map { identifier(for: $0) })
        let toRemove = pending
            .map { $0.identifier }
            .filter { $0.hasPrefix("subscription-") && !activeIds.contains($0) }
        if !toRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: toRemove)
        }
        for sub in subscriptions {
            await schedule(for: sub)
        }
    }
}
