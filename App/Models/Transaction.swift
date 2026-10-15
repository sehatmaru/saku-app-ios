import Foundation

struct Transaction: Identifiable, Codable {
    let id: String
    let accountId: String
    let counterpartyAccountId: String?
    let categoryId: String?
    let amount: Double
    let type: TransactionType
    let description: String?
    let note: String?
    let date: Date
    let delta: Double?
    /// The client operation id; recurring bills post as `sub_<subscription>_<date>`.
    var clientReferenceId: String? = nil

    enum TransactionType: String, Codable {
        case income = "income"
        case expense = "expense"
        case transfer = "transfer"
        case adjustment = "adjustment"
        /// A card bill paid from outside Saku: lowers the card's debt, moves no wallet.
        case cardPayment = "card_payment"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case accountId = "primary_account_id"
        case counterpartyAccountId = "counterparty_account_id"
        case categoryId = "category_id"
        case amount
        case type = "transaction_type"
        case description
        case note
        case date = "occurred_at"
        case delta
        case clientReferenceId = "client_reference_id"
    }

    /// The "Catatan" the user typed (saved as `description`), else the system `note`.
    var displayNote: String? {
        [description, note].lazy.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
    }

    /// Search by what a row shows: the note text or the category name.
    func matches(search query: String, categoryName: String?) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        return [description, note, categoryName].contains { $0?.localizedCaseInsensitiveContains(q) == true }
    }

    /// Posted automatically from a recurring bill when its date arrived.
    var isRecurring: Bool { clientReferenceId?.hasPrefix("sub_") == true }

    /// "Spotify" out of the "Tagihan berulang: Spotify" note the auto-posting writes.
    var recurringName: String? {
        guard isRecurring, let note else { return nil }
        let prefix = "Tagihan berulang: "
        return note.hasPrefix(prefix) ? String(note.dropFirst(prefix.count)) : note
    }
}

extension Sequence where Element == Transaction {
    /// Newest day first. Transactions on the same day keep the order they came in, which is
    /// newest-created first (the fetch orders by `created_at`): a day has no time of day.
    func newestFirst() -> [Transaction] {
        enumerated()
            .sorted { $0.element.date != $1.element.date ? $0.element.date > $1.element.date : $0.offset < $1.offset }
            .map(\.element)
    }
}
