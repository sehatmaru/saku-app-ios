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
        await refreshPaydaySchedule()
        return profile
    }

    /// The profile decides. If this device agreed but saving failed earlier, the agreement is saved now.
    static func syncSmartTrackerConsent(_ profile: UserProfile) async {
        if profile.smartTrackerConsentAt != nil {
            SmartTrackerConsent.isGranted = true
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

    /// Development tool: deletes the signed-in account and all its data on the server.
    static func deleteMyAccount() async throws {
        try await client.rpc("delete_my_account").execute()
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
    }
}

extension Notification.Name {
    static let dataDidChange = Notification.Name("com.saku.dataDidChange")
}
