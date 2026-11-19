import Foundation

/// One row of `space_members(space)`: an active or former member of a Workspace (K8).
struct WorkspaceMember: Identifiable, Equatable, Decodable, Sendable {
    let profileId: UUID
    let displayName: String?
    let avatarUrl: String?
    let role: String
    let leftAt: String?
    let isMe: Bool

    var id: UUID { profileId }
    var isOwner: Bool { role == "owner" }
    var isFormer: Bool { leftAt != nil }
    var name: String { displayName?.trimmingCharacters(in: .whitespaces).isEmpty == false ? displayName! : L("Tanpa nama") }
    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }
    var initial: String { String(name.prefix(1)).uppercased() }

    enum CodingKeys: String, CodingKey {
        case profileId = "profile_id", displayName = "display_name", avatarUrl = "avatar_url", role
        case leftAt = "left_at", isMe = "is_me"
    }
}

/// The live invite code of a Workspace (`create_invite`).
struct WorkspaceInvite: Equatable, Decodable, Sendable {
    let code: String
    let expiresAt: String

    enum CodingKeys: String, CodingKey { case code, expiresAt = "expires_at" }

    var expiryDate: Date? { Workspace.parseTimestamp(expiresAt) }
}

/// What the server says about a code: usable, or why not. Refused codes come back as a status, not an error (M3c).
enum InviteStatus: String, Decodable, Sendable {
    case ok, joined, alreadyMember = "already_member", invalid, expired, revoked, full, rateLimited = "rate_limited", closed

    /// The line shown to someone whose code did not work; nil when it did.
    var problem: String? {
        switch self {
        case .ok, .joined: nil
        case .alreadyMember: L("Kamu sudah menjadi anggota Workspace ini.")
        case .invalid: L("Kode tidak ditemukan. Periksa lagi kodenya.")
        case .expired: L("Kode sudah kedaluwarsa. Minta kode baru ke Pemilik.")
        case .revoked: L("Kode sudah dicabut. Minta kode baru ke Pemilik.")
        case .full: L("Workspace ini sudah penuh, maksimal 5 anggota.")
        case .rateLimited: L("Terlalu banyak percobaan. Coba lagi satu jam lagi.")
        case .closed: L("Workspace ini sedang tidak menerima anggota baru.")
        }
    }
}

struct InvitePreview: Equatable, Decodable, Sendable {
    let status: InviteStatus
    let spaceId: UUID?
    let name: String?
    let icon: String?
    let color: String?
    let ownerName: String?
    let memberCount: Int?
    let imageUrl: String?

    enum CodingKeys: String, CodingKey {
        case status, name, icon, color
        case imageUrl = "image_url"
        case spaceId = "space_id", ownerName = "owner_name", memberCount = "member_count"
    }
}

struct JoinOutcome: Equatable, Decodable, Sendable {
    let status: InviteStatus
    let spaceId: UUID?

    enum CodingKeys: String, CodingKey { case status, spaceId = "space_id" }
}

/// Invite codes have 8 characters; people type them in any case, with spaces or dashes (TD 6.1).
enum InviteCode {
    static let length = 8

    static func normalized(_ raw: String) -> String {
        String(raw.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(length))
    }

    static func isComplete(_ raw: String) -> Bool { normalized(raw).count == length }

    /// "ABCD EFGH": the way the code is shown and shared.
    static func grouped(_ raw: String) -> String {
        let code = normalized(raw)
        guard code.count > 4 else { return code }
        return code.prefix(4) + " " + code.dropFirst(4)
    }
}
