import Foundation
import SwiftUI

/// Failures of the workspace calls the screens tell apart (TD T4 error codes).
enum WorkspaceError: Error, Equatable {
    case limit, guest, ownerDeleting, other

    init(_ error: Error) {
        let text = String(describing: error)
        if text.contains("space_limit") { self = .limit }
        else if text.contains("guest_not_allowed") { self = .guest }
        else if text.contains("space_owner_deleting") { self = .ownerDeleting }
        else { self = .other }
    }
}

/// The person's workspaces and the one the app is showing (K12, K13). Calls that are about the person, not about
/// one workspace, go through `SupabaseSDK.client` and carry no `x-saku-space` header.
@MainActor
final class WorkspaceStore: ObservableObject {
    static let shared = WorkspaceStore()

    @Published private(set) var spaces: [Workspace] = []
    @Published private(set) var activeId: UUID?
    @Published private(set) var hasLoaded = false
    @Published private(set) var loadFailed = false
    /// Counts switches; the app root uses it as an identity so the whole app reloads for the new workspace.
    @Published private(set) var epoch = 0
    /// A2: the default workspace was reset to Workspace Pribadi and this person has not been told yet.
    @Published var resetNotice = false
    /// Counts "make a workspace" requests; `WorkspaceHost` answers each one.
    @Published private(set) var createRequests = 0

    /// Members of the active shared Workspace, former ones included (K8, K17); empty in Workspace Pribadi.
    @Published private(set) var activeMembers: [WorkspaceMember] = []
    /// Rows show who recorded them only where more than one person can (K17).
    var showsAttribution: Bool { !activeIsPersonal && !activeMembers.isEmpty }
    func member(_ profileId: String?) -> WorkspaceMember? {
        guard let profileId, let id = UUID(uuidString: profileId) else { return nil }
        return activeMembers.first { $0.profileId == id }
    }

    /// Where Smart Tracker drafts land (K12, A1).
    var defaultWorkspace: Workspace? { spaces.first { $0.isDefault } ?? personal }
    var personal: Workspace? { spaces.first { $0.isPersonal } }
    var active: Workspace? { spaces.first { $0.id == activeId } ?? personal }
    var shared: [Workspace] { spaces.filter { !$0.isPersonal } }
    var owned: [Workspace] { shared.filter(\.isOwner) }
    /// Beranda shows the switcher only when there is something to switch to, or for testers and internal builds while this is not public (K30).
    var showsSwitcher: Bool { PlusStore.shared.isTester || PlusStore.isInternalBuild }
    var activeIsPersonal: Bool { active?.isPersonal ?? true }
    var canEditActive: Bool { activeIsPersonal || active?.isOwner == true }

    func requestCreate() { createRequests += 1 }

    func load() async {
        do {
            let rows: [Workspace] = try await SupabaseSDK.client.rpc("my_spaces").execute().value
            let before = SpaceStore.activeSpaceId
            spaces = rows
            loadFailed = false
            hasLoaded = true
            let home = rows.first(where: { $0.isDefault }) ?? rows.first(where: { $0.isPersonal })
            if let home { SpaceStore.setDefault(home.id.uuidString) }
            // the workspace in use is gone or hidden (left, removed, deleted): back to the default (K21)
            if let current = SpaceStore.activeSpaceId.flatMap(UUID.init(uuidString:)), !rows.contains(where: { $0.id == current }) {
                SpaceStore.setActive(nil)
            }
            activeId = SpaceStore.activeSpaceId.flatMap(UUID.init(uuidString:)) ?? home?.id
            if let active, !active.isPersonal, let day = active.paydayDay { PaydaySetting.day = day }
            if SpaceStore.activeSpaceId != before { reloadApp() }
            if rows.contains(where: { $0.defaultReset }) { resetNotice = true }
            await loadMembers()
        } catch {
            loadFailed = true
        }
    }

    /// Switches the whole app to `workspace`: new header, fresh caches, payday of that workspace.
    func open(_ workspace: Workspace) {
        guard workspace.id != activeId else { return }
        SpaceStore.setActive(workspace.id.uuidString)
        activeId = workspace.id
        PaydaySetting.day = workspace.paydayDay ?? 0
        activeMembers = []
        reloadApp()
        Task { await loadMembers() }
    }

    func loadMembers() async {
        guard let active, !active.isPersonal else { activeMembers = []; return }
        activeMembers = (try? await members(of: active)) ?? activeMembers
    }

    private func reloadApp() {
        AppDataCache.shared.clearAll()
        TransactionStore.shared.reset()
        PaydaySetting.schedule = []
        epoch += 1
        Task {
            await SupabaseSDK.refreshPaydaySchedule()
            await SupabaseSDK.refreshPaydayShifts()
        }
    }

    func create(name: String, icon: String, color: String, copyCategories: Bool, paydayDay: Int?) async throws -> Workspace {
        struct Params: Encodable, Sendable {
            let p_name: String, p_icon: String, p_color: String, p_category_source: String, p_payday_day: Int?
        }
        do {
            let id: UUID = try await SupabaseSDK.client.rpc("create_space", params: Params(
                p_name: name, p_icon: icon, p_color: color,
                p_category_source: copyCategories ? "copy_personal" : "default", p_payday_day: paydayDay)).execute().value
            await load()
            guard let made = spaces.first(where: { $0.id == id }) else { throw WorkspaceError.other }
            return made
        } catch let error as WorkspaceError {
            throw error
        } catch {
            throw WorkspaceError(error)
        }
    }

    func update(_ workspace: Workspace, name: String, icon: String, color: String) async throws {
        struct Params: Encodable, Sendable { let p_space: UUID, p_name: String, p_icon: String, p_color: String }
        do {
            try await SupabaseSDK.client.rpc("update_space", params: Params(p_space: workspace.id, p_name: name, p_icon: icon, p_color: color)).execute()
            await load()
        } catch { throw WorkspaceError(error) }
    }

    func setDefault(_ workspace: Workspace) async throws {
        do {
            try await SupabaseSDK.client.rpc("set_default_space", params: ["p_space": workspace.id]).execute()
            await load()
        } catch { throw WorkspaceError(error) }
    }

    // MARK: Invites and members (stage 3)

    /// The live code, or a new one. `renew` retires the live code first (K23).
    func invite(for workspace: Workspace, renew: Bool = false) async throws -> WorkspaceInvite {
        struct Params: Encodable, Sendable { let p_space: UUID, p_renew: Bool }
        do {
            let rows: [WorkspaceInvite] = try await SupabaseSDK.client.rpc("create_invite", params: Params(p_space: workspace.id, p_renew: renew)).execute().value
            guard let invite = rows.first else { throw WorkspaceError.other }
            return invite
        } catch { throw WorkspaceError(error) }
    }

    func revokeInvite(of workspace: Workspace) async throws {
        do { try await SupabaseSDK.client.rpc("revoke_invite", params: ["p_space": workspace.id]).execute() }
        catch { throw WorkspaceError(error) }
    }

    func preview(code: String) async throws -> InvitePreview {
        do {
            let rows: [InvitePreview] = try await SupabaseSDK.client.rpc("preview_invite", params: ["p_code": InviteCode.normalized(code)]).execute().value
            guard let row = rows.first else { throw WorkspaceError.other }
            return row
        } catch { throw WorkspaceError(error) }
    }

    /// Joins with a code. A refused code comes back as a status; `load()` runs so the new Workspace is in the list.
    func join(code: String) async throws -> JoinOutcome {
        do {
            let rows: [JoinOutcome] = try await SupabaseSDK.client.rpc("join_space", params: ["p_code": InviteCode.normalized(code)]).execute().value
            guard let row = rows.first else { throw WorkspaceError.other }
            if row.status == .joined || row.status == .alreadyMember { await load() }
            return row
        } catch { throw WorkspaceError(error) }
    }

    func members(of workspace: Workspace) async throws -> [WorkspaceMember] {
        do { return try await SupabaseSDK.client.rpc("space_members", params: ["p_space": workspace.id]).execute().value }
        catch { throw WorkspaceError(error) }
    }

    func leave(_ workspace: Workspace) async throws {
        do {
            try await SupabaseSDK.client.rpc("leave_space", params: ["p_space": workspace.id]).execute()
            await load()
        } catch { throw WorkspaceError(error) }
    }

    func remove(_ member: WorkspaceMember, from workspace: Workspace) async throws {
        struct Params: Encodable, Sendable { let p_space: UUID, p_profile: UUID }
        do { try await SupabaseSDK.client.rpc("remove_member", params: Params(p_space: workspace.id, p_profile: member.profileId)).execute() }
        catch { throw WorkspaceError(error) }
    }

    func transfer(_ workspace: Workspace, to member: WorkspaceMember) async throws {
        struct Params: Encodable, Sendable { let p_space: UUID, p_profile: UUID }
        do {
            try await SupabaseSDK.client.rpc("transfer_ownership", params: Params(p_space: workspace.id, p_profile: member.profileId)).execute()
            await load()
        } catch { throw WorkspaceError(error) }
    }

    /// Counts "join with a code" requests; `WorkspaceHost` answers each one.
    @Published private(set) var joinRequests = 0
    func requestJoin() { joinRequests += 1 }

    /// Back to the signed-out state: nothing of this account stays in memory.
    func reset() {
        spaces = []; activeId = nil; hasLoaded = false; loadFailed = false; resetNotice = false
    }
}
