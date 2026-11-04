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
        case unavailable(Fallback)
    }

    /// Why the rules had to read it instead of AI; the word is shown on the draft ("Dibaca tanpa AI").
    enum Fallback: Equatable {
        case offline, failed, slow, quota

        var reason: String {
            switch self {
            case .offline: L("tidak ada koneksi")
            case .failed: L("AI gagal membaca")
            case .slow: L("AI terlalu lama")
            case .quota: L("jatah habis")
            }
        }
    }

    /// How long the screen waits for AI before the rules' reading is used.
    static let timeout: Duration = .seconds(4)

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

    /// Whether AI may read: the switch is on and this is a real account (guests stay on the rules).
    @MainActor static var isAvailable: Bool { SmartTrackerConsent.isGranted && !DraftStore.shared.isGuest }

    static func parse(_ text: String, source: Draft.Source, context: SmartParser.Context) async -> Outcome {
        await withTaskGroup(of: Outcome.self) { group in
            group.addTask { await request(text, source: source, context: context) }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .unavailable(.slow)
            }
            let first = await group.next() ?? .unavailable(.failed)
            group.cancelAll()
            return first
        }
    }

    private static func request(_ text: String, source: Draft.Source, context: SmartParser.Context) async -> Outcome {
        let payload: [String: AnyJSON] = [
            "text": .string(SmartTextScrubber.clean(text)),
            "wallets": .array(context.accounts.filter(\.isActive).map { .string($0.name) }),
            "categories": .array(context.categories.filter { !CategoryCatalog.isSystem($0) }.map { .string($0.name) }),
            "today": .string(ISO8601DateFormatter().string(from: context.now)),
        ]
        let reply: Reply
        do {
            reply = try await SupabaseSDK.client.functions.invoke("smart-parse", options: FunctionInvokeOptions(body: payload))
        } catch FunctionsError.httpError(let code, _) where code == 402 {
            Task { @MainActor in await AIQuotaStore.shared.refresh() }
            return .outOfQuota
        } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
            return .unavailable(.offline)
        } catch is CancellationError {
            return .unavailable(.slow)
        } catch {
            return .unavailable(.failed)
        }
        // the allowance refreshes after the answer is on screen, not inside the 4 s wait
        Task { @MainActor in await AIQuotaStore.shared.refresh() }
        let drafts = reply.drafts.compactMap { item -> Draft? in
            guard let amount = item.amount, amount > 0, let kind = Draft.Kind(rawValue: item.kind) else { return nil }
            var draft = Draft()
            draft.kind = kind
            draft.amount = amount
            draft.title = item.title ?? ""
            draft.source = source
            draft.reader = .ai
            draft.accountId = context.accounts.first { $0.name == item.wallet }?.id
            draft.counterpartyAccountId = context.accounts.first { $0.name == item.toWallet }?.id
            draft.categoryId = context.categories.first { $0.name == item.category }?.id
            draft.date = Calendar.current.date(byAdding: .day, value: -(item.daysAgo ?? 0), to: context.now) ?? context.now
            MerchantMemory.override(&draft, text: text, context: context)
            return draft
        }
        return drafts.isEmpty ? .unavailable(.failed) : .drafts(drafts)
    }
}
