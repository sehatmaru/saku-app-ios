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
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
