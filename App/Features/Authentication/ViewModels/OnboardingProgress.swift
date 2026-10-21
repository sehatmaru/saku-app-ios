import Foundation

/// Notes on this device that the first-run setup finished for an account.
///
/// A session restored while setup never finished must not open the app (BUG-43):
/// the marker is missing and the profile still has no wallets, so RootView shows
/// SetupOnboardingView again instead of an empty dashboard.
enum OnboardingProgress {
    private static let keyPrefix = "setupCompleted."

    private static func key(for authUserId: UUID) -> String {
        keyPrefix + authUserId.uuidString
    }

    static func isComplete(authUserId: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: key(for: authUserId))
    }

    static func markComplete(authUserId: UUID) {
        UserDefaults.standard.set(true, forKey: key(for: authUserId))
    }

    /// Whether setup should be shown after the session is restored.
    /// `accountCount` is nil when the server could not be asked: never keep a
    /// signed-in user out of the app on a guess.
    static func needsSetup(markedComplete: Bool, accountCount: Int?) -> Bool {
        guard !markedComplete else { return false }
        guard let accountCount else { return false }
        return accountCount == 0
    }
}
