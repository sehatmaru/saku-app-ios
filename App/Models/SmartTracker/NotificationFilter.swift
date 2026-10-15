import Foundation

/// Which bank or e-wallet notifications become drafts (BUG-22). Two lists of words, matched against the title and
/// subtitle without regard to case: anything matching "Abaikan" is dropped, and when "Hanya tangkap" has words only
/// matching notifications are kept. The last few titles (never the body) are remembered so they can be tapped
/// into a list. Per device, in UserDefaults; the titles are cleared with the rest of Smart Tracker's data.
enum NotificationFilter {
    static let ignoreKey = "notifIgnoreWords"
    static let onlyKey = "notifOnlyWords"
    static let recentKey = "notifRecentTitles"
    static let recentLimit = 10

    static var ignore: [String] {
        get { UserDefaults.standard.stringArray(forKey: ignoreKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: ignoreKey) }
    }
    static var only: [String] {
        get { UserDefaults.standard.stringArray(forKey: onlyKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: onlyKey) }
    }
    static var recent: [String] {
        get { UserDefaults.standard.stringArray(forKey: recentKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: recentKey) }
    }

    /// Whether a notification passes the two lists.
    static func allows(title: String, subtitle: String, ignore: [String], only: [String]) -> Bool {
        let text = (title + " " + subtitle).lowercased()
        func hits(_ words: [String]) -> Bool { words.contains { !$0.isEmpty && text.contains($0.lowercased()) } }
        if hits(ignore) { return false }
        return only.isEmpty || hits(only)
    }

    static func allows(title: String, subtitle: String) -> Bool {
        allows(title: title, subtitle: subtitle, ignore: ignore, only: only)
    }

    /// Newest first, no repeats (ignoring case), at most `recentLimit`.
    static func remember(title: String) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        var list = recent.filter { $0.caseInsensitiveCompare(clean) != .orderedSame }
        list.insert(clean, at: 0)
        recent = Array(list.prefix(recentLimit))
    }

    static func add(_ word: String, toOnly: Bool) {
        let clean = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if toOnly { if !only.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) { only.append(clean) } }
        else if !ignore.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) { ignore.append(clean) }
    }

    static func clearRecent() { UserDefaults.standard.removeObject(forKey: recentKey) }
}
