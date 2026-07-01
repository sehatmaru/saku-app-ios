import Foundation
import Supabase

enum SupabaseSDK {
    static let client = SupabaseClient(
        supabaseURL: URL(string: "https://tenopunaydfhtkpywldr.supabase.co")!,
        supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRlbm9wdW5heWRmaHRrcHl3bGRyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA5NTMzMjcsImV4cCI6MjA5NjUyOTMyN30.UtViSySycifdW09nTht1mt-8Oxkt30qattOa7SBO_gg"
    )

    static func fetchProfile(authUserId: UUID) async throws -> UserProfile {
        try await client
            .from("user_profiles")
            .select()
            .eq("auth_user_id", value: authUserId)
            .single()
            .execute()
            .value
    }

    static func updateProfile(id: UUID, displayName: String?) async throws {
        var payload: [String: AnyJSON] = [:]
        if let displayName {
            payload["display_name"] = AnyJSON.string(displayName)
        }
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
        return try await client
            .from("user_profiles")
            .upsert(payload)
            .select()
            .single()
            .execute()
            .value
    }
}

struct UserProfile: Codable, Identifiable {
    let id: UUID
    let authUserId: UUID
    let displayName: String?
    let defaultCurrencyCode: String
    let locale: String
    let timezone: String

    enum CodingKeys: String, CodingKey {
        case id
        case authUserId = "auth_user_id"
        case displayName = "display_name"
        case defaultCurrencyCode = "default_currency_code"
        case locale
        case timezone
    }
}

extension Notification.Name {
    static let dataDidChange = Notification.Name("com.sakuq.dataDidChange")
}
