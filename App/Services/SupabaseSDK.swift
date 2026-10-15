import Foundation
import Supabase

enum SupabaseSDK {
    static let client = SupabaseClient(
        supabaseURL: URL(string: "https://tenopunaydfhtkpywldr.supabase.co")!,
        supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRlbm9wdW5heWRmaHRrcHl3bGRyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA5NTMzMjcsImV4cCI6MjA5NjUyOTMyN30.UtViSySycifdW09nTht1mt-8Oxkt30qattOa7SBO_gg"
    )

    static func fetchProfile(authUserId: UUID) async throws -> UserProfile {
        let profile: UserProfile = try await client
            .from("user_profiles")
            .select()
            .eq("auth_user_id", value: authUserId)
            .single()
            .execute()
            .value
        PaydaySetting.day = profile.paydayDay
        HomeBalanceSetting.mode = profile.homeBalanceMode
        await syncSmartTrackerConsent(profile)
        SmartTrackerMemorySync.isGranted = profile.smartTrackerMemoryConsentAt != nil
        await refreshPaydaySchedule()
        await PlusStore.shared.apply(profile)
        return profile
    }

    /// US8: turns Saku Plus on or off for a tester account; the server refuses anyone else (`not_tester`).
    static func setTestPlus(_ on: Bool) async throws {
        try await client.rpc("set_test_plus", params: ["p_on": AnyJSON.bool(on)]).execute()
    }

    /// The profile decides. If this device agreed but saving failed earlier, the agreement is saved now.
    static func syncSmartTrackerConsent(_ profile: UserProfile) async {
        if let stamp = profile.smartTrackerConsentAt {
            SmartTrackerConsent.isGranted = true
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            SmartTrackerConsent.since = fractional.date(from: stamp) ?? ISO8601DateFormatter().date(from: stamp)
        } else if SmartTrackerConsent.isGranted {
            try? await recordSmartTrackerConsent(profileId: profile.id)
        }
    }

    /// Saves that the user agreed (now) and mirrors it on the device.
    static func recordSmartTrackerConsent(profileId: UUID) async throws {
        try await client
            .from("user_profiles")
            .update(["smart_tracker_consent_at": AnyJSON.string(ISO8601DateFormatter().string(from: Date()))] as [String: AnyJSON])
            .eq("id", value: profileId)
            .execute()
        SmartTrackerConsent.isGranted = true
        SmartTrackerConsent.since = Date()
    }

    /// Withdraws the agreement: saved on the profile first, then mirrored on the device.
    static func revokeSmartTrackerConsent(profileId: UUID) async throws {
        try await client
            .from("user_profiles")
            .update(["smart_tracker_consent_at": AnyJSON.null] as [String: AnyJSON])
            .eq("id", value: profileId)
            .execute()
        SmartTrackerConsent.isGranted = false
    }

    // MARK: Ingatan sync

    /// Saves that the user agreed to keeping Ingatan on the server, and mirrors it on the device.
    static func recordMemorySyncConsent(profileId: UUID) async throws {
        try await client
            .from("user_profiles")
            .update(["smart_tracker_memory_consent_at": AnyJSON.string(ISO8601DateFormatter().string(from: Date()))] as [String: AnyJSON])
            .eq("id", value: profileId)
            .execute()
        SmartTrackerMemorySync.isGranted = true
    }

    static func revokeMemorySyncConsent(profileId: UUID) async throws {
        try await client
            .from("user_profiles")
            .update(["smart_tracker_memory_consent_at": AnyJSON.null] as [String: AnyJSON])
            .eq("id", value: profileId)
            .execute()
        SmartTrackerMemorySync.isGranted = false
    }

    private struct MemoryRow: Codable {
        let keyword: String
        let kind: String
        let categoryId: String?
        let accountId: String?
        let uses: Int
        let updatedAt: String
        let deletedAt: String?

        enum CodingKeys: String, CodingKey {
            case keyword, kind, uses
            case categoryId = "category_id"
            case accountId = "account_id"
            case updatedAt = "updated_at"
            case deletedAt = "deleted_at"
        }
    }

    private static func memoryDate(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    private static func memoryString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// Every Ingatan row of the signed-in user, tombstones included.
    static func fetchMemory() async throws -> [MerchantMemory.Entry] {
        let rows: [MemoryRow] = try await client.from("merchant_memory").select().execute().value
        return rows.compactMap { row in
            guard let kind = Draft.Kind(rawValue: row.kind), let updated = memoryDate(row.updatedAt) else { return nil }
            var entry = MerchantMemory.Entry(keyword: row.keyword, kind: kind, categoryId: row.categoryId, accountId: row.accountId,
                                             uses: row.uses, updatedAt: updated)
            entry.deletedAt = row.deletedAt.flatMap(memoryDate)
            return entry
        }
    }

    /// Sends entries to the server; it keeps whichever version is newer.
    static func pushMemory(_ entries: [MerchantMemory.Entry]) async throws {
        guard !entries.isEmpty else { return }
        let rows: [AnyJSON] = entries.map { entry in
            var object: [String: AnyJSON] = [
                "keyword": .string(entry.keyword),
                "kind": .string(entry.kind.rawValue),
                "uses": .integer(entry.uses),
                "updated_at": .string(memoryString(entry.updatedAt)),
            ]
            if let id = entry.categoryId { object["category_id"] = .string(id) }
            if let id = entry.accountId { object["account_id"] = .string(id) }
            if let deleted = entry.deletedAt { object["deleted_at"] = .string(memoryString(deleted)) }
            return .object(object)
        }
        try await client.rpc("upsert_merchant_memory", params: ["p_rows": AnyJSON.array(rows)]).execute()
    }

    /// "Lupakan semua" on the server: everything changed up to `before`.
    static func forgetAllMemory(before: Date) async throws {
        try await client.rpc("forget_all_merchant_memory", params: ["p_before": AnyJSON.string(memoryString(before))]).execute()
    }

    private struct PaydayChangeRow: Decodable {
        let paydayDay: Int
        let effectiveFrom: String
        enum CodingKeys: String, CodingKey { case paydayDay = "payday_day", effectiveFrom = "effective_from" }
    }

    /// Mirrors `payday_changes` on the device. Keeps the old schedule when offline.
    static func refreshPaydaySchedule() async {
        guard let rows: [PaydayChangeRow] = try? await client
            .from("payday_changes").select().order("effective_from").execute().value else { return }
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd"
        format.locale = Locale(identifier: "en_US_POSIX")
        PaydaySetting.schedule = rows.compactMap { row in
            format.date(from: row.effectiveFrom).map { PaydayEntry(day: row.paydayDay, from: $0) }
        }
    }

    /// Asks to delete the signed-in account. It is scheduled 30 days out (the server returns the date); `reason`
    /// and `note` are the optional survey answer and are stored without any link to the user.
    static func requestAccountDeletion(reason: String?, note: String?) async throws -> Date {
        var params: [String: AnyJSON] = [:]
        if let reason { params["p_reason"] = .string(reason) }
        if let note, !note.isEmpty { params["p_note"] = .string(note) }
        let raw: String = try await client.rpc("request_account_deletion", params: params).execute().value
        guard let date = AccountDeletion.parse(raw) else { throw URLError(.cannotParseResponse) }
        return date
    }

    /// Signing in during the wait and choosing "Batalkan".
    static func cancelAccountDeletion() async throws {
        try await client.rpc("cancel_account_deletion").execute()
    }

    /// Saves the payday (1–31). The server decides when it takes effect (now for early corrections,
    /// else the end of the running period) and returns that date.
    @discardableResult
    static func updatePayday(day: Int) async throws -> Date {
        let day = min(max(day, 1), 31)
        let effective: String = try await client.rpc("set_payday", params: ["p_day": day]).execute().value
        PaydaySetting.day = day
        await refreshPaydaySchedule()
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd"
        format.locale = Locale(identifier: "en_US_POSIX")
        return format.date(from: effective) ?? Date()
    }

    /// Drops a payday change that has not taken effect yet.
    static func cancelPendingPayday() async throws {
        try await client.rpc("cancel_pending_payday").execute()
        await refreshPaydaySchedule()
        PaydaySetting.day = PaydayCycle.current.day
    }

    /// Saves what Beranda's "Total saldo" adds up and mirrors it on the device.
    static func updateHomeBalanceMode(profileId: UUID, mode: HomeBalanceMode) async throws {
        try await client
            .from("user_profiles")
            .update(["home_balance_mode": AnyJSON.string(mode.rawValue)] as [String: AnyJSON])
            .eq("id", value: profileId)
            .execute()
        HomeBalanceSetting.mode = mode.rawValue
    }

    /// Uploads the JPEG to `avatars/<auth uid>/avatar.jpg` (overwriting) and returns its public URL.
    /// The `v` query busts the image cache, since the path never changes.
    static func uploadAvatar(authUserId: UUID, jpeg: Data) async throws -> String {
        let path = "\(authUserId.uuidString.lowercased())/avatar.jpg"
        let bucket = client.storage.from("avatars")
        try await bucket.upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg", upsert: true))
        let url = try bucket.getPublicURL(path: path)
        return "\(url.absoluteString)?v=\(Int(Date().timeIntervalSince1970))"
    }

    static func updateProfile(id: UUID, displayName: String?, avatarURL: String? = nil) async throws {
        var payload: [String: AnyJSON] = [:]
        if let displayName {
            payload["display_name"] = AnyJSON.string(displayName)
        }
        if let avatarURL {
            payload["avatar_url"] = AnyJSON.string(avatarURL)
        }
        guard !payload.isEmpty else { return }
        try await client
            .from("user_profiles")
            .update(payload)
            .eq("id", value: id)
            .execute()
    }

    static func upsertProfile(authUserId: UUID, displayName: String) async throws -> UserProfile {
        let payload: [String: AnyJSON] = [
            "auth_user_id": AnyJSON.string(authUserId.uuidString),
            "display_name": AnyJSON.string(displayName),
            "default_currency_code": AnyJSON.string("IDR"),
            "locale": AnyJSON.string("id"),
            "timezone": AnyJSON.string("Asia/Jakarta"),
        ]
        let profile: UserProfile = try await client
            .from("user_profiles")
            .upsert(payload)
            .select()
            .single()
            .execute()
            .value
        PaydaySetting.day = profile.paydayDay
        HomeBalanceSetting.mode = profile.homeBalanceMode
        return profile
    }
}

struct UserProfile: Codable, Identifiable {
    let id: UUID
    let authUserId: UUID
    let displayName: String?
    let defaultCurrencyCode: String
    let locale: String
    let timezone: String
    /// Payday (1–31); nil until the user sets it.
    var paydayDay: Int? = nil
    var avatarUrl: String? = nil
    /// "cash" or "all"; nil reads as cash.
    var homeBalanceMode: String? = nil
    /// When the user agreed to Smart Tracker; nil until then.
    var smartTrackerConsentAt: String? = nil
    /// When the user agreed to keeping Ingatan on the server; nil until then.
    var smartTrackerMemoryConsentAt: String? = nil
    /// When a requested deletion becomes permanent; nil for an account not waiting to be deleted.
    var deletionScheduledFor: String? = nil
    /// Saku Plus: free, trial, active or grace; nil until the server has the columns.
    var plusStatus: String? = nil
    var plusUntil: String? = nil
    /// Tester accounts may use the internal Plus switch.
    var isTester: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case authUserId = "auth_user_id"
        case displayName = "display_name"
        case defaultCurrencyCode = "default_currency_code"
        case locale
        case timezone
        case paydayDay = "payday_day"
        case avatarUrl = "avatar_url"
        case homeBalanceMode = "home_balance_mode"
        case smartTrackerConsentAt = "smart_tracker_consent_at"
        case smartTrackerMemoryConsentAt = "smart_tracker_memory_consent_at"
        case deletionScheduledFor = "deletion_scheduled_for"
        case plusStatus = "plus_status"
        case plusUntil = "plus_until"
        case isTester = "is_tester"
    }
}

extension Notification.Name {
    static let dataDidChange = Notification.Name("com.saku.dataDidChange")
}
