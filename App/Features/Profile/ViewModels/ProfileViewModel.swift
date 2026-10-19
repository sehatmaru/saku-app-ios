import UIKit

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var displayName: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    func loadProfile(from user: User?) {
        displayName = user?.displayName ?? ""
    }

    /// Saves the name and, when `photo` is set, uploads it first; `removePhoto` clears the avatar.
    /// Returns the updated user.
    /// `name` saves that name instead of the field's (a photo change saves on its own and leaves a half-typed name alone).
    func saveProfile(user: User?, photo: UIImage?, removePhoto: Bool = false, name: String? = nil) async -> User? {
        errorMessage = nil
        if name == nil { displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines) }
        let displayName = name ?? self.displayName
        guard !displayName.isEmpty else {
            errorMessage = L("Nama tidak boleh kosong")
            return nil
        }
        guard let currentUser = user, let authUserId = UUID(uuidString: currentUser.authUserId) else { return nil }
        isLoading = true
        defer { isLoading = false }

        do {
            let profile = try await SupabaseSDK.fetchProfile(authUserId: authUserId)
            var avatarURL: String?
            if let jpeg = photo.flatMap(Self.avatarJPEG) {
                avatarURL = try await SupabaseSDK.uploadAvatar(authUserId: authUserId, jpeg: jpeg)
            } else if removePhoto {
                // "Hapus foto": store it empty rather than keeping the old one
                avatarURL = ""
            }
            try await SupabaseSDK.updateProfile(id: profile.id, displayName: displayName, avatarURL: avatarURL)
            return User(
                id: currentUser.id,
                authUserId: currentUser.authUserId,
                email: currentUser.email,
                displayName: displayName,
                defaultCurrencyCode: currentUser.defaultCurrencyCode,
                avatarURL: avatarURL ?? currentUser.avatarURL
            )
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Centre-crops to a 512 px square and compresses (~50–100 KB), well under the 1 MB bucket limit.
    private static func avatarJPEG(_ image: UIImage) -> Data? {
        let side = min(image.size.width, image.size.height)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let target = CGSize(width: 512, height: 512)
        let scaled = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            let k = target.width / side
            let size = CGSize(width: image.size.width * k, height: image.size.height * k)
            image.draw(in: CGRect(x: (target.width - size.width) / 2, y: (target.height - size.height) / 2,
                                  width: size.width, height: size.height))
        }
        return scaled.jpegData(compressionQuality: 0.8)
    }
}
