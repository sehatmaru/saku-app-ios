import Foundation
import Supabase

/// Asks the `smart-parse` Edge Function (a language model) to read a sentence the on-device rules could not.
/// Sends only the sentence, wallet and category names and today's date. Any failure just returns nil and the
/// draft stays as the rules made it (the user's own words in the note), so offline and errors are never fatal.
enum RemoteSmartParser {
    /// What the server answered: drafts, "this month's AI help is used up" (HTTP 402), or nothing usable.
    enum Outcome: Equatable {
        case drafts([Draft])
        case outOfQuota
        case unavailable
    }

    /// Shown on the draft the user fills in by hand when the monthly AI help is used up.
    static var outOfQuotaNote: String { L("Jatah bantuan AI bulan ini habis. Isi manual.") }

    private struct Reply: Decodable {
        struct Item: Decodable {
            let kind: String
            let amount: Double?
            let title: String?
            let wallet: String?
            let toWallet: String?
            let category: String?
            let daysAgo: Int?
        }
        let drafts: [Item]
    }

    static func parse(_ text: String, source: Draft.Source, context: SmartParser.Context) async -> Outcome {
        let payload: [String: AnyJSON] = [
            "text": .string(text),
            "wallets": .array(context.accounts.filter(\.isActive).map { .string($0.name) }),
            "categories": .array(context.categories.filter { !CategoryCatalog.isSystem($0) }.map { .string($0.name) }),
            "today": .string(ISO8601DateFormatter().string(from: context.now)),
        ]
        let reply: Reply
        do {
            reply = try await SupabaseSDK.client.functions.invoke("smart-parse", options: FunctionInvokeOptions(body: payload))
        } catch FunctionsError.httpError(let code, _) where code == 402 {
            return .outOfQuota
        } catch {
            return .unavailable
        }
        let drafts = reply.drafts.compactMap { item -> Draft? in
            guard let amount = item.amount, amount > 0, let kind = Draft.Kind(rawValue: item.kind) else { return nil }
            var draft = Draft()
            draft.kind = kind
            draft.amount = amount
            draft.title = item.title ?? ""
            draft.source = source
            draft.accountId = context.accounts.first { $0.name == item.wallet }?.id
            draft.counterpartyAccountId = context.accounts.first { $0.name == item.toWallet }?.id
            draft.categoryId = context.categories.first { $0.name == item.category }?.id
            draft.date = Calendar.current.date(byAdding: .day, value: -(item.daysAgo ?? 0), to: context.now) ?? context.now
            return draft
        }
        return drafts.isEmpty ? .unavailable : .drafts(drafts)
    }
}
