import Foundation

/// A transaction waiting to be checked ("Perlu dicek"). Nothing is saved until the user agrees.
/// Drafts live on the device (JSON file); the raw sentence is never stored, only what was understood.
struct Draft: Identifiable, Codable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case expense, income
        /// Between two wallets, including top ups and deposits into an investment wallet.
        case transfer
        /// A card bill paid from outside Saku.
        case cardPayment
    }

    enum Source: String, Codable {
        case typed, voice, siri, share, notification
    }

    var id = UUID()
    var kind: Kind = .expense
    var amount: Double?
    /// What the user called it ("Kopi"); for unreadable input, their own words.
    var title = ""
    /// The wallet money leaves (expense, transfer, card payment) or arrives in (income).
    var accountId: String?
    /// Transfer destination (a wallet or investment wallet); the card for a card payment.
    var counterpartyAccountId: String?
    var categoryId: String?
    var date = Date()
    var source: Source = .typed
    var createdAt = Date()
    /// Learned from this keyword/merchant, shown so the user can see why a field is filled.
    var merchant: String?
    /// Category or wallet came from what Saku remembered (shown as "Ingatan").
    var fromMemory = false
    /// Where it came from in words, e.g. the bank app of a notification ("BCA").
    var sourceName: String?
    /// "Mirip dengan transaksi …" warning from the duplicate check.
    var duplicateNote: String?
    /// The sentence could not be understood; `title` holds the original text.
    var isUnreadable = false
    /// Investment deposit wanted but no investment wallet to receive it.
    var needsInvestmentWallet = false

    var expiresAt: Date { Calendar.current.date(byAdding: .day, value: 30, to: createdAt) ?? createdAt }

    /// What still blocks saving, in the order the editor asks for it.
    enum Missing: Equatable { case amount, account, counterparty, category }

    var missing: [Missing] {
        var result: [Missing] = []
        if (amount ?? 0) <= 0 { result.append(.amount) }
        // a card bill with no source wallet was paid outside Saku; it only lowers the card's debt
        if accountId == nil && kind != .cardPayment { result.append(.account) }
        if (kind == .transfer || kind == .cardPayment) && counterpartyAccountId == nil { result.append(.counterparty) }
        if (kind == .expense || kind == .income) && categoryId == nil { result.append(.category) }
        return result
    }

    /// Ready for one-tap save; "Simpan semua" only takes these.
    var isComplete: Bool { missing.isEmpty && !isUnreadable }
}
