import AppIntents

/// Siri and Shortcuts: "Catat di Saku ...". The result joins "Konfirmasi transaksi"; nothing is saved without a look.
struct RecordTransactionIntent: AppIntent {
    static let title: LocalizedStringResource = "Catat transaksi"
    static let description = IntentDescription("Catat transaksi dari satu kalimat, misalnya \"kopi 25rb gopay\". Hasilnya masuk ke Konfirmasi transaksi.")

    @Parameter(title: "Teks", requestValueDialog: "Apa yang mau dicatat?")
    var text: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard SmartTrackerWays.siri else { return .result(dialog: "Siri belum diaktifkan. Nyalakan di Profil > Smart Tracker.") }
        let count = await MainActor.run { DraftStore.shared.add(text: text, source: .siri).count }
        await DraftNotifier.announce(count: count)
        return .result(dialog: "\(count) draf masuk ke Konfirmasi transaksi di Saku.")
    }
}

/// Shortcuts: feed a screenshot, photo or receipt (from "Ambil screenshot", "Ambil foto" or the photo picker). The picture is read
/// on the device and dropped; only its text goes on, like a picture shared from another app. Reading pictures is Saku Plus.
struct ReadImageIntent: AppIntent {
    static let title: LocalizedStringResource = "Baca gambar"
    static let description = IntentDescription("Membaca screenshot, foto, atau struk dan membuat draf. Hasilnya masuk ke Konfirmasi transaksi.")

    @Parameter(title: "Gambar", supportedContentTypes: [.image], requestValueDialog: "Gambar mana yang mau dibaca?",
               inputConnectionBehavior: .connectToPreviousIntentResult)
    var image: IntentFile

    private func why(_ text: String) async -> IntentDialog {
        await DraftNotifier.explain(text)
        return IntentDialog(stringLiteral: text)
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard PlusStore.cachedIsPlus else { return .result(dialog: await why("Membaca gambar butuh Saku Plus. Draf yang sudah ada tetap bisa diperiksa dan disimpan.")) }
        guard let cg = ImageReader.downscaled(image.data) else { return .result(dialog: await why("Gambar tidak bisa dibuka.")) }
        let lines = await ImageReader.lines(in: cg)
        guard !lines.isEmpty else { return .result(dialog: await why("Tidak ada teks di gambar ini.")) }
        let count = await MainActor.run { DraftStore.shared }.ingestPhoto(lines: lines)
        guard count > 0 else { return .result(dialog: await why("Tidak ada nominal di gambar ini, jadi tidak dibuat draf.")) }
        await DraftNotifier.announce(count: count)
        return .result(dialog: "\(count) draf masuk ke Konfirmasi transaksi di Saku.")
    }
}

/// Opens Konfirmasi transaksi.
struct ReviewDraftsIntent: AppIntent {
    static let title: LocalizedStringResource = "Lihat draf"
    static let description = IntentDescription("Membuka Konfirmasi transaksi di Saku.")
    static let openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult {
        NotificationRouter.shared.opensDrafts = true
        return .result()
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
        guard SmartTrackerWays.notification else { return .result(dialog: "Notifikasi belum diaktifkan. Nyalakan di Profil > Smart Tracker.") }
        // Recording from notifications is a Saku Plus feature; drafts already queued stay (US6, TC 17).
        guard PlusStore.cachedIsPlus else { return .result(dialog: "Fitur ini butuh Saku Plus. Draf yang sudah ada tetap bisa diperiksa dan disimpan.") }
        NotificationFilter.remember(title: notificationTitle)
        guard NotificationFilter.allows(title: notificationTitle, subtitle: subtitle) else {
            return .result(dialog: "Notifikasi diabaikan sesuai pengaturan Notifikasi aplikasi.")
        }
        let result = await MainActor.run { () -> (added: Int, skipped: Int) in
            let store = DraftStore.shared
            let drafts = NotificationParser.parse(app: appName, title: notificationTitle, subtitle: subtitle, body: body,
                                                  context: store.context)
            if !drafts.isEmpty { store.noteConnected(app: appName) }
            let raw = [notificationTitle, subtitle, body].filter { !$0.isEmpty }.joined(separator: "\n")
            return store.addFromNotification(drafts.map { var d = $0; d.rawText = raw; return d }, appName: appName)
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
        AppShortcut(intent: ReadImageIntent(), phrases: ["Baca gambar di \(.applicationName)", "Baca screenshot di \(.applicationName)"],
                    shortTitle: "Baca gambar", systemImageName: "photo")
        AppShortcut(intent: ReviewDraftsIntent(), phrases: ["Lihat draf di \(.applicationName)"],
                    shortTitle: "Lihat draf", systemImageName: "tray.full")
    }
}
