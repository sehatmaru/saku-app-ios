import AppIntents

/// Siri and Shortcuts: "Catat di Saku ...". The result joins "Konfirmasi transaksi"; nothing is saved without a look.
struct RecordTransactionIntent: AppIntent {
    static let title: LocalizedStringResource = "Catat transaksi"
    static let description = IntentDescription("Catat transaksi dari satu kalimat, misalnya \"kopi 25rb gopay\". Hasilnya masuk ke Konfirmasi transaksi.")

    @Parameter(title: "Teks", requestValueDialog: "Apa yang mau dicatat?")
    var text: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard SmartTrackerWays.siri else { return .result(dialog: "Siri belum diaktifkan. Nyalakan di Profil > Smart Tracker.") }
        let added = await MainActor.run { DraftStore.shared.add(text: text, source: .siri) }
        let count = added.count
        await DraftNotifier.announce(added)
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

    /// Only what the owner can act on gets a notification: Plus, the AI allowance, and the Smart Tracker agreement.
    /// A picture with no text or no amount stays quiet.
    private func stop(_ title: String, _ body: String) async -> IntentDialog {
        await DraftNotifier.explain(title: L(title), body: L(body))
        return IntentDialog(stringLiteral: L(title))
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        SakuShortcut.screenshot.noteRun()
        guard PlusStore.cachedIsPlus else {
            return .result(dialog: await stop("Baca gambar butuh Saku Plus", "Draf yang sudah ada tetap bisa diperiksa dan disimpan."))
        }
        guard SmartTrackerConsent.isGranted else {
            return .result(dialog: await stop("Smart Tracker belum disetujui", "Buka Saku dan setujui Smart Tracker supaya gambar bisa dibaca."))
        }
        guard let cg = ImageReader.downscaled(image.data) else { return .result(dialog: "Gambar tidak bisa dibuka.") }
        let lines = await ImageReader.lines(in: cg)
        guard !lines.isEmpty else { return .result(dialog: "Tidak ada teks di gambar ini.") }
        let imageId = DraftImageStore.save(cg)
        let read = await MainActor.run { DraftStore.shared }.ingestPhoto(lines: lines, imageId: imageId)
        if read.drafts.isEmpty {
            if read.outOfQuota {
                return .result(dialog: await stop("Jatah AI bulan ini habis", "Gambar ini belum terbaca. Jatah terisi lagi bulan depan."))
            }
            return .result(dialog: "Tidak ada nominal di gambar ini, jadi tidak dibuat draf.")
        }
        await DraftNotifier.announce(read.drafts)
        return .result(dialog: "\(read.drafts.count) draf masuk ke Konfirmasi transaksi di Saku.")
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
        SakuShortcut.notification.noteRun()
        // Recording from notifications is a Saku Plus feature; drafts already queued stay (US6, TC 17).
        guard PlusStore.cachedIsPlus else { return .result(dialog: "Fitur ini butuh Saku Plus. Draf yang sudah ada tetap bisa diperiksa dan disimpan.") }
        NotificationFilter.remember(title: notificationTitle)
        guard NotificationFilter.allows(title: notificationTitle, subtitle: subtitle) else {
            return .result(dialog: "Notifikasi diabaikan sesuai pengaturan Notifikasi aplikasi.")
        }
        let result = await MainActor.run { () -> (added: Int, skipped: Int, drafts: [Draft]) in
            let store = DraftStore.shared
            let drafts = NotificationParser.parse(app: appName, title: notificationTitle, subtitle: subtitle, body: body,
                                                  context: store.context)
            if !drafts.isEmpty { store.noteConnected(app: appName) }
            let raw = [notificationTitle, subtitle, body].filter { !$0.isEmpty }.joined(separator: "\n")
            let kept = drafts.map { var d = $0; d.rawText = raw; return d }
            let counts = store.addFromNotification(kept, appName: appName)
            return (counts.added, counts.skipped, Array(store.drafts.prefix(counts.added)))
        }
        if result.added > 0 { await DraftNotifier.announce(result.drafts) }
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
