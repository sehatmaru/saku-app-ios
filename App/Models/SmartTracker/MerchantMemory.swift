import Foundation

/// What the user chose for a merchant or keyword last time, so the next draft starts filled in.
/// Kept on the device; viewable and removable in Profil.
enum MerchantMemory {
    enum Field { case category, account }

    struct Entry: Codable, Equatable, Identifiable {
        var id: String { keyword + "|" + kind.rawValue }
        let keyword: String
        let kind: Draft.Kind
        var categoryId: String?
        var accountId: String?
        /// How many times a saved draft confirmed this choice.
        var uses = 1
        var updatedAt = Date()
        /// Set when the user forgot it: kept as a tombstone so the other devices drop it too.
        var deletedAt: Date?
    }

    /// How many entries one user keeps; past that the least used go first.
    static let limit = 500

    struct SyncResult: Equatable {
        var live: [Entry]
        var tombstones: [Entry]
        /// What the server does not have yet, or has an older version of.
        var toPush: [Entry]
    }

    /// Merges this device's entries with the server's: per keyword the latest change wins, a newer tombstone
    /// removes the entry, and more than `limit` live entries drop the least used (then the oldest).
    static func merge(local: [Entry], tombstones: [Entry], remote: [Entry], now: Date = Date()) -> SyncResult {
        let remoteById = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { a, b in a.updatedAt >= b.updatedAt ? a : b })
        var chosen: [String: Entry] = remoteById
        for entry in local + tombstones where entry.updatedAt > (chosen[entry.id]?.updatedAt ?? .distantPast) {
            chosen[entry.id] = entry
        }
        var live = chosen.values.filter { $0.deletedAt == nil }
        var dead = chosen.values.filter { $0.deletedAt != nil }
        if live.count > limit {
            live.sort { ($0.uses, $0.updatedAt) > ($1.uses, $1.updatedAt) }
            for var extra in live[limit...] {
                extra.deletedAt = now
                extra.updatedAt = now
                dead.append(extra)
                chosen[extra.id] = extra
            }
            live = Array(live[..<limit])
        }
        let toPush = chosen.values.filter { entry in
            guard let server = remoteById[entry.id] else { return true }
            return entry.updatedAt > server.updatedAt
        }
        let order: (Entry, Entry) -> Bool = { $0.updatedAt > $1.updatedAt }
        return SyncResult(live: live.sorted(by: order), tombstones: dead.sorted(by: order), toPush: toPush)
    }

    /// The remembered entry whose keyword appears in the text (longest keyword wins).
    static func match(in text: String, entries: [Entry], kind: Draft.Kind) -> Entry? {
        entries.filter { $0.kind == kind && text.contains($0.keyword) }.max { $0.keyword.count < $1.keyword.count }
    }

    /// The keyword to remember for a saved draft: its title, lowercased.
    static func keyword(for draft: Draft) -> String? {
        let word = draft.title.lowercased().trimmingCharacters(in: .whitespaces)
        return word.count >= 2 && !draft.isUnreadable ? word : nil
    }
}

/// Per-device switch for Siri (Profil › Smart Tracker). Typing, voice, pictures and sharing are always on.
enum SmartTrackerWays {
    static let siriKey = "smartWaySiri"

    static var siri: Bool {
        get { UserDefaults.standard.object(forKey: siriKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: siriKey) }
    }
}

/// Whether this account agreed to the language model (AI) reading what it types, says, shares or receives.
/// Smart Tracker itself is always on; this is the AI switch. The profile row is the source of truth (per account,
/// every device); `SupabaseSDK` mirrors it here so the app can check it without a network call. Cleared on sign-out.
enum SmartTrackerConsent {
    static let key = "smartTrackerConsent"
    static let sinceKey = "smartTrackerConsentSince"
    /// The one-time AI sheet was shown (agreed or "Nanti saja"); existing users see it once.
    static let promptSeenKey = "smartTrackerAIPromptSeen"

    static var since: Date? {
        get { UserDefaults.standard.object(forKey: sinceKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: sinceKey) }
    }

    static var isGranted: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static var promptSeen: Bool {
        get { UserDefaults.standard.bool(forKey: promptSeenKey) }
        set { UserDefaults.standard.set(newValue, forKey: promptSeenKey) }
    }
}

/// Ingatan on the server follows the AI switch: synced while AI is on, paused (server data kept) while it is off.
/// Guests never sync, whatever this says.
enum SmartTrackerMemorySync {
    static var isGranted: Bool { SmartTrackerConsent.isGranted }
}
