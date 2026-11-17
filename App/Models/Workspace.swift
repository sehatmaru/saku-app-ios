import Foundation

/// One row of `my_spaces()`: a workspace the person can open, with their role in it (TD T3).
struct Workspace: Identifiable, Equatable, Decodable, Sendable {
    let id: UUID
    let kind: String
    /// Null for Workspace Pribadi: the app names it.
    let name: String?
    let icon: String?
    let color: String?
    let role: String
    let ownerId: UUID?
    let ownerName: String?
    let memberCount: Int
    let isReadOnly: Bool
    let isDefault: Bool
    /// The default workspace was reset to Workspace Pribadi by the server (A2): tell the person once.
    let defaultReset: Bool
    let deletionScheduledFor: String?
    let paydayDay: Int?

    enum CodingKeys: String, CodingKey {
        case id, kind, name, icon, color, role
        case ownerId = "owner_id", ownerName = "owner_name", memberCount = "member_count"
        case isReadOnly = "is_read_only", isDefault = "is_default", defaultReset = "default_reset"
        case deletionScheduledFor = "deletion_scheduled_for", paydayDay = "payday_day"
    }

    var isPersonal: Bool { kind == "personal" }
    var isOwner: Bool { role == "owner" }

    /// Workspace Pribadi is named by the app so it follows the language; shared ones keep the name their Owner typed.
    var displayName: String { isPersonal ? L("Workspace Pribadi") : (name ?? "") }

    /// Days left until the workspace is deleted, rounded up so a fresh request reads 7. Nil when not waiting for deletion.
    var daysUntilDeletion: Int? {
        guard let raw = deletionScheduledFor, let date = Self.parseTimestamp(raw) else { return nil }
        return max(0, Int((date.timeIntervalSinceNow / 86_400).rounded(.up)))
    }

    static func parseTimestamp(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }
}
