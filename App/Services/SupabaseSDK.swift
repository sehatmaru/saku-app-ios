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
