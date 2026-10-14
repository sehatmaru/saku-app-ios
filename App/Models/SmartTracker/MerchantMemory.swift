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

/// Per-device switches for each way of recording (Profil › Smart Tracker). The agreement itself is per account.
/// Mirrored into the App Group so the share extension can honour its switch.
enum SmartTrackerWays {
    static let quickKey = "smartWayQuick"
    static let shareKey = "smartWayShare"
    static let siriKey = "smartWaySiri"

    static var quick: Bool {
        get { UserDefaults.standard.object(forKey: quickKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: quickKey) }
    }
    static var share: Bool {
        get { UserDefaults.standard.object(forKey: shareKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: shareKey)
            ShareInbox.setEnabled(newValue)
        }
    }
    static var siri: Bool {
        get { UserDefaults.standard.object(forKey: siriKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: siriKey) }
    }
}

/// Whether this account agreed to Smart Tracker reading sentences, notifications and shared text.
/// The profile row is the source of truth (per account, every device); `SupabaseSDK` mirrors it here so
/// Siri, Shortcuts and the share extension can check it without a network call. Cleared on sign-out.
enum SmartTrackerConsent {
    static let key = "smartTrackerConsent"

    static let sinceKey = "smartTrackerConsentSince"

    /// When the user agreed, for "Aktif sejak".
    static var since: Date? {
        get { UserDefaults.standard.object(forKey: sinceKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: sinceKey) }
    }

    static var isGranted: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            // withdrawing the agreement also switches reading pictures off
            if !newValue { ShareInbox.isImageAgreed = false }
        }
    }
}

/// The short one-time agreement for reading pictures (kamera, galeri, Bagikan). Only counts while Smart Tracker is agreed.
enum SmartTrackerImageConsent {
    static var isGranted: Bool {
        get { SmartTrackerConsent.isGranted && ShareInbox.isImageAgreed }
        set { ShareInbox.isImageAgreed = newValue }
    }
}

/// Whether this account agreed to keeping Ingatan on the server so it follows the user to every device.
/// The profile row is the source of truth (`smart_tracker_memory_consent_at`); mirrored here like `SmartTrackerConsent`.
/// Guests never sync, whatever this says.
enum SmartTrackerMemorySync {
    static let key = "smartTrackerMemorySync"
    static let declinedKey = "smartTrackerMemorySyncDeclinedAt"

    static var isGranted: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// "Nanti saja" was chosen at this moment; asked again after a week.
    static var declinedAt: Date? {
        get { UserDefaults.standard.object(forKey: declinedKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: declinedKey) }
    }

    static var shouldAsk: Bool {
        guard !isGranted else { return false }
        guard let declinedAt else { return true }
        return Date().timeIntervalSince(declinedAt) > 7 * 86_400
    }
}
