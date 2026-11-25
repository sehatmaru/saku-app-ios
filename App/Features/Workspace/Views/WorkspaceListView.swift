import SwiftUI

/// Profil → Workspace: the list of the person's Workspaces (the default one carries a tag) and the way to make or join one (K33).
struct WorkspaceListView: View {
    @ObservedObject private var store = WorkspaceStore.shared
    @State private var showsDeleting = false

    private var active: [Workspace] { store.spaces.filter { $0.daysUntilDeletion == nil } }
    private var defaultSpace: Workspace? { active.first { $0.isDefault && !$0.isReadOnly } }
    private var others: [Workspace] { active.filter { $0.id != defaultSpace?.id } }
    private var deleting: [Workspace] { store.spaces.filter { $0.daysUntilDeletion != nil } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if store.loadFailed && store.spaces.isEmpty {
                    failure.padding(.horizontal, 24).padding(.top, 8)
                } else {
                    if let defaultSpace {
                        label(L("Default Workspace"))
                        NavigationLink(destination: WorkspaceSettingsView(workspaceId: defaultSpace.id).detailPage()) { row(defaultSpace) }
                            .buttonStyle(RowPressStyle())
                    }
                    label(defaultSpace == nil ? L("Workspace saya") : L("Lainnya"))
                    ForEach(others) { workspace in
                        NavigationLink(destination: WorkspaceSettingsView(workspaceId: workspace.id).detailPage()) { row(workspace) }
                            .buttonStyle(RowPressStyle())
                    }
                    joinRow
                    if !deleting.isEmpty { deletingCard }
                    if store.shared.isEmpty {
                        Text(L("Kamu baru punya Workspace Pribadi. Buat Workspace untuk mencatat keuangan bersama orang lain."))
                            .font(.app(13)).foregroundStyle(Color.appTextSecondary).lineSpacing(2)
                            .padding(.horizontal, 24).padding(.top, 12)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color.appBackground)
        .safeAreaInset(edge: .bottom) {
            SmartSheetFooter(primary: L("Tambah workspace"), onPrimary: { store.requestCreate() })
                .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 12)
                .background(Color.appBackground)
        }
        .navigationTitle(L("Workspace"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
    }

    private var joinRow: some View {
        Button { store.requestJoin() } label: {
            HStack(spacing: 14) {
                Image(systemName: "number")
                    .font(.system(size: 20, weight: .bold)).foregroundStyle(Color.appPrimary)
                    .frame(width: 48, height: 48)
                    .background(Color.appPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 48 * 0.29, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("Punya kode undangan?")).font(.app(16, weight: .semibold)).foregroundStyle(Color.appText)
                    Text(L("Gabung ke Workspace orang lain")).font(.app(14)).foregroundStyle(Color.appTextSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.appTextTertiary)
            }
            .frame(minHeight: 68).padding(.horizontal, 24).contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .padding(.top, 28)
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.app(13, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 2)
    }

    private func secondLine(_ workspace: Workspace) -> String {
        var line = workspace.isPersonal ? L("Hanya kamu") : workspace.isOwner ? L("Pemilik") : L("Anggota · %lld orang", workspace.memberCount)
        if workspace.isReadOnly { line += " · " + L("Baca saja") }
        return line
    }

    private func row(_ workspace: Workspace) -> some View {
        HStack(spacing: 14) {
            WorkspaceBadge(workspace, size: 48)
            VStack(alignment: .leading, spacing: 1) {
                Text(workspace.displayName).font(.app(16, weight: .semibold)).foregroundStyle(Color.appText).lineLimit(1)
                Text(secondLine(workspace)).font(.app(14)).foregroundStyle(Color.appTextSecondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if workspace.id == defaultSpace?.id {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 22, height: 22).background(Color.appPrimary, in: Circle())
            } else {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.appTextTertiary)
            }
        }
        .frame(minHeight: 68)
        .padding(.horizontal, 24)
        .contentShape(Rectangle())
    }

    /// Workspaces waiting out their 7 days sit in one quiet card instead of filling the list.
    private var deletingCard: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.settle(0.3)) { showsDeleting.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "clock").font(.system(size: 17)).foregroundStyle(Color.appError)
                        .frame(width: 36, height: 36).background(Color.appError.opacity(0.09), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L("%lld Workspace akan dihapus", deleting.count)).font(.app(15, weight: .semibold)).foregroundStyle(Color.appText)
                        Text(deleting.map(\.displayName).joined(separator: ", ")).font(.app(13)).foregroundStyle(Color.appTextSecondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.appTextTertiary)
                        .rotationEffect(.degrees(showsDeleting ? 180 : 0))
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showsDeleting {
                ForEach(deleting) { workspace in
                    NavigationLink(destination: WorkspaceSettingsView(workspaceId: workspace.id).detailPage()) {
                        HStack(spacing: 12) {
                            WorkspaceBadge(workspace, size: 36)
                            Text(workspace.displayName).font(.app(15)).foregroundStyle(Color.appText).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(L("Dihapus dalam %lld hari", workspace.daysUntilDeletion ?? 0))
                                .font(.app(12, weight: .semibold)).foregroundStyle(Color.appError)
                        }
                        .frame(minHeight: 52)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                }
            }
        }
        .background(Color.appError.opacity(0.09), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 24).padding(.top, 20)
    }

    private var failure: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Daftar Workspace belum bisa dimuat."))
                .font(.app(15)).foregroundStyle(Color.appTextSecondary)
            Button(L("Coba lagi")) { Task { await store.load() } }
                .font(.app(15, weight: .semibold)).foregroundStyle(Color.appPrimary)
        }
    }
}

/// One Workspace's settings (K33). The Owner edits name, icon, colour and payday; members only look.
struct WorkspaceSettingsView: View {
    let workspaceId: UUID
    @ObservedObject private var store = WorkspaceStore.shared
    @State private var editing: EditWorkspaceSheet.Field?
    @State private var showsPayday = false
    @State private var confirmsDelete = false
    @State private var isDeleting = false
    @State private var showsRescue = false
    @State private var showsBring = false

    private var workspace: Workspace? { store.spaces.first { $0.id == workspaceId } }

    var body: some View {
        ScrollView {
            if let workspace {
                VStack(spacing: 0) {
                    header(workspace)
                    VStack(spacing: 0) {
                        if !workspace.isPersonal {
                            row(L("Nama"), value: workspace.displayName, editable: workspace.isOwner) { editing = .name }
                            row(L("Ikon, warna, dan foto"), editable: workspace.isOwner, trailing: { WorkspaceBadge(workspace, size: 28) }) { editing = .look }
                        }
                        row(WorkspaceStore.paydayTitle(shared: !workspace.isPersonal), value: workspace.paydayDay.map { "\($0)" } ?? L("Belum diatur"),
                            editable: workspace.isOwner) { editPayday(workspace) }
                        defaultRow(workspace)
                    }
                    .padding(.horizontal, 24)
                    if !workspace.isPersonal {
                        WorkspaceMembersSection(workspace: workspace).padding(.horizontal, 24)
                    }
                    // any member may bring their own wallets in, moved or copied (K39)
                    let canBring = !workspace.isPersonal && !workspace.isReadOnly && workspace.daysUntilDeletion == nil
                    let canRescue = !workspace.isOwner && !workspace.isPersonal && workspace.daysUntilDeletion != nil
                    let canDelete = workspace.isOwner && !workspace.isPersonal
                    if canBring || canRescue || canDelete { sectionLabel(L("Lainnya")) }
                    if canBring {
                        actionRow(L("Bawa data pribadi saya ke sini"), sub: L("Pindahkan atau salin dompet pribadi")) { showsBring = true }
                    }
                    // K42: a member can still bring their own wallets out while the Workspace waits to be deleted
                    if canRescue, let days = workspace.daysUntilDeletion {
                        actionRow(L("Bawa data saya ke Workspace Pribadi"), sub: L("Dihapus dalam %lld hari", days)) { showsRescue = true }
                    }
                    if canDelete { deleteRow(workspace) }
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
        .sheet(item: $editing) { field in
            if let workspace { EditWorkspaceSheet(workspace: workspace, field: field) }
        }
        .sheet(isPresented: $showsBring) { MergeWizardView(mode: .merge(target: workspaceId)) }
        .sheet(isPresented: $showsRescue) { MergeWizardView(mode: .rescue(space: workspaceId)) }
        .sheet(isPresented: $showsPayday) {
            PaydaySheet(context: .settings) { day in
                guard day != nil else { return }
                ToastCenter.shared.show(WorkspaceStore.paydaySaved(shared: !store.activeIsPersonal))
                Task { await store.load() }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.app(13, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 2)
    }

    private func actionRow(_ title: String, sub: String, destructive: Bool = false, subIsError: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.app(16, weight: .medium)).foregroundStyle(destructive ? Color.appError : Color.appText)
                    Text(sub).font(.app(13)).foregroundStyle(subIsError ? Color.appError : Color.appTextSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.appTextTertiary)
            }
            .frame(minHeight: 60).contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .padding(.horizontal, 24)
    }

    /// K21: delete with 7 days of grace, or take it back while the days run.
    private func deleteRow(_ workspace: Workspace) -> some View {
        if let days = workspace.daysUntilDeletion {
            return actionRow(L("Batalkan penghapusan"), sub: L("Dihapus dalam %lld hari", days), subIsError: true) { Task { await cancelDeletion(workspace) } }
        }
        return actionRow(L("Hapus Workspace"), sub: L("Dihapus permanen setelah 7 hari"), destructive: true) { confirmsDelete = true }
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
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Default Workspace")).font(.app(16)).foregroundStyle(Color.appText)
                Text(blocked ? L("Workspace baca saja tidak bisa dipilih") : L("Dibuka saat app dijalankan"))
                    .font(.app(13)).foregroundStyle(Color.appTextSecondary)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(
                get: { workspace.isDefault },
                set: { on in
                    if on { Task { try? await store.setDefault(workspace); ToastCenter.shared.show(L("%@ jadi Default Workspace", workspace.displayName)) } }
                    else { ToastCenter.shared.show(L("Pilih Workspace lain untuk mengganti default")) }
                }))
                .labelsHidden().tint(.appPrimary)
                .accessibilityLabel(L("Default Workspace"))
        }
        .frame(minHeight: 60)
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
    enum Field: Identifiable { case name, look; var id: Self { self } }
    let workspace: Workspace
    let field: Field
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = WorkspaceStore.shared
    @State private var name: String
    @State private var icon: String
    @State private var color: String
    @State private var photo: UIImage?
    @State private var photoRemoved = false
    @State private var lookMode = WorkspaceLookMode.icon
    @State private var showsAllIcons = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(workspace: Workspace, field: Field) {
        self.workspace = workspace
        self.field = field
        _name = State(initialValue: workspace.displayName)
        _icon = State(initialValue: workspace.icon ?? "person.2.fill")
        _color = State(initialValue: workspace.color ?? "hijau")
        _lookMode = State(initialValue: workspace.imageUrl?.isEmpty == false ? .photo : .icon)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(field == .name ? L("Nama Workspace") : L("Ikon, warna, dan foto"))
                .font(.app(22, weight: .bold)).tracking(-0.3)
                .padding(.horizontal, 24).padding(.top, 20)
            if field == .name {
                TextField("", text: $name, prompt: Text(L("Nama Workspace")).foregroundStyle(Color.appTextTertiary))
                    .font(.app(17)).tint(.appPrimary)
                    .padding(.horizontal, 16).frame(height: 56)
                    .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 24).padding(.top, 16)
                    .onChange(of: name) { _, value in if value.count > 40 { name = String(value.prefix(40)) } }
                Text(errorMessage ?? L("Terlihat oleh semua anggota."))
                    .font(.app(13)).foregroundStyle(errorMessage == nil ? Color.appTextSecondary : Color.appError)
                    .padding(.horizontal, 24).padding(.top, 8)
            } else {
                WorkspaceBadge(icon: icon, color: color, size: 72, imageUrl: photoRemoved ? nil : workspace.imageUrl, image: photo)
                    .frame(maxWidth: .infinity).padding(.top, 16)
                if let errorMessage {
                    Text(errorMessage).font(.app(13)).foregroundStyle(Color.appError).padding(.horizontal, 24).padding(.top, 8)
                }
            WorkspaceLookModePicker(mode: $lookMode).padding(.horizontal, 24).padding(.top, 8)
            if lookMode == .photo {
                WorkspacePhotoPanel(imageUrl: workspace.imageUrl, photo: $photo, removed: $photoRemoved).padding(.horizontal, 24)
            } else {
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
            }
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
                if let photo, let jpeg = ProfileViewModel.avatarJPEG(photo) {
                    try await store.setImage(of: workspace, jpeg: jpeg)
                } else if photoRemoved, workspace.imageUrl?.isEmpty == false {
                    try await store.setImage(of: workspace, jpeg: nil)
                }
                dismiss()
            } catch {
                isSaving = false
                errorMessage = L("Gagal menyimpan. Coba lagi.")
            }
        }
    }
}
