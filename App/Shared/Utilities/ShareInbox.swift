import Foundation

/// Text shared to Saku from other apps. The share extension appends here (App Group file); the app
/// reads it when it becomes active, turns it into drafts, and empties it. Compiled into both targets.
enum ShareInbox {
    static let appGroup = "group.id.saku.app"

    private static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appendingPathComponent("share-inbox.json")
    }

    static func append(_ text: String) {
        guard let url else { return }
        var items = (try? JSONDecoder().decode([String].self, from: Data(contentsOf: url))) ?? []
        items.append(text)
        try? JSONEncoder().encode(items).write(to: url, options: .atomic)
    }

    /// Returns everything waiting and clears the file, so the raw text is not kept.
    static func drain() -> [String] {
        guard let url, let data = try? Data(contentsOf: url), let items = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        try? FileManager.default.removeItem(at: url)
        return items
    }
}
