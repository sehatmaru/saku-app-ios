import Foundation
import UserNotifications

/// Two local reminders for drafts nobody confirmed: 5 hours and 1 day after the oldest one arrived.
/// Nothing runs in the background: the times are worked out from the queue and handed to the system.
enum DraftReminder {
    static let hours = [5, 24]
    static let quietStart = 22
    static let quietEnd = 7

    /// When each reminder fires. A time that has passed is dropped (it already fired), and a time inside quiet hours
    /// (22:00 to 07:00) moves to 07:00.
    static func fireDates(oldest: Date, now: Date = Date(), calendar: Calendar = .current) -> [(hours: Int, date: Date)] {
        hours.compactMap { h in
            guard let raw = calendar.date(byAdding: .hour, value: h, to: oldest), raw > now else { return nil }
            return (h, quietAdjusted(raw, calendar: calendar))
        }
    }

    static func quietAdjusted(_ date: Date, calendar: Calendar = .current) -> Date {
        let hour = calendar.component(.hour, from: date)
        guard hour >= quietStart || hour < quietEnd else { return date }
        let morning = calendar.date(bySettingHour: quietEnd, minute: 0, second: 0, of: date) ?? date
        return hour < quietEnd ? morning : (calendar.date(byAdding: .day, value: 1, to: morning) ?? morning)
    }

    private static let ids = hours.map { "draft-reminder-\($0)" }

    /// Called whenever the queue changes. Same ids every time, so a new schedule replaces the old one.
    @MainActor static func reschedule(_ drafts: [Draft]) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard SmartTrackerWays.reminder, let oldest = drafts.map(\.createdAt).min() else { return }
        let count = drafts.count
        let title = L("Ada %lld draf belum dicek", count)
        let body = count == 1 ? singleBody(drafts[0]) : L("Ketuk untuk menyimpan atau membuang.")
        for (h, date) in fireDates(oldest: oldest) {
            schedule(id: "draft-reminder-\(h)", title: title, body: body, at: date, center: center)
        }
    }

    @MainActor private static func singleBody(_ d: Draft) -> String {
        guard let amount = d.amount else { return L("Ketuk untuk menyimpan atau membuang.") }
        let kind = d.kind == .income ? L("Pemasukan") : d.kind == .expense ? L("Pengeluaran") : L("Transfer")
        return L("%@ %@ menunggu. Ketuk untuk menyimpan atau membuangnya.", kind, amount.formattedAsCurrency())
    }

    private static func schedule(id: String, title: String, body: String, at date: Date, center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["route": DraftNotifier.route]
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        center.add(UNNotificationRequest(identifier: id, content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
    }

    /// The test button (Profil › Menu uji): shows the reminder in 5 seconds so the text can be checked without waiting.
    /// Returns what happened, so a silent failure (permission off) is visible on the page.
    @MainActor static func sendSample() async -> String {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional else {
            return "Izin notifikasi Saku mati. Nyalakan di Pengaturan iOS > Notifikasi > Saku."
        }
        let content = UNMutableNotificationContent()
        content.title = L("Ada %lld draf belum dicek", 1)
        content.body = L("%@ %@ menunggu. Ketuk untuk menyimpan atau membuangnya.", L("Pengeluaran"), 25_000.0.formattedAsCurrency())
        content.sound = .default
        content.userInfo = ["route": DraftNotifier.route]
        do {
            try await center.add(UNNotificationRequest(identifier: "draft-reminder-sample", content: content,
                                                       trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)))
        } catch { return "Gagal menjadwalkan: \(error.localizedDescription)" }
        return "Terjadwal. Muncul dalam 5 detik. Kalau tidak tampil, cek Fokus atau mode Jangan Ganggu."
    }
}
