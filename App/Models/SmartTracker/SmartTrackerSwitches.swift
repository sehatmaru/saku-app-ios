import Foundation

/// Per-device switches for Siri and for notifications (Profil › Smart Tracker). Typing, voice, pictures and sharing are always on.
enum SmartTrackerWays {
    static let siriKey = "smartWaySiri"
    static let reminderKey = "smartWayReminder"

    /// On by default: a reminder 5 hours and 1 day after a draft arrives while it is still unconfirmed.
    static var reminder: Bool {
        get { UserDefaults.standard.object(forKey: reminderKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: reminderKey) }
    }

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
    /// The accounts that have seen the one-time AI sheet (agreed or "Nanti saja"). It is kept per account, not wiped on
    /// sign-out, so signing in again does not ask again.
    static let promptSeenKey = "smartTrackerAIPromptSeenFor"

    static var since: Date? {
        get { UserDefaults.standard.object(forKey: sinceKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: sinceKey) }
    }

    static var isGranted: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    private static func seenIds() -> [String] { UserDefaults.standard.stringArray(forKey: promptSeenKey) ?? [] }

    static func hasSeenPrompt(for userId: String?) -> Bool {
        guard let id = userId?.lowercased() else { return false }
        return seenIds().contains(id)
    }

    static func markPromptSeen(for userId: String?) {
        guard let id = userId?.lowercased(), !seenIds().contains(id) else { return }
        UserDefaults.standard.set(seenIds() + [id], forKey: promptSeenKey)
    }
}
