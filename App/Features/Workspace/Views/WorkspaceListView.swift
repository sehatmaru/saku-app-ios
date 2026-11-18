import SwiftUI

/// Profil → Workspace: which Workspace opens at launch, and the list of the person's Workspaces with the way to make one (K33).
struct WorkspaceListView: View {
    @ObservedObject private var store = WorkspaceStore.shared
    @State private var showsMerge = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if store.loadFailed && store.spaces.isEmpty {
                    failure.padding(.horizontal, 24).padding(.top, 8)
                } else {
                    if store.shared.isEmpty == false { launchRow }
                    label(L("Workspace saya"))
                    ForEach(store.spaces) { workspace in
                        NavigationLink(destination: WorkspaceSettingsView(workspaceId: workspace.id).detailPage()) {
                            WorkspaceRow(workspace: workspace) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.appTextTertiary)
                            }
                            .padding(.horizontal, 24)
                        }
                        .buttonStyle(RowPressStyle())
                    }
                    Button { store.requestCreate() } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.appPrimary)
                                .frame(width: 40, height: 40)
                                .background(Color.appFill, in: Circle())
                            Text(L("Buat Workspace"))
                                .font(.app(16, weight: .semibold))
                                .foregroundStyle(Color.appPrimary)
                            Spacer(minLength: 8)
                        }
                        .frame(minHeight: 64)
                        .padding(.horizontal, 24)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    Button { store.requestJoin() } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "number")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.appPrimary)
                                .frame(width: 40, height: 40)
                                .background(Color.appFill, in: Circle())
                            Text(L("Gabung dengan kode"))
                                .font(.app(16, weight: .semibold))
                                .foregroundStyle(Color.appPrimary)
                            Spacer(minLength: 8)
                        }
                        .frame(minHeight: 64)
                        .padding(.horizontal, 24)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    if store.shared.contains(where: { !$0.isReadOnly && $0.daysUntilDeletion == nil }) {
                        Button { showsMerge = true } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "arrow.triangle.merge")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color.appPrimary)
                                    .frame(width: 40, height: 40)
                                    .background(Color.appFill, in: Circle())
                                Text(L("Gabungkan Workspace Pribadi"))
                                    .font(.app(16, weight: .semibold))
                                    .foregroundStyle(Color.appPrimary)
                                Spacer(minLength: 8)
                            }
                            .frame(minHeight: 64)
                            .padding(.horizontal, 24)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                    }
                    if store.shared.isEmpty {
                        Text(L("Kamu baru punya Workspace Pribadi. Buat Workspace untuk mencatat keuangan bersama orang lain."))
                            .font(.app(13)).foregroundStyle(Color.appTextSecondary).lineSpacing(2)
                            .padding(.horizontal, 24).padding(.top, 8)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color.appBackground)
        .navigationTitle(L("Workspace"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .sheet(isPresented: $showsMerge) { MergeWizardView(mode: .merge(target: nil)) }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.app(13, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 2)
    }

    private var failure: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Daftar Workspace belum bisa dimuat."))
                .font(.app(15)).foregroundStyle(Color.appTextSecondary)
            Button(L("Coba lagi")) { Task { await store.load() } }
                .font(.app(15, weight: .semibold)).foregroundStyle(Color.appPrimary)
        }
    }

    /// "Dibuka saat app dijalankan": a Workspace that is read-only or waiting for deletion cannot be the default.
    private var launchRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            label(L("Dibuka saat app dijalankan"))
            Menu {
                ForEach(store.spaces) { workspace in
                    let blocked = workspace.isReadOnly || workspace.daysUntilDeletion != nil
                    Button {
                        Task { try? await store.setDefault(workspace) }
                    } label: {
                        if workspace.isDefault { Label(workspace.displayName, systemImage: "checkmark") }
                        else { Text(blocked ? L("%@ · Baca saja", workspace.displayName) : workspace.displayName) }
                    }
                    .disabled(blocked)
                }
            } label: {
                HStack(spacing: 8) {
                    Text(store.spaces.first(where: \.isDefault)?.displayName ?? L("Workspace Pribadi"))
                        .font(.app(16)).foregroundStyle(Color.appText).lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.appTextTertiary)
                }
                .frame(minHeight: 48)
                .padding(.horizontal, 24)
                .contentShape(Rectangle())
            }
        }
    }
}

/// One Workspace's settings (K33). The Owner edits name, icon, colour and payday; members only look.
struct WorkspaceSettingsView: View {
    let workspaceId: UUID
    @ObservedObject private var store = WorkspaceStore.shared
    @State private var showsEdit = false
    @State private var showsPayday = false
    @State private var confirmsDelete = false
    @State private var isDeleting = false
    @State private var showsRescue = false

    private var workspace: Workspace? { store.spaces.first { $0.id == workspaceId } }

    var body: some View {
        ScrollView {
            if let workspace {
                VStack(spacing: 0) {
                    header(workspace)
                    VStack(spacing: 0) {
                        if !workspace.isPersonal {
                            row(L("Nama"), value: workspace.displayName, editable: workspace.isOwner) { showsEdit = true }
                            row(L("Ikon dan warna"), editable: workspace.isOwner, trailing: { WorkspaceBadge(workspace, size: 28) }) { showsEdit = true }
                        }
                        row(WorkspaceStore.paydayTitle(shared: !workspace.isPersonal), value: workspace.paydayDay.map { "\($0)" } ?? L("Belum diatur"),
                            editable: workspace.isOwner) { editPayday(workspace) }
                        defaultRow(workspace)
                    }
                    .padding(.horizontal, 24)
                    if !workspace.isPersonal {
                        WorkspaceMembersSection(workspace: workspace).padding(.horizontal, 24)
                    }
                    if workspace.isOwner && !workspace.isPersonal { deleteRow(workspace) }
                    // K42: a member can still bring their own wallets out while the Workspace waits to be deleted
                    if !workspace.isOwner && !workspace.isPersonal, let days = workspace.daysUntilDeletion {
                        Text(L("Dihapus dalam %lld hari", days)).font(.app(13)).foregroundStyle(Color.appError)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.top, 14)
                        Button { showsRescue = true } label: {
                            Text(L("Bawa data saya ke Workspace Pribadi"))
                                .font(.app(16, weight: .semibold)).foregroundStyle(Color.appPrimaryText)
                                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                        .padding(.horizontal, 24)
                    }
                    if !workspace.isOwner {
                        Text(L("Hanya Pemilik yang bisa mengubah"))
                            .font(.app(13)).foregroundStyle(Color.appTextSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24).padding(.top, 12)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .background(Color.appBackground)
        .navigationTitle(L("Pengaturan Workspace"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmDialog(isPresented: $confirmsDelete, icon: "trash", destructive: true, title: L("Hapus Workspace?"),
                       message: L("%@ langsung tersembunyi dari semua anggota dan dihapus permanen setelah 7 hari, dengan semua datanya. Selama itu kamu bisa membatalkannya.", workspace?.displayName ?? ""),
                       confirmTitle: L("Hapus"), isBusy: isDeleting) {
            guard let workspace else { return }
            Task { await delete(workspace) }
        }
        .sheet(isPresented: $showsEdit) {
            if let workspace { EditWorkspaceSheet(workspace: workspace) }
        }
        .sheet(isPresented: $showsRescue) { MergeWizardView(mode: .rescue(space: workspaceId)) }
        .sheet(isPresented: $showsPayday) {
            PaydaySheet(context: .settings) { day in
                guard day != nil else { return }
                ToastCenter.shared.show(WorkspaceStore.paydaySaved(shared: !store.activeIsPersonal))
                Task { await store.load() }
            }
        }
    }

    /// K21: delete with 7 days of grace, or take it back while the days run.
    private func deleteRow(_ workspace: Workspace) -> some View {
        let waiting = workspace.daysUntilDeletion != nil
        return Button {
            if waiting { Task { await cancelDeletion(workspace) } } else { confirmsDelete = true }
        } label: {
            HStack {
                Text(waiting ? L("Batalkan penghapusan") : L("Hapus Workspace"))
                    .font(.app(16, weight: .medium))
                    .foregroundStyle(waiting ? Color.appPrimaryText : Color.appError)
                Spacer(minLength: 8)
                if let days = workspace.daysUntilDeletion {
                    Text(L("Dihapus dalam %lld hari", days)).font(.app(13)).foregroundStyle(Color.appError)
                }
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .padding(.horizontal, 24).padding(.top, 12)
    }

    private func delete(_ workspace: Workspace) async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await store.requestDeletion(of: workspace)
            confirmsDelete = false
        } catch { ToastCenter.shared.show(L("Belum berhasil. Periksa koneksi lalu coba lagi.")) }
    }

    private func cancelDeletion(_ workspace: Workspace) async {
        do { try await store.cancelDeletion(of: workspace) }
        catch { ToastCenter.shared.show(L("Belum berhasil. Periksa koneksi lalu coba lagi.")) }
    }

    private func header(_ workspace: Workspace) -> some View {
        VStack(spacing: 10) {
            WorkspaceBadge(workspace, size: 72)
            Text(workspace.displayName)
                .font(.app(22, weight: .bold)).tracking(-0.3)
                .multilineTextAlignment(.center)
            Text(workspace.isPersonal ? L("Hanya kamu") : workspace.isOwner ? L("Kamu Pemilik") : L("Anggota · %lld orang", workspace.memberCount))
                .font(.app(13)).foregroundStyle(Color.appTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 12)
    }

    private func row<T: View>(_ title: String, value: String? = nil, editable: Bool,
                              @ViewBuilder trailing: () -> T = { EmptyView() }, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title).font(.app(16)).foregroundStyle(Color.appText)
                Spacer(minLength: 8)
                if let value { Text(value).font(.app(15)).foregroundStyle(Color.appTextSecondary).lineLimit(1) }
                trailing()
                if editable {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.appTextTertiary)
                }
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .disabled(!editable)
    }

    private func defaultRow(_ workspace: Workspace) -> some View {
        let blocked = workspace.isReadOnly || workspace.daysUntilDeletion != nil
        return Button {
            guard !workspace.isDefault else { return }
            Task { try? await store.setDefault(workspace) }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Buka saat app dijalankan")).font(.app(16)).foregroundStyle(Color.appText)
                    if blocked {
                        Text(L("Workspace baca saja tidak bisa dipilih")).font(.app(13)).foregroundStyle(Color.appTextSecondary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.appPrimary)
                    .opacity(workspace.isDefault ? 1 : 0)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .disabled(blocked)
        .opacity(blocked ? 0.5 : 1)
    }

    /// The payday sheet reads and saves the Workspace that is open, so another one has to be opened first.
    private func editPayday(_ workspace: Workspace) {
        if workspace.id == store.active?.id { showsPayday = true }
        else { ToastCenter.shared.show(workspace.isPersonal ? L("Buka Workspace ini dulu untuk mengubah tanggal gajian") : L("Buka Workspace ini dulu untuk mengubah awal periode")) }
    }
}

/// Ubah nama, ikon, dan warna (Owner only, `update_space`).
struct EditWorkspaceSheet: View {
    let workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = WorkspaceStore.shared
    @State private var name: String
    @State private var icon: String
    @State private var color: String
    @State private var showsAllIcons = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(workspace: Workspace) {
        self.workspace = workspace
        _name = State(initialValue: workspace.displayName)
        _icon = State(initialValue: workspace.icon ?? "person.2.fill")
        _color = State(initialValue: workspace.color ?? "hijau")
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Ubah Workspace"))
                .font(.app(22, weight: .bold)).tracking(-0.3)
                .padding(.horizontal, 24).padding(.top, 20)
            VStack(spacing: 10) {
                WorkspaceBadge(icon: icon, color: color, size: 72)
                TextField("", text: $name, prompt: Text(L("Nama Workspace")).foregroundStyle(Color.appTextTertiary))
                    .font(.app(26, weight: .bold)).tracking(-0.3)
                    .multilineTextAlignment(.center).tint(.appPrimary)
                    .frame(height: 36)
                    .onChange(of: name) { _, value in if value.count > 40 { name = String(value.prefix(40)) } }
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button(L("Selesai")) { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                                .font(.app(17, weight: .semibold))
                        }
                    }
                if let errorMessage {
                    Text(errorMessage).font(.app(13)).foregroundStyle(Color.appError)
                }
            }
            .padding(.horizontal, 24).padding(.top, 16)
            VStack(spacing: 4) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 6), spacing: 4) {
                    ForEach(CategoryCatalog.visibleIcons(expanded: showsAllIcons), id: \.self) { symbol in
                        let isOn = symbol == icon
                        Button { icon = symbol } label: {
                            Circle()
                                .fill(isOn ? WorkspaceStyle.color(color).opacity(0.14) : .clear)
                                .frame(width: 44, height: 44)
                                .overlay {
                                    Image(systemName: symbol).font(.system(size: 21))
                                        .foregroundStyle(isOn ? WorkspaceStyle.color(color) : Color.appTextSecondary)
                                }
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(symbol)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
                Button(showsAllIcons ? L("Lebih sedikit") : L("Lihat semua ikon")) {
                    withAnimation(.settle(0.36)) { showsAllIcons.toggle() }
                }
                .font(.app(13, weight: .semibold)).foregroundStyle(Color.appPrimary)
                .frame(maxWidth: .infinity, minHeight: 36)
                Rectangle().fill(Color.appDivider).frame(height: 1).padding(.horizontal, 10)
                HStack(spacing: 0) {
                    ForEach(WalletIcon.presetColors, id: \.name) { preset in
                        let isOn = preset.name == color
                        Button { color = preset.name } label: {
                            Circle().fill(preset.color).frame(width: 24, height: 24).padding(3)
                                .overlay { Circle().stroke(preset.color, lineWidth: 2).opacity(isOn ? 1 : 0) }
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("Warna %@", preset.name))
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
            }
            .padding(.horizontal, 30).padding(.top, 12)
        }
        .disabled(isSaving)
        .filterSheet {
            SmartSheetFooter(primary: L("Simpan"), isBusy: isSaving, isEnabled: !trimmed.isEmpty, secondary: L("Batal"),
                             onPrimary: save, onSecondary: { dismiss() })
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await store.update(workspace, name: trimmed, icon: icon, color: color)
                dismiss()
            } catch {
                isSaving = false
                errorMessage = L("Gagal menyimpan. Coba lagi.")
            }
        }
    }
}
