import Foundation
import os
import Supabase

/// The workspace every data request belongs to (TD T5). Stage 1: always the person's own Workspace Pribadi, taken from
/// the profile's `default_space_id`. The id is kept in the App Group so Siri/Shortcuts, which can run before the profile
/// is fetched, send the same header. With no id the server falls back to Workspace Pribadi by itself.
enum SpaceStore {
    static let headerName = "x-saku-space"
    private static let key = "activeSpaceId"
    private static let cache = OSAllocatedUnfairLock<String??>(initialState: .none)

    private static var defaults: UserDefaults { UserDefaults(suiteName: ShareInbox.appGroup) ?? .standard }

    /// Lowercase UUID string, or nil when `raw` is not a UUID (the server refuses anything else with `space_header_invalid`).
    static func normalized(_ raw: String?) -> String? {
        raw.flatMap { UUID(uuidString: $0)?.uuidString.lowercased() }
    }

    /// The workspace opened at launch (profile choice, K12). Kept in the App Group: Siri and Shortcuts can run before the profile loads.
    static var defaultSpaceId: String? {
        if let known = cache.withLock({ $0 }) { return known }
        let saved = normalized(defaults.string(forKey: key))
        cache.withLock { $0 = .some(saved) }
        return saved
    }

    /// Chosen in the switcher; lives only in memory, so the next launch opens the default again.
    private static let session = OSAllocatedUnfairLock<String?>(initialState: nil)

    /// A request that must go to one workspace whichever is open (Smart Tracker drafts, K12): set around the calls with `$override.withValue`.
    @TaskLocal static var override: String?

    /// The workspace in use; nil means "let the server pick the person's Workspace Pribadi".
    static var activeSpaceId: String? { session.withLock { $0 } ?? defaultSpaceId }

    static func setDefault(_ id: String?) {
        let value = normalized(id)
        cache.withLock { $0 = .some(value) }
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    /// Switches the app to `id` for this run; nil goes back to the default.
    static func setActive(_ id: String?) { session.withLock { $0 = normalized(id) } }

    /// Sign-out, account switch or deletion: nothing of the old account may steer the next request.
    static func clear() { setActive(nil); setDefault(nil) }

    /// The server refused the workspace (not a member any more, or it is gone). The caller falls back to Workspace Pribadi.
    static func isSpaceError(_ error: Error) -> Bool {
        let text = String(describing: error)
        return text.contains("space_forbidden") || text.contains("space_header_invalid")
    }

    /// A.2: on such an error, forget the workspace so the next request lands in Workspace Pribadi. True when it did.
    @discardableResult
    static func recover(from error: Error) -> Bool {
        guard isSpaceError(error) else { return false }
        clear()
        return true
    }
}

/// `from()` and `rpc()` of the Supabase client with the `x-saku-space` header added. Used for everything that belongs to a
/// workspace (wallets, transactions, budgets, categories, payday). Personal calls (profile, Plus, referral, AI quota,
/// merchant memory, account deletion, storage, functions) keep using `SupabaseSDK.client` and send no header.
struct SpaceClient: Sendable {
    let base: SupabaseClient

    func from(_ table: String) -> PostgrestQueryBuilder {
        let builder = base.from(table)
        if let id = SpaceStore.override ?? SpaceStore.activeSpaceId { builder.setHeader(name: SpaceStore.headerName, value: id) }
        return builder
    }

    func rpc(_ fn: String) throws -> PostgrestFilterBuilder {
        let builder = try base.rpc(fn)
        if let id = SpaceStore.override ?? SpaceStore.activeSpaceId { builder.setHeader(name: SpaceStore.headerName, value: id) }
        return builder
    }

    func rpc(_ fn: String, params: some Encodable & Sendable) throws -> PostgrestFilterBuilder {
        let builder = try base.rpc(fn, params: params)
        if let id = SpaceStore.override ?? SpaceStore.activeSpaceId { builder.setHeader(name: SpaceStore.headerName, value: id) }
        return builder
    }
}
