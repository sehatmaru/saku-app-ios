import Foundation

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var displayName: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    func loadProfile(from user: User?) {
        displayName = user?.displayName ?? ""
    }

    func saveDisplayName(user: User?) async -> User? {
        guard let currentUser = user, let authUserId = UUID(uuidString: currentUser.authUserId) else { return nil }
        isLoading = true
        defer { isLoading = false }

        do {
            let profile = try await SupabaseSDK.fetchProfile(authUserId: authUserId)
            try await SupabaseSDK.updateProfile(id: profile.id, displayName: displayName.isEmpty ? nil : displayName)
            return User(
                id: currentUser.id,
                authUserId: currentUser.authUserId,
                email: currentUser.email,
                displayName: displayName.isEmpty ? currentUser.displayName : displayName,
                defaultCurrencyCode: currentUser.defaultCurrencyCode
            )
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
