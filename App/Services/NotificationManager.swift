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

    /// Three days before a renewal, so there's still time to cancel it.
    func schedule(for sub: CardSubscription) async {
        guard sub.isActive, let billingDate = sub.nextBillingDateAsDate else { return }
        let body = "\(sub.name) diperpanjang 3 hari lagi sebesar \(sub.amount.formattedAsCurrency()). Batalkan sebelum itu kalau sudah tidak dipakai."
        await add(id: identifier(for: sub), title: "Langganan: \(sub.name)", body: body, daysBefore: 3, date: billingDate)
    }

    /// Card bills still owed: a reminder three days and one day before the due date.
    func resyncCardDue(cards: [Account], statements: [CreditStatement]) async {
        let center = UNUserNotificationCenter.current()
        let stale = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("card-due-") }
        center.removePendingNotificationRequests(withIdentifiers: stale)
        for (card, statement) in zip(cards, statements) where statement.remaining >= 1 {
            let amount = statement.remaining.formattedAsCurrency()
            await add(id: "card-due-\(card.id)-3", title: "Tagihan \(card.name)",
                      body: "Tagihan \(amount) jatuh tempo 3 hari lagi.", daysBefore: 3, date: statement.dueDate)
            await add(id: "card-due-\(card.id)-1", title: "Tagihan \(card.name)",
                      body: "Tagihan \(amount) jatuh tempo besok. Bayar penuh supaya tidak kena bunga.", daysBefore: 1, date: statement.dueDate)
        }
    }

    /// A one-off reminder at 09:00, `daysBefore` days before `date`; skipped once that's past.
    private func add(id: String, title: String, body: String, daysBefore: Int, date: Date) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let calendar = Calendar.current
        guard let day = calendar.date(byAdding: .day, value: -daysBefore, to: calendar.startOfDay(for: date)),
              let fireDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day),
              fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
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
