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

    /// Drops every reminder still waiting (account reset).
    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
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
        let stale = await center.pendingNotificationRequests().map(\.identifier)
            .filter { $0.hasPrefix("card-due-") || $0.hasPrefix(Self.latePrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)
        let store = BillReminderStore()
        for (card, statement) in zip(cards, statements) where statement.remaining >= 1 {
            await scheduleLateReminder(card: card, statement: statement, store: store)
            let amount = statement.remaining.formattedAsCurrency()
            await add(id: "card-due-\(card.id)-3", title: "Tagihan \(card.name)",
                      body: "Tagihan \(amount) jatuh tempo 3 hari lagi.", daysBefore: 3, date: statement.dueDate)
            await add(id: "card-due-\(card.id)-1", title: "Tagihan \(card.name)",
                      body: "Tagihan \(amount) jatuh tempo besok. Bayar penuh supaya tidak kena bunga.", daysBefore: 1, date: statement.dueDate)
        }
    }

    static let latePrefix = "card-late-"
    static let lateCategory = "CARD_LATE"
    static let recordAction = "CARD_LATE_RECORD"
    static let notYetAction = "CARD_LATE_NOT_YET"

    /// "Sudah kamu bayar?" the morning after the due date; once overdue, only the wake-up the
    /// user asked for with "Belum".
    private func scheduleLateReminder(card: Account, statement: CreditStatement, store: BillReminderStore) async {
        let fireDay: Date
        let daysBefore: Int
        if statement.status == .overdue {
            guard let until = store.snoozedUntil(card: card.id, statementDate: statement.statementDate) else { return }
            fireDay = until
            daysBefore = 0
        } else {
            fireDay = statement.dueDate
            daysBefore = -1
        }
        let text = Self.lateText(card: card, statement: statement)
        await add(id: Self.latePrefix + card.id, title: text.title, body: text.body,
                  daysBefore: daysBefore, date: fireDay, category: Self.lateCategory,
                  userInfo: Self.lateInfo(cardId: card.id, statementDate: statement.statementDate))
    }

    static func lateText(card: Account, statement: CreditStatement) -> (title: String, body: String) {
        ("Tagihan \(card.name) jatuh tempo \(TransactionDates.dayMonth.string(from: statement.dueDate))",
         "\(statement.remaining.formattedAsCurrency()) belum tercatat lunas. Sudah kamu bayar?")
    }

    private static func lateInfo(cardId: String, statementDate: Date) -> [String: Any] {
        ["cardId": cardId, "statementDate": statementDate.timeIntervalSince1970]
    }

    /// "Belum": stay quiet until tomorrow 09:00 and ask again then.
    func snoozeLateReminder(cardId: String, statementDate: Date, title: String, body: String) async {
        let wake = BillReminderStore.tomorrowMorning()
        BillReminderStore().snooze(card: cardId, statementDate: statementDate, until: wake)
        // "Ingatkan besok" only works with notifications on, so ask right when the user wants one.
        await requestPermissionIfNeeded()
        await add(id: Self.latePrefix + cardId, title: title, body: body, daysBefore: 0, date: wake,
                  category: Self.lateCategory, userInfo: Self.lateInfo(cardId: cardId, statementDate: statementDate))
    }

    /// Registers the "Sudah, catat" / "Belum" buttons on the overdue-bill notification.
    func registerCategories() {
        let record = UNNotificationAction(identifier: Self.recordAction, title: "Sudah, catat", options: [.foreground])
        let notYet = UNNotificationAction(identifier: Self.notYetAction, title: "Belum", options: [])
        let category = UNNotificationCategory(identifier: Self.lateCategory, actions: [record, notYet],
                                              intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// A one-off reminder at 09:00, `daysBefore` days before `date`; skipped once that's past.
    private func add(id: String, title: String, body: String, daysBefore: Int, date: Date,
                     category: String? = nil, userInfo: [String: Any] = [:]) async {
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
        if let category { content.categoryIdentifier = category }
        content.userInfo = userInfo
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
