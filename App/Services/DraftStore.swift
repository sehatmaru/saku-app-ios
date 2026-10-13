import Foundation
import SwiftUI
import UserNotifications

/// The "Konfirmasi transaksi" queue and what Saku learned from corrections. Everything lives on the device
/// (one JSON file); the raw sentence is never kept, only the draft that came out of it. Drafts expire
/// after 30 days. Siri, Shortcuts and the share extension add to the same file.
@MainActor
final class DraftStore: ObservableObject {
    static let shared = DraftStore()

    @Published private(set) var drafts: [Draft] = []
    /// A draft the queue should open in the editor as soon as it appears ("Isi manual" in the quick result).
    @Published var editRequest: UUID?
    @Published private(set) var memory: [MerchantMemory.Entry] = []
    /// Wallets, categories and recent transactions, kept for parsing offline and the duplicate check.
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var categories: [Category] = []
    /// Bank and e-wallet apps whose notifications have reached Saku (shown as "Sudah terhubung").
    @Published private(set) var connectedApps: [String] = []
    private var recent: [Transaction] = []

    private struct Snapshot: Codable {
        var drafts: [Draft] = []
        var memory: [MerchantMemory.Entry] = []
        var accounts: [Account] = []
        var categories: [Category] = []
        var connectedApps: [String] = []
        /// Forgotten Ingatan entries, kept so the server and other devices drop them too (optional: older files lack it).
        var memoryTombstones: [MerchantMemory.Entry]?
        /// "Lupakan semua" pressed at this moment and not yet told to the server.
        var memoryForgottenAt: Date?
    }

    private var memoryTombstones: [MerchantMemory.Entry] = []
    private var memoryForgottenAt: Date?
    /// Guests keep Ingatan on the device only.
    var isGuest = false
    private var isSyncingMemory = false
    private var memorySyncTask: Task<Void, Never>?

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultURL
        load()
    }

    /// App Group container when the app has one (so the share extension can write too), else Application Support.
    private static var defaultURL: URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SmartTracker.appGroup)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("smart-tracker.json")
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL), let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        // card bills are paid by hand in Saku; an older draft of that kind becomes one to fill in manually
        drafts = snapshot.drafts.map { draft in
            guard draft.kind == .cardPayment else { return draft }
            var copy = draft
            copy.kind = .expense
            copy.isUnreadable = true
            copy.accountId = nil
            copy.counterpartyAccountId = nil
            return copy
        }
        memory = snapshot.memory
        accounts = snapshot.accounts
        categories = snapshot.categories
        connectedApps = snapshot.connectedApps
        memoryTombstones = snapshot.memoryTombstones ?? []
        memoryForgottenAt = snapshot.memoryForgottenAt
        purgeExpired()
    }

    private func persist() {
        let snapshot = Snapshot(drafts: drafts, memory: memory, accounts: accounts, categories: categories, connectedApps: connectedApps,
                                memoryTombstones: memoryTombstones, memoryForgottenAt: memoryForgottenAt)
        if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: fileURL, options: .atomic) }
        updateBadge()
    }

    /// Drafts the user never handled are dropped after 30 days.
    func purgeExpired(now: Date = Date()) {
        let kept = drafts.filter { $0.expiresAt > now }
        if kept.count != drafts.count { drafts = kept; persist() }
    }

    /// Drafts that disappear within three days, for the in-app notice.
    var expiringSoon: Int {
        let limit = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
        return drafts.filter { $0.expiresAt < limit }.count
    }

    private func updateBadge() {
        UNUserNotificationCenter.current().setBadgeCount(drafts.count)
    }

    // MARK: Reference data

    /// Reloads wallets, categories and recent transactions; keeps the old ones when offline.
    func refreshReferenceData(userId: String) async {
        async let accountsTask = SupabaseRepository.shared.fetchAccounts(userId: userId)
        async let categoriesTask = SupabaseRepository.shared.fetchCategories()
        async let transactionsTask = SupabaseRepository.shared.fetchTransactions(userId: userId)
        if let fetched = try? await accountsTask { accounts = fetched }
        if let fetched = try? await categoriesTask { categories = fetched }
        if let fetched = try? await transactionsTask { recent = fetched }
        persist()
        recheckDuplicates()
        await syncMemory()
    }

    // MARK: Ingatan sync

    /// Syncs a moment after something changed, so a burst of edits is one round trip.
    private func scheduleMemorySync() {
        guard SmartTrackerMemorySync.isGranted, !isGuest else { return }
        memorySyncTask?.cancel()
        memorySyncTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.syncMemory()
        }
    }

    /// Ingatan follows the account: merged with the server's copy (latest change wins), then what the server lacks
    /// is sent. Nothing leaves the device for guests or before the user agreed. Offline, it simply tries again later.
    func syncMemory() async {
        guard !isGuest, SmartTrackerConsent.isGranted, SmartTrackerMemorySync.isGranted, !isSyncingMemory else { return }
        isSyncingMemory = true
        defer { isSyncingMemory = false }
        do {
            if let forgotten = memoryForgottenAt {
                try await SupabaseSDK.forgetAllMemory(before: forgotten)
                if memoryForgottenAt == forgotten { memoryForgottenAt = nil }
            }
            let remote = try await SupabaseSDK.fetchMemory()
            let result = MerchantMemory.merge(local: memory, tombstones: memoryTombstones, remote: remote)
            memory = result.live
            memoryTombstones = result.tombstones
            persist()
            try await SupabaseSDK.pushMemory(result.toPush)
        } catch {
            // offline or the server said no: the device copy stays as it is and the next sync retries
        }
    }

    var context: SmartParser.Context {
        SmartParser.Context(accounts: accounts, categories: categories, memory: memory)
    }

    // MARK: Adding

    /// Reads a sentence and queues what it finds. Returns the new drafts.
    @discardableResult
    func add(text: String, source: Draft.Source) -> [Draft] {
        add(SmartParser.parse(text, source: source, context: context))
    }

    /// Like `add(text:)`, but a sentence the rules could not read is handed to the language model (server)
    /// when the user agreed to it and there is a network; offline it stays as the user's own words.
    func addRefined(text: String, source: Draft.Source) async -> [Draft] {
        let parsed = SmartParser.parse(text, source: source, context: context)
        // the language model (server) is only used with the user's agreement
        guard SmartTrackerConsent.isGranted, parsed.count == 1, parsed[0].isUnreadable || parsed[0].amount == nil,
              let remote = await RemoteSmartParser.parse(text, source: source, context: context) else { return add(parsed) }
        return add(remote)
    }

    /// The language model's reading of a sentence the rules could not read; nil when not agreed, offline or no answer.
    func refined(_ text: String, source: Draft.Source) async -> [Draft]? {
        guard SmartTrackerConsent.isGranted else { return nil }
        return await RemoteSmartParser.parse(text, source: source, context: context)
    }

    @discardableResult
    func add(_ new: [Draft]) -> [Draft] {
        let marked = new.map { withDuplicateNote($0) }
        drafts.insert(contentsOf: marked, at: 0)
        persist()
        return marked
    }

    func update(_ draft: Draft) {
        guard let index = drafts.firstIndex(where: { $0.id == draft.id }) else { return }
        drafts[index] = withDuplicateNote(draft)
        persist()
    }

    /// Puts a draft back where it was (Urungkan), newest first like the rest.
    func restore(_ draft: Draft) {
        guard !drafts.contains(where: { $0.id == draft.id }) else { return }
        let index = drafts.firstIndex { $0.createdAt < draft.createdAt } ?? drafts.count
        drafts.insert(draft, at: index)
        persist()
    }

    func discard(_ id: UUID) {
        drafts.removeAll { $0.id == id }
        persist()
    }

    /// Text shared from other apps becomes drafts; the inbox is emptied so the raw text is not kept.
    func ingestSharedText() {
        purgeExpired()
        // not agreed yet: the shared text waits in the inbox until the user is asked
        guard SmartTrackerConsent.isGranted else { return }
        guard SmartTrackerWays.share else { _ = ShareInbox.drain(); return }
        let texts = ShareInbox.drain()
        guard !texts.isEmpty else { return }
        let added = texts.flatMap { SmartParser.parse($0, source: .share, context: context) }
        // the share extension already told the user; no second notification here
        add(added)
    }

    // MARK: Duplicates

    /// "Mirip dengan transaksi …": same amount, same wallet, same day as a saved transaction or another draft.
    func duplicateNote(for draft: Draft) -> String? {
        guard let amount = draft.amount, let accountId = draft.accountId else { return nil }
        let calendar = Calendar.current
        if let match = recent.first(where: {
            $0.accountId == accountId && abs($0.amount - amount) < 0.5 && calendar.isDate($0.date, inSameDayAs: draft.date)
                && $0.type != .adjustment
        }) {
            return L("Mirip dengan transaksi %@ %@ (%@)", match.displayNote ?? L("tanpa catatan"), amount.formattedAsCurrency(),
                     Self.dayFormat.string(from: match.date))
        }
        if drafts.contains(where: {
            $0.id != draft.id && $0.accountId == accountId && $0.amount == amount && calendar.isDate($0.date, inSameDayAs: draft.date)
        }) {
            return L("Mirip dengan draf lain di daftar ini")
        }
        return nil
    }

    private func withDuplicateNote(_ draft: Draft) -> Draft {
        var copy = draft
        copy.duplicateNote = duplicateNote(for: draft)
        return copy
    }

    private func recheckDuplicates() {
        drafts = drafts.map { withDuplicateNote($0) }
    }

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        f.locale = AppLanguage.locale
        return f
    }()

    // MARK: Saving

    enum SaveError: Error { case incomplete, noUser }

    /// Writes the draft as a real transaction, then remembers the user's choices for next time.
    /// Returns the new transaction's id so a save can be undone.
    @discardableResult
    func save(_ draft: Draft, userId: String, remember: Bool = true) async throws -> String? {
        guard draft.isComplete, let amount = draft.amount else { throw SaveError.incomplete }
        if draft.kind == .cardPayment && draft.accountId == nil { try await saveOutsideCardPayment(draft); return nil }
        guard let accountId = draft.accountId else { throw SaveError.incomplete }
        let repo = SupabaseRepository.shared
        let account = accounts.first { $0.id == accountId }
        let created: Transaction
        switch draft.kind {
        case .expense, .income:
            created = try await repo.createTransaction(
                accountId: accountId, categoryId: draft.categoryId, amount: amount,
                type: draft.kind == .income ? .income : .expense, description: draft.title, note: nil,
                date: draft.date, userId: userId, isCreditAccount: account?.isCreditCard ?? false)
        case .transfer, .cardPayment:
            guard let counterparty = draft.counterpartyAccountId else { throw SaveError.incomplete }
            created = try await repo.createTransfer(primaryAccountId: accountId, counterpartyAccountId: counterparty, amount: amount,
                                              description: draft.title, note: nil, date: draft.date)
        }
        if remember { learn(from: draft) }
        discard(draft.id)
        NotificationCenter.default.post(name: .dataDidChange, object: nil)
        return created.id
    }

    /// Saves a draft that was never queued (the quick result sheet): same as `save`, nothing to remove from the queue.
    func saveImmediately(_ draft: Draft, userId: String) async throws {
        _ = try await save(draft, userId: userId)
    }

    /// A card bill paid from outside Saku (no source wallet named): lowers the card's debt only.
    func saveOutsideCardPayment(_ draft: Draft) async throws {
        guard let amount = draft.amount, let card = draft.counterpartyAccountId else { throw SaveError.incomplete }
        try await SupabaseRepository.shared.createCardPayment(cardId: card, amount: amount, note: draft.title, date: draft.date)
        discard(draft.id)
        NotificationCenter.default.post(name: .dataDidChange, object: nil)
    }

    // MARK: Memory

    /// Editing a draft is a correction: remember the choice now, without counting a use (saving counts it).
    func learnCorrection(from draft: Draft) {
        guard draft.categoryId != nil || draft.accountId != nil else { return }
        learn(from: draft, countsUse: false)
    }

    private func learn(from draft: Draft, countsUse: Bool = true) {
        guard let keyword = MerchantMemory.keyword(for: draft), draft.kind == .expense || draft.kind == .income else { return }
        var entry = MerchantMemory.Entry(keyword: keyword, kind: draft.kind, categoryId: draft.categoryId, accountId: draft.accountId)
        if let old = memory.first(where: { $0.id == entry.id }) {
            // the same choice again counts up; a new choice starts over
            let same = old.categoryId == entry.categoryId && old.accountId == entry.accountId
            entry.uses = same ? old.uses + (countsUse ? 1 : 0) : 1
        }
        memory.removeAll { $0.id == entry.id }
        memoryTombstones.removeAll { $0.id == entry.id }
        memory.insert(entry, at: 0)
        persist()
        scheduleMemorySync()
    }

    /// Forgets one remembered choice: the category part or the wallet part of a keyword.
    func forget(_ entry: MerchantMemory.Entry, field: MerchantMemory.Field) {
        guard let index = memory.firstIndex(where: { $0.id == entry.id }) else { return }
        switch field {
        case .category: memory[index].categoryId = nil
        case .account: memory[index].accountId = nil
        }
        memory[index].updatedAt = Date()
        if memory[index].categoryId == nil && memory[index].accountId == nil { tombstone(at: index) }
        persist()
        scheduleMemorySync()
    }

    /// Moves a live entry to the tombstones, dated now, so the server and other devices forget it too.
    private func tombstone(at index: Int) {
        var entry = memory.remove(at: index)
        entry.deletedAt = Date()
        entry.updatedAt = Date()
        memoryTombstones.removeAll { $0.id == entry.id }
        memoryTombstones.append(entry)
    }

    func noteConnected(app: String) {
        guard !app.isEmpty, !connectedApps.contains(app) else { return }
        connectedApps.append(app)
        persist()
    }

    func forget(_ entry: MerchantMemory.Entry) {
        guard let index = memory.firstIndex(where: { $0.id == entry.id }) else { return }
        tombstone(at: index)
        persist()
        scheduleMemorySync()
    }

    func forgetEverything() {
        forgetAllMemory()
        drafts = []
        connectedApps = []
        persist()
    }

    /// Forgets every remembered choice but keeps the drafts.
    func forgetMemory() {
        forgetAllMemory()
        persist()
        scheduleMemorySync()
    }

    private func forgetAllMemory() {
        let now = Date()
        for var entry in memory {
            entry.deletedAt = now
            entry.updatedAt = now
            memoryTombstones.removeAll { $0.id == entry.id }
            memoryTombstones.append(entry)
        }
        memory = []
        // entries only the server knows about are dropped there at this moment
        memoryForgottenAt = now
    }

    /// Signing out: nothing of this account stays on the device for the next one.
    func reset() {
        memory = []
        drafts = []
        accounts = []
        categories = []
        connectedApps = []
        recent = []
        memoryTombstones = []
        memoryForgottenAt = nil
        persist()
    }
}

enum SmartTracker {
    static let appGroup = ShareInbox.appGroup
}
