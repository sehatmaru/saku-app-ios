import Foundation

/// Text shared to Saku from other apps. The share extension appends here (App Group file); the app
/// reads it when it becomes active, turns it into drafts, and empties it. Compiled into both targets.
enum ShareInbox {
    static let appGroup = "group.id.saku.app"

    private static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appendingPathComponent("share-inbox.json")
    }

    /// The "Bagikan teks" switch in Profil, kept in the App Group so the extension can read it.
    static var isEnabled: Bool {
        UserDefaults(suiteName: appGroup)?.object(forKey: "shareEnabled") as? Bool ?? true
    }

    static func setEnabled(_ on: Bool) {
        UserDefaults(suiteName: appGroup)?.set(on, forKey: "shareEnabled")
    }

    /// Text read from a shared picture starts with this mark; the picture itself is never stored.
    static let photoMark = "\u{1}photo\u{1}"

    /// The short agreement for reading pictures, kept in the App Group so the extension can check it.
    static var isImageAgreed: Bool {
        get { UserDefaults(suiteName: appGroup)?.bool(forKey: "imageAgreed") ?? false }
        set { UserDefaults(suiteName: appGroup)?.set(newValue, forKey: "imageAgreed") }
    }

    /// Whether the account has Saku Plus, mirrored by the app so the extension can refuse pictures (Plus) without a network call.
    static var isPlus: Bool {
        get { UserDefaults(suiteName: appGroup)?.bool(forKey: "plusActive") ?? false }
        set { UserDefaults(suiteName: appGroup)?.set(newValue, forKey: "plusActive") }
    }

    static func append(_ text: String) {
        guard let url else { return }
        var items = (try? JSONDecoder().decode([String].self, from: Data(contentsOf: url))) ?? []
        items.append(text)
        try? JSONEncoder().encode(items).write(to: url, options: .atomic)
    }

    static var hasItems: Bool {
        guard let url, let data = try? Data(contentsOf: url), let items = try? JSONDecoder().decode([String].self, from: data) else { return false }
        return !items.isEmpty
    }

    /// Returns everything waiting and clears the file, so the raw text is not kept.
    static func drain() -> [String] {
        guard let url, let data = try? Data(contentsOf: url), let items = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        try? FileManager.default.removeItem(at: url)
        return items
    }
}
