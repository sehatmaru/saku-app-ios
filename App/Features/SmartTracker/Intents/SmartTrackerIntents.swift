import AppIntents

/// Siri and Shortcuts: "Catat di Saku ...". The result joins "Konfirmasi transaksi"; nothing is saved without a look.
struct RecordTransactionIntent: AppIntent {
    static let title: LocalizedStringResource = "Catat transaksi"
    static let description = IntentDescription("Catat transaksi dari satu kalimat, misalnya \"kopi 25rb gopay\". Hasilnya masuk ke Konfirmasi transaksi.")

    @Parameter(title: "Teks", requestValueDialog: "Apa yang mau dicatat?")
    var text: String

    static let needsConsent: IntentDialog = "Buka Saku dan setujui Catat cepat dulu, lalu coba lagi."

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard SmartTrackerConsent.isGranted else { return .result(dialog: Self.needsConsent) }
        guard SmartTrackerWays.siri else { return .result(dialog: "Siri belum diaktifkan. Nyalakan di Profil > Smart Tracker.") }
        let count = await MainActor.run { DraftStore.shared.add(text: text, source: .siri).count }
        await DraftNotifier.announce(count: count)
        return .result(dialog: "\(count) draf masuk ke Konfirmasi transaksi di Saku.")
    }
}

/// Shortcuts automation with the "Notifikasi" trigger: pass the notification's title, subtitle and body.
struct RecordFromNotificationIntent: AppIntent {
    static let title: LocalizedStringResource = "Catat dari notifikasi"
    static let description = IntentDescription("Membaca notifikasi bank atau e-wallet dan membuat draf. Notifikasi tanpa nominal diabaikan.")

    @Parameter(title: "Aplikasi sumber") var appName: String
    @Parameter(title: "Judul") var notificationTitle: String
    @Parameter(title: "Subjudul", default: "") var subtitle: String
    @Parameter(title: "Isi") var body: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard SmartTrackerConsent.isGranted else { return .result(dialog: RecordTransactionIntent.needsConsent) }
        NotificationFilter.remember(title: notificationTitle)
        guard NotificationFilter.allows(title: notificationTitle, subtitle: subtitle) else {
            return .result(dialog: "Notifikasi diabaikan sesuai pengaturan Notifikasi aplikasi.")
        }
        let result = await MainActor.run { () -> (added: Int, skipped: Int) in
            let store = DraftStore.shared
            let drafts = NotificationParser.parse(app: appName, title: notificationTitle, subtitle: subtitle, body: body,
                                                  context: store.context)
            if !drafts.isEmpty { store.noteConnected(app: appName) }
            return store.addFromNotification(drafts, appName: appName)
        }
        if result.added > 0 { await DraftNotifier.announce(count: result.added) }
        // an empty body usually means the Shortcut's Body variable is not filled, which is worth saying
        let nothing = body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && subtitle.isEmpty
            ? "Isi notifikasi kosong. Cek variabel Isi di Shortcuts."
            : "Tidak ada nominal, notifikasi diabaikan."
        let dialog: IntentDialog = if result.added > 0 {
            "Draf dari notifikasi masuk ke Konfirmasi transaksi."
        } else if result.skipped > 0 {
            "Notifikasi sudah tercatat di Saku, jadi tidak dibuat draf baru. Bisa dibatalkan di Konfirmasi transaksi."
        } else {
            IntentDialog(stringLiteral: nothing)
        }
        return .result(dialog: dialog)
    }
}

struct SakuShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RecordTransactionIntent(), phrases: ["Catat di \(.applicationName)", "Catat transaksi di \(.applicationName)"],
                    shortTitle: "Catat transaksi", systemImageName: "plus.circle")
    }
}
