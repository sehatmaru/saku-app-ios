import Foundation

/// Switches for tools that only make sense while the app is in development and testing.
enum DevTools {
    /// Profil › "Hapus akun & data": deletes the account and everything under it (needs the
    /// `delete_my_account` function on the backend). Turn off, and drop the function, before release.
    static let isAccountResetEnabled = true
}
