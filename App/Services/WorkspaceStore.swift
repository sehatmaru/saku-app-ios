import Foundation
import SwiftUI

/// Failures of the workspace calls the screens tell apart (TD T4 error codes).
enum WorkspaceError: Error, Equatable {
    case limit, guest, ownerDeleting, ownerMustTransfer, walletLimit, notMovable, readOnly, mapInvalid, other

    init(_ error: Error) {
        let text = String(describing: error)
        if text.contains("space_limit") { self = .limit }
        else if text.contains("guest_not_allowed") { self = .guest }
        else if text.contains("space_owner_deleting") { self = .ownerDeleting }
        else if text.contains("space_owner_must_transfer") { self = .ownerMustTransfer }
        else if text.contains("wallet_limit") { self = .walletLimit }
        else if text.contains("account_not_movable") || text.contains("account_card_not_movable") { self = .notMovable }
        else if text.contains("space_read_only") { self = .readOnly }
        else if text.contains("merge_map_invalid") || text.contains("space_forbidden") { self = .mapInvalid }
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
    /// Beranda shows the switcher only for testers and internal builds until Workspace opens for everyone, after stage 7 (K30).
    var showsSwitcher: Bool { PlusStore.shared.isTester || PlusStore.isInternalBuild }
    var activeIsPersonal: Bool { active?.isPersonal ?? true }
    /// K35: a shared Workspace calls the cycle date "Awal periode"; Workspace Pribadi keeps "Tanggal gajian". Same data and maths.
    static func paydayTitle(shared: Bool) -> String { shared ? L("Awal periode") : L("Tanggal gajian") }
    static func paydaySaved(shared: Bool) -> String { shared ? L("Awal periode disimpan, berlaku untuk semua anggota") : L("Tanggal gajian disimpan") }
    var paydayTitle: String { Self.paydayTitle(shared: !activeIsPersonal) }
    /// Read-only (K9, A3) or waiting to be deleted (K21): the open Workspace takes no new records.
    var activeBlocksWriting: Bool { active.map { $0.isReadOnly || $0.daysUntilDeletion != nil } ?? false }

    /// True when a record may be added here; otherwise says why, once.
    func allowsWriting() -> Bool {
        guard activeBlocksWriting else { return true }
        tell(.readOnly)
        return false
    }

    /// A8 (13): an Owner's change to categories, budgets or the period start touches every member; say so once it is saved.
    func announceSharedChange() {
        guard !activeIsPersonal else { return }
        tell(.sharedChange)
    }

    var canEditActive: Bool { activeIsPersonal || active?.isOwner == true }

    /// K45: in a shared Workspace only the Owner sets up categories and budgets; a member who tries is told once.
    func requireOwner() -> Bool {
        guard !canEditActive else { return true }
        tell(.ownerOnly)
        return false
    }

    func requestCreate() { createRequests += 1 }

    /// What a person is told in a sheet (not a toast): short hints would be cut to one line and missed.
    struct Notice: Identifiable, Equatable {
        enum Kind { case accessLost, draftSaved, readOnly, ownerOnly, sharedChange }
        let kind: Kind
        var id: Int { kind.hashValue }
        var icon: String {
            switch kind {
            case .accessLost: "person.crop.circle.badge.xmark"
            case .draftSaved: "tray.and.arrow.down.fill"
            case .readOnly: "lock.fill"
            case .ownerOnly: "person.badge.key.fill"
            case .sharedChange: "person.2.fill"
            }
        }
        var title: String {
            switch kind {
            case .accessLost: L("Akses Workspace hilang")
            case .draftSaved: L("Disimpan sebagai draf")
            case .readOnly: L("Workspace ini baca saja")
            case .ownerOnly: L("Hanya Pemilik yang bisa mengubah")
            case .sharedChange: L("Berlaku untuk semua anggota")
            }
        }
        var message: String {
            switch kind {
            case .accessLost: L("Kamu tidak lagi punya akses ke Workspace itu. Saku membuka Workspace utamamu.")
            case .draftSaved: L("Workspace ini tidak bisa diisi lagi, jadi catatanmu disimpan sebagai draf. Cek di Konfirmasi transaksi.")
            case .readOnly: L("Kamu belum bisa menambah catatan di sini. Catatan yang sudah ada tetap bisa dilihat.")
            case .ownerOnly: L("Kategori dan budget Workspace ini hanya diatur oleh Pemilik. Kamu tetap bisa melihatnya.")
            case .sharedChange: L("Perubahan tadi terlihat oleh semua anggota Workspace ini.")
            }
        }
    }
    @Published var notice: Notice?
    /// Shown a moment later, so a screen that is closing (or a reload) does not swallow the sheet.
    func tell(_ kind: Notice.Kind) {
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            notice = Notice(kind: kind)
        }
    }

    /// Set around a loss the person caused themselves (leaving), so `load()` does not announce it.
    private var quietLoss = false

    /// K44 / A8 (6): a new record was refused because access is gone or the Workspace turned read-only. Reloads the list
    /// (A2 moves the default to Workspace Pribadi when needed) and says whether the refusal was of that kind.
    static func isRejection(_ error: Error) -> Bool {
        let text = String(describing: error)
        return text.contains("space_forbidden") || text.contains("space_read_only")
    }

    /// `quiet`: the caller already tells the person what happened, so the access-lost toast stays away.
    func handleRejection(_ error: Error, quiet: Bool = false) async -> Bool {
        guard Self.isRejection(error) else { return false }
        quietLoss = quiet
        await load()
        return true
    }

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
                // A8 (5): told once when removed or the Workspace was deleted; leaving on purpose says nothing
                if !quietLoss { tell(.accessLost) }
            }
            quietLoss = false
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

    /// K38/A5: Workspace Pribadi becomes this shared Workspace with its history; a new empty Workspace Pribadi takes its place.
    /// The server keeps the id, so the default and the open workspace stay on the converted one.
    func convertPersonal(name: String, icon: String, color: String) async throws -> Workspace {
        struct Params: Encodable, Sendable { let p_name: String, p_icon: String, p_color: String }
        do {
            let id: UUID = try await SupabaseSDK.client.rpc("convert_personal_space", params: Params(p_name: name, p_icon: icon, p_color: color)).execute().value
            await load()
            reloadApp()
            guard let made = spaces.first(where: { $0.id == id }) else { throw WorkspaceError.other }
            return made
        } catch { throw WorkspaceError(error) }
    }

    /// K36/A4: moves every non credit card wallet of Workspace Pribadi into `target`, no history; all or nothing. Returns how many.
    func moveAllWallets(to target: Workspace) async throws -> Int {
        do {
            let count: Int = try await SupabaseSDK.client.rpc("move_all_accounts_to_space", params: ["p_target": target.id]).execute().value
            AppDataCache.shared.clearAll()
            return count
        } catch { throw WorkspaceError(error) }
    }

    /// K39/K42: what moving would bring (counts, limit check, category suggestions). `rescue` reads a Workspace in its grace period.
    func movePreview(rescue: Bool, space: UUID) async throws -> MovePreview {
        do {
            let params = rescue ? ["p_space": space] : ["p_target": space]
            return try await SupabaseSDK.client.rpc(rescue ? "rescue_preview" : "merge_preview", params: params).execute().value
        } catch { throw WorkspaceError(error) }
    }

    /// Moves it all or nothing (A6, A7). `map` sends each source category to a destination category id or "new".
    func moveApply(rescue: Bool, space: UUID, map: [String: String]) async throws -> MoveResult {
        struct Params: Encodable, Sendable { let p_space: UUID?, p_target: UUID?, p_map: [String: String] }
        do {
            let params = Params(p_space: rescue ? space : nil, p_target: rescue ? nil : space, p_map: map)
            let result: MoveResult = try await SupabaseSDK.client.rpc(rescue ? "rescue_from_deleting_space" : "merge_personal_into_space", params: params).execute().value
            await load()
            reloadApp()
            return result
        } catch { throw WorkspaceError(error) }
    }

    /// K36: one wallet, from the wallet's detail.
    func moveWallet(_ accountId: String, to target: Workspace) async throws {
        struct Params: Encodable, Sendable { let p_account: String, p_target: UUID }
        do {
            let _: UUID = try await SupabaseSDK.client.rpc("move_account_to_space", params: Params(p_account: accountId, p_target: target.id)).execute().value
            AppDataCache.shared.clearAll()
        } catch { throw WorkspaceError(error) }
    }

    func update(_ workspace: Workspace, name: String, icon: String, color: String) async throws {
        struct Params: Encodable, Sendable { let p_space: UUID, p_name: String, p_icon: String, p_color: String }
        do {
            try await SupabaseSDK.client.rpc("update_space", params: Params(p_space: workspace.id, p_name: name, p_icon: icon, p_color: color)).execute()
            await load()
        } catch { throw WorkspaceError(error) }
    }

    /// The Owner's picture: `jpeg` uploads and sets it, nil removes it.
    func setImage(of workspace: Workspace, jpeg: Data?) async throws {
        struct Params: Encodable, Sendable { let p_space: UUID, p_url: String }
        do {
            var url = ""
            if let jpeg { url = try await SupabaseSDK.uploadWorkspaceImage(spaceId: workspace.id, jpeg: jpeg) }
            try await SupabaseSDK.client.rpc("set_space_image", params: Params(p_space: workspace.id, p_url: url)).execute()
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

    /// K21: hidden from every member at once; the owner has 7 days to cancel.
    func requestDeletion(of workspace: Workspace) async throws {
        do {
            _ = try await SupabaseSDK.client.rpc("request_space_deletion", params: ["p_space": workspace.id]).execute()
            // the owner may not stay inside a Workspace that is going away
            if workspace.id == activeId, let personal { open(personal) }
            await load()
        } catch { throw WorkspaceError(error) }
    }

    func cancelDeletion(of workspace: Workspace) async throws {
        do {
            try await SupabaseSDK.client.rpc("cancel_space_deletion", params: ["p_space": workspace.id]).execute()
            await load()
        } catch { throw WorkspaceError(error) }
    }

    func leave(_ workspace: Workspace) async throws {
        do {
            try await SupabaseSDK.client.rpc("leave_space", params: ["p_space": workspace.id]).execute()
            quietLoss = true
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


/// What `merge_preview` and `rescue_preview` return (TD 6.1).
struct MovePreview: Decodable, Equatable {
    struct Source: Decodable, Equatable, Identifiable {
        let id: String, name: String, kind: String, uses: Int, suggested: String?
        let icon: String?, color: String?
    }
    struct Destination: Decodable, Equatable, Identifiable {
        let id: String, name: String, kind: String, hidden: Bool
    }
    let targetName: String
    let canCreate: Bool
    let wallets: Int, cards: Int, transactions: Int
    let limitOk: Bool
    let moneyAfter: Int, investmentAfter: Int
    let source: [Source]
    let destination: [Destination]

    enum CodingKeys: String, CodingKey {
        case targetName = "target_name", canCreate = "can_create", wallets, cards, transactions
        case limitOk = "limit_ok", moneyAfter = "money_after", investmentAfter = "investment_after", source, destination
    }

    /// Categories that a moved record uses: these need an answer before the move (A7).
    var needsMapping: [Source] { source.filter { $0.uses > 0 } }
}

struct MoveResult: Decodable, Equatable { let wallets: Int, transactions: Int }
