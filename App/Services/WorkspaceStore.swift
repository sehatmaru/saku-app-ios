import Foundation
import SwiftUI

/// Failures of the workspace calls the screens tell apart (TD T4 error codes).
enum WorkspaceError: Error, Equatable {
    case limit, guest, other

    init(_ error: Error) {
        let text = String(describing: error)
        if text.contains("space_limit") { self = .limit }
        else if text.contains("guest_not_allowed") { self = .guest }
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

    var personal: Workspace? { spaces.first { $0.isPersonal } }
    var active: Workspace? { spaces.first { $0.id == activeId } ?? personal }
    var shared: [Workspace] { spaces.filter { !$0.isPersonal } }
    var owned: [Workspace] { shared.filter(\.isOwner) }
    /// Beranda shows the switcher only when there is something to switch to, or for the testers while this is not public (K30).
    var showsSwitcher: Bool { PlusStore.shared.isTester }
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
        reloadApp()
    }

    private func reloadApp() {
        AppDataCache.shared.clearAll()
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

    /// Back to the signed-out state: nothing of this account stays in memory.
    func reset() {
        spaces = []; activeId = nil; hasLoaded = false; loadFailed = false; resetNotice = false
    }
}
