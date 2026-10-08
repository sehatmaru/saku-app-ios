import Foundation

/// What the user chose for a merchant or keyword last time, so the next draft starts filled in.
/// Kept on the device; viewable and removable in Profil.
enum MerchantMemory {
    struct Entry: Codable, Equatable, Identifiable {
        var id: String { keyword + "|" + kind.rawValue }
        let keyword: String
        let kind: Draft.Kind
        var categoryId: String?
        var accountId: String?
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
