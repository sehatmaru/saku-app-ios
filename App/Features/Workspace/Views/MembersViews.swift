import SwiftUI

/// Anggota on a Workspace's settings page: who is in, the Owner's tools (invite, remove, hand over), and leaving (US9, US10).
struct WorkspaceMembersSection: View {
    let workspace: Workspace
    @ObservedObject private var store = WorkspaceStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var members: [WorkspaceMember] = []
    @State private var failed = false
    @State private var showsInvite = false
    @State private var picked: WorkspaceMember?
    @State private var asking: Ask?
    @State private var confirmsLeave = false

    private enum Ask: Identifiable {
        case remove(WorkspaceMember), transfer(WorkspaceMember)
        var id: UUID { switch self { case .remove(let m), .transfer(let m): m.id } }
    }

    private var active: [WorkspaceMember] { members.filter { !$0.isFormer } }
    private var former: [WorkspaceMember] { members.filter(\.isFormer) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            label(L("Anggota · %lld dari 5", max(active.count, workspace.memberCount)))
            if failed && members.isEmpty {
                Button(L("Daftar anggota belum bisa dimuat. Coba lagi.")) { Task { await load() } }
                    .font(.app(15)).foregroundStyle(Color.appPrimary).padding(.vertical, 12)
            }
            ForEach(active) { member in
                Button { if workspace.isOwner, !member.isMe { picked = member } } label: { row(member) }
                    .buttonStyle(RowPressStyle())
                    .disabled(!(workspace.isOwner && !member.isMe))
            }
            if workspace.isOwner {
                Button { showsInvite = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "person.badge.plus").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.appPrimary)
                            .frame(width: 40, height: 40).background(Color.appFill, in: Circle())
                        Text(L("Undang anggota")).font(.app(16, weight: .semibold)).foregroundStyle(Color.appPrimary)
                        Spacer(minLength: 8)
                    }
                    .frame(minHeight: 60).contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
            }
            if !former.isEmpty {
                label(L("Mantan anggota"))
                ForEach(former) { member in row(member).opacity(0.55) }
                Text(L("Catatan mereka tetap di Workspace ini."))
                    .font(.app(13)).foregroundStyle(Color.appTextSecondary).padding(.top, 2)
            }
            if !workspace.isOwner {
                Button { confirmsLeave = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 19)).foregroundStyle(Color.appError).frame(width: 24)
                        Text(L("Keluar dari Workspace")).font(.app(16)).foregroundStyle(Color.appError)
                        Spacer(minLength: 8)
                    }
                    .frame(minHeight: 52).contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .padding(.top, 16)
            }
        }
        .task(id: workspace.id) { await load() }
        .sheet(isPresented: $showsInvite, onDismiss: { Task { await load() } }) { InviteSheet(workspace: workspace) }
        .confirmationDialog(picked?.name ?? "", isPresented: Binding(get: { picked != nil }, set: { if !$0 { picked = nil } }), titleVisibility: .visible) {
            if let member = picked {
                Button(L("Jadikan Pemilik")) { asking = .transfer(member) }
                Button(L("Keluarkan dari Workspace"), role: .destructive) { asking = .remove(member) }
            }
        }
        .alert(item: $asking) { ask in
            switch ask {
            case .remove(let member):
                Alert(title: Text(L("Keluarkan %@?", member.name)),
                      message: Text(L("Catatan %@ tetap di Workspace dan ditandai mantan anggota. Dia perlu kode baru untuk masuk lagi.", member.name)),
                      primaryButton: .destructive(Text(L("Keluarkan"))) { Task { await remove(member) } },
                      secondaryButton: .cancel(Text(L("Batal"))))
            case .transfer(let member):
                Alert(title: Text(L("Jadikan %@ Pemilik?", member.name)),
                      message: Text(L("Kamu menjadi anggota biasa. %@ yang bisa mengundang, mengeluarkan anggota, dan mengubah Workspace.", member.name)),
                      primaryButton: .default(Text(L("Jadikan Pemilik"))) { Task { await transfer(member) } },
                      secondaryButton: .cancel(Text(L("Batal"))))
            }
        }
        .alert(L("Keluar dari %@?", workspace.displayName), isPresented: $confirmsLeave) {
            Button(L("Keluar"), role: .destructive) { Task { await leave() } }
            Button(L("Batal"), role: .cancel) {}
        } message: { Text(L("Catatanmu tetap di Workspace dan ditandai mantan anggota. Kamu perlu kode baru untuk masuk lagi.")) }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.app(13, weight: .semibold)).foregroundStyle(Color.appTextSecondary).padding(.top, 20).padding(.bottom, 2)
    }

    private func row(_ member: WorkspaceMember) -> some View {
        HStack(spacing: 14) {
            avatar(member)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.isMe ? L("%@ (kamu)", member.name) : member.name)
                    .font(.app(16, weight: .semibold)).foregroundStyle(Color.appText).lineLimit(1)
                Text(member.isFormer ? L("Mantan anggota") : member.isOwner ? L("Pemilik") : L("Anggota"))
                    .font(.app(13)).foregroundStyle(Color.appTextSecondary)
            }
            Spacer(minLength: 8)
            if workspace.isOwner, !member.isMe, !member.isFormer {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.appTextTertiary)
            }
        }
        .frame(minHeight: 60)
        .contentShape(Rectangle())
    }

    private func avatar(_ member: WorkspaceMember) -> some View {
        ZStack {
            Circle().fill(Color.appFill)
            Text(member.initial).font(.app(16, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
            if let raw = member.avatarUrl, let url = URL(string: raw) {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.clear }
                    .clipShape(Circle())
            }
        }
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }

    private func load() async {
        do { members = try await store.members(of: workspace); failed = false } catch { failed = true }
    }

    private func remove(_ member: WorkspaceMember) async {
        do {
            try await store.remove(member, from: workspace)
            ToastCenter.shared.show(L("%@ dikeluarkan", member.name))
            await load(); await store.load()
        } catch { ToastCenter.shared.show(L("Belum bisa mengeluarkan. Coba lagi.")) }
    }

    private func transfer(_ member: WorkspaceMember) async {
        do {
            try await store.transfer(workspace, to: member)
            ToastCenter.shared.show(L("%@ sekarang Pemilik", member.name))
            await load()
        } catch { ToastCenter.shared.show(L("Belum bisa menyerahkan. Coba lagi.")) }
    }

    private func leave() async {
        do {
            try await store.leave(workspace)
            ToastCenter.shared.show(L("Kamu keluar dari %@", workspace.displayName))
            dismiss()
        } catch { ToastCenter.shared.show(L("Belum bisa keluar. Coba lagi.")) }
    }
}
