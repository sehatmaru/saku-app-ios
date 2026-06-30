import Foundation
import Supabase

enum SupabaseSDK {
    static let client = SupabaseClient(
        supabaseURL: URL(string: "https://tenopunaydfhtkpywldr.supabase.co")!,
        supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRlbm9wdW5heWRmaHRrcHl3bGRyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA5NTMzMjcsImV4cCI6MjA5NjUyOTMyN30.UtViSySycifdW09nTht1mt-8Oxkt30qattOa7SBO_gg"
    )

    static func signInWithGoogle(idToken: String, accessToken: String) async throws -> AuthResult {
        let response = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .google,
                idToken: idToken,
                accessToken: accessToken
            )
        )
        let supaUser = response.user
        return AuthResult(
            id: supaUser.id.uuidString,
            email: supaUser.email ?? "",
            fullName: supaUser.userMetadata["full_name"]?.stringValue
                ?? supaUser.userMetadata["name"]?.stringValue
                ?? ""
        )
    }
}

struct AuthResult {
    let id: String
    let email: String
    let fullName: String
}