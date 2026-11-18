import SwiftUI
import PhotosUI

/// The colour a workspace carries: one of `WalletIcon.presetColors` by name (K32).
enum WorkspaceStyle {
    static func color(_ name: String?) -> Color {
        name.flatMap(WalletIcon.presetColor(named:)) ?? Color.appPrimary
    }
}

/// A workspace's face: its picture when the Owner set one, else its colour with its icon in white.
struct WorkspaceBadge: View {
    let icon: String?
    let color: String?
    var size: CGFloat = 40
    var imageUrl: String?
    /// A picture chosen but not saved yet.
    var image: UIImage?

    init(icon: String?, color: String?, size: CGFloat = 40, imageUrl: String? = nil, image: UIImage? = nil) {
        self.icon = icon; self.color = color; self.size = size; self.imageUrl = imageUrl; self.image = image
    }

    init(_ workspace: Workspace, size: CGFloat = 40) {
        self.init(icon: workspace.isPersonal ? "person.fill" : workspace.icon, color: workspace.isPersonal ? "abu" : workspace.color, size: size,
                  imageUrl: workspace.isPersonal ? nil : workspace.imageUrl)
    }

    var body: some View {
        ZStack {
            Circle().fill(WorkspaceStyle.color(color))
            Image(systemName: icon ?? "person.2.fill")
                .font(.system(size: size * 0.45))
                .foregroundStyle(.white)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let raw = imageUrl, !raw.isEmpty, let url = URL(string: raw) {
                AsyncImage(url: url) { loaded in loaded.resizable().scaledToFill() } placeholder: { Color.clear }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// The big badge of the create and edit sheets: tap it to choose a picture; the icon stays as the fallback.
struct WorkspacePhotoBadge: View {
    let icon: String?
    let color: String?
    let imageUrl: String?
    @Binding var photo: UIImage?
    @Binding var removed: Bool
    @State private var item: PhotosPickerItem?

    private var shownUrl: String? { removed ? nil : imageUrl }

    var body: some View {
        VStack(spacing: 6) {
            PhotosPicker(selection: $item, matching: .images) {
                WorkspaceBadge(icon: icon, color: color, size: 72, imageUrl: shownUrl, image: photo)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera.fill").font(.system(size: 12)).foregroundStyle(Color.appPrimary)
                            .frame(width: 26, height: 26).background(Color.appBackground, in: Circle())
                            .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                            .offset(x: 4, y: 4)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Ganti foto"))
            if photo != nil || (shownUrl?.isEmpty == false) {
                Button(L("Hapus foto")) { photo = nil; removed = true }
                    .font(.app(13, weight: .semibold)).foregroundStyle(Color.appError)
            }
        }
        .onChange(of: item) { _, picked in
            guard let picked else { return }
            Task {
                if let data = try? await picked.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    photo = image; removed = false
                }
                item = nil
            }
        }
    }
}

/// Overlapping faces of a Workspace's members, the Owner first with a crown on the edge of the picture.
struct WorkspaceMemberStack: View {
    let members: [WorkspaceMember]
    var size: CGFloat = 28
    var limit = 5

    var body: some View {
        let shown = Array(members.prefix(limit))
        HStack(spacing: -size * 0.28) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, member in
                MemberAvatar(member: member, size: size)
                    .overlay(Circle().stroke(Color.appBackground, lineWidth: 2.5))
                    .overlay(alignment: .topTrailing) { if member.isOwner { crown } }
                    .zIndex(Double(shown.count - index))
            }
            if members.count > limit {
                Text("+\(members.count - limit)")
                    .font(.app(size * 0.38, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
                    .frame(width: size, height: size).background(Color.appFill, in: Circle())
                    .overlay(Circle().stroke(Color.appBackground, lineWidth: 2.5))
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(members.map(\.name).joined(separator: ", "))
    }

    private var crown: some View {
        Image(systemName: "crown.fill")
            .font(.system(size: size * 0.3, weight: .bold)).foregroundStyle(.white)
            .frame(width: size * 0.5, height: size * 0.5)
            .background(Color.appWarning, in: Circle())
            .overlay(Circle().stroke(Color.appBackground, lineWidth: 1.5))
            .offset(x: size * 0.14, y: -size * 0.14)
    }
}

/// Beranda's left side while the Workspace is open to testers: who the numbers below belong to.
struct WorkspacePill: View {
    @ObservedObject private var store = WorkspaceStore.shared
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let active = store.active { WorkspaceBadge(active, size: 24) }
                Text(store.active?.displayName ?? L("Workspace Pribadi"))
                    .font(.app(15, weight: .semibold))
                    .foregroundStyle(Color.appText)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.appTextTertiary)
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .frame(height: 36)
            .background(Color.appFill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(L("Workspace aktif: %@", store.active?.displayName ?? L("Workspace Pribadi")))
        .accessibilityHint(L("Pilih Workspace"))
    }
}

/// One line of the switcher and of "Workspace saya".
struct WorkspaceRow<Trailing: View>: View {
    let workspace: Workspace
    /// The faces under the name of a shared Workspace, once known.
    var members: [WorkspaceMember]?
    @ViewBuilder var trailing: () -> Trailing

    var secondLine: String {
        if workspace.isPersonal { return L("Hanya kamu") }
        return workspace.isOwner ? L("Pemilik") : L("Anggota · %lld orang", workspace.memberCount)
    }

    var body: some View {
        HStack(spacing: 14) {
            WorkspaceBadge(workspace)
            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.displayName)
                    .font(.app(16, weight: .semibold))
                    .foregroundStyle(Color.appText)
                    .lineLimit(1)
                if let members, !workspace.isPersonal, !members.isEmpty {
                    WorkspaceMemberStack(members: members)
                } else {
                    Text(secondLine)
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            tag
            trailing()
        }
        .frame(minHeight: 64)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var tag: some View {
        if let days = workspace.daysUntilDeletion {
            Text(L("Dihapus dalam %lld hari", days))
                .font(.app(12, weight: .semibold))
                .foregroundStyle(Color.appError)
        } else if workspace.isReadOnly {
            Text(L("Baca saja"))
                .font(.app(12, weight: .semibold))
                .foregroundStyle(Color.appTextSecondary)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Color.appFill, in: Capsule())
        }
    }
}

/// Beranda's switcher (K12): Workspace Pribadi first, then the shared ones, then the way to make another.
struct WorkspaceSwitcherSheet: View {
    @ObservedObject private var store = WorkspaceStore.shared
    @Environment(\.dismiss) private var dismiss
    let onCreate: () -> Void
    let onJoin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L("Workspace"))
                    .font(.app(22, weight: .bold)).tracking(-0.3)
                    .foregroundStyle(Color.appText)
                Spacer(minLength: 12)
                Button { dismiss(); onJoin() } label: {
                    Text(L("Punya kode?"))
                        .font(.app(13, weight: .semibold)).foregroundStyle(Color.appPrimary)
                        .padding(.horizontal, 12).frame(height: 32)
                        .background(Color.appPrimary.opacity(0.12), in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 8)

            if store.loadFailed && store.spaces.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("Daftar Workspace belum bisa dimuat."))
                        .font(.app(15)).foregroundStyle(Color.appTextSecondary)
                    Button(L("Coba lagi")) { Task { await store.load() } }
                        .font(.app(15, weight: .semibold)).foregroundStyle(Color.appPrimary)
                }
                .padding(.horizontal, 24).padding(.vertical, 12)
            }

            ForEach(store.spaces.filter { $0.daysUntilDeletion == nil }) { workspace in
                Button { choose(workspace) } label: {
                    WorkspaceRow(workspace: workspace, members: store.memberPreviews[workspace.id]) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.appPrimary)
                            .opacity(workspace.id == store.active?.id ? 1 : 0)
                    }
                    .padding(.horizontal, 24)
                }
                .buttonStyle(RowPressStyle())
                .accessibilityAddTraits(workspace.id == store.active?.id ? .isSelected : [])
            }
        }
        .filterSheet {
            SmartSheetFooter(primary: L("Tambah Workspace"), primaryIcon: "plus", onPrimary: { dismiss(); onCreate() })
        }
        .task { await store.loadMemberPreviews() }
    }

    private func choose(_ workspace: Workspace) {
        UISelectionFeedbackGenerator().selectionChanged()
        dismiss()
        store.open(workspace)
    }
}

/// Root-level host for the create flow, so the switcher and "Workspace saya" can both start it and the right thing opens:
/// the upgrade flow for a guest (K18), the Plus offer at the limit (K29), else the wizard.
struct WorkspaceHost: ViewModifier {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @ObservedObject private var store = WorkspaceStore.shared
    @State private var plusReason: PlusReason?
    @State private var showsWizard = false
    @State private var showsJoin = false
    @State private var showsNews = false
    private static let newsKey = "workspaceNewsSeen"

    func body(content: Content) -> some View {
        content
            // K37: a "Baru" sheet, once, after Workspace opens to the person
            .task(id: store.hasLoaded) {
                guard store.hasLoaded, store.showsSwitcher, !UserDefaults.standard.bool(forKey: Self.newsKey) else { return }
                try? await Task.sleep(for: .milliseconds(1500))
                guard !Task.isCancelled else { return }
                UserDefaults.standard.set(true, forKey: Self.newsKey)
                showsNews = true
            }
            .sheet(isPresented: $showsNews) {
                WorkspaceNewsSheet { showsNews = false; store.requestCreate() }
            }
            .onChange(of: store.createRequests) { _, _ in start() }
            .onChange(of: store.joinRequests) { _, _ in
                if authViewModel.currentUser?.isGuest == true { authViewModel.startGuestLink() } else { showsJoin = true }
            }
            .sheet(isPresented: $showsJoin) { JoinWorkspaceSheet() }
            .sheet(item: $store.notice) { notice in
                WorkspaceNoticeSheet(notice: notice)
            }
            .onChange(of: store.resetNotice) { _, notice in
                guard notice else { return }
                store.resetNotice = false
                ToastCenter.shared.show(L("Workspace default-mu sudah tidak tersedia. Saku membuka Workspace Pribadi."))
                if let personal = store.personal { Task { try? await store.setDefault(personal) } }
            }
            .fullScreenCover(isPresented: $showsWizard) {
                CreateWorkspaceView { plusReason = .workspaces }
            }
            .plusOffer($plusReason)
    }

    private func start() {
        if authViewModel.currentUser?.isGuest == true { authViewModel.startGuestLink(); return }
        if !PlusStore.shared.isPlus, !store.owned.isEmpty { plusReason = .workspaces; return }
        showsWizard = true
    }
}

extension View {
    func workspaceHost() -> some View { modifier(WorkspaceHost()) }
}


/// On Beranda: why the open Workspace is read-only (K9, A3, only the Owner gets the button) or when it will be deleted (K21).
struct WorkspaceStatusBanner: View {
    @ObservedObject private var store = WorkspaceStore.shared
    @State private var plusReason: PlusReason?
    @State private var failed = false

    var body: some View {
        if let workspace = store.active, !workspace.isPersonal {
            if let days = workspace.daysUntilDeletion {
                banner(icon: "trash", tone: .critical,
                       text: L("Workspace ini dihapus dalam %lld hari. Semua data ikut hilang.", days),
                       action: workspace.isOwner ? (L("Batalkan penghapusan"), { cancel(workspace) }) : nil)
            } else if workspace.isReadOnly {
                banner(icon: "lock", tone: .warning,
                       text: workspace.isOwner ? L("Plus-mu berakhir, jadi Workspace ini baca saja untuk semua anggota.")
                                              : L("Plus Pemilik berakhir, jadi Workspace ini baca saja untuk semua anggota."),
                       action: workspace.isOwner ? (L("Aktifkan Plus lagi"), { plusReason = .general }) : nil)
            }
        }
    }

    @ViewBuilder
    private func banner(icon: String, tone: NoticeTone, text: String, action: (String, () -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            NoticeLine(icon: icon, tone: tone, text: text)
            if let action {
                Button(action.0, action: action.1)
                    .font(.app(14, weight: .semibold)).foregroundStyle(Color.appPrimaryText)
                    .frame(minHeight: 44).padding(.horizontal, 24)
            }
        }
        .plusOffer($plusReason)
        .confirmDialog(isPresented: $failed, icon: "exclamationmark.triangle", title: L("Belum berhasil"),
                       message: L("Periksa koneksi internetmu lalu coba lagi."), confirmTitle: nil, cancelTitle: L("Tutup"))
    }

    private func cancel(_ workspace: Workspace) {
        Task {
            do { try await store.cancelDeletion(of: workspace) } catch { failed = true }
        }
    }
}


/// "Baru": one sheet that tells a person Workspace exists (K37).
struct WorkspaceNewsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCreate: () -> Void

    var body: some View {
        SmartSheet(tone: .consent, icon: "person.2.fill", title: L("Catat uang bersama di Workspace"),
                   message: L("Ajak pasangan, keluarga, atau rekan usaha. Setiap catatan menunjukkan siapa yang mencatat. Workspace Pribadi-mu tetap milikmu sendiri.")) {
            SmartSheetFooter(primary: L("Tambah Workspace"), secondary: L("Nanti saja"), onPrimary: onCreate, onSecondary: { dismiss() })
        }
    }
}

/// One message about a Workspace (access lost, draft saved, read-only, owner-only, applies to all). A sheet, not a toast.
struct WorkspaceNoticeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let notice: WorkspaceStore.Notice

    var body: some View {
        SmartSheet(tone: notice.kind == .draftSaved || notice.kind == .sharedChange ? .consent : .neutral,
                   icon: notice.icon, title: notice.title, message: notice.message) {
            SmartSheetFooter(primary: L("Mengerti"), onPrimary: { dismiss() })
        }
    }
}

/// A list of choices on the shared sheet frame (replaces the system action sheet): a title, an optional line, tappable rows, Batal.
/// The picked action runs once the sheet is gone, so it may open another sheet.
struct WorkspaceChoiceSheet: View {
    struct Option: Identifiable {
        let id = UUID()
        let title: String
        var icon: String?
        var workspace: Workspace?
        var destructive = false
        let action: () -> Void
    }

    @Environment(\.dismiss) private var dismiss
    let title: String
    var message: String?
    let options: [Option]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.app(22, weight: .bold)).tracking(-0.3).fixedSize(horizontal: false, vertical: true)
            if let message {
                Text(message).font(.app(15)).foregroundStyle(Color.appTextSecondary).lineSpacing(2).padding(.top, 6)
            }
            VStack(spacing: 0) {
                ForEach(options) { option in
                    Button {
                        dismiss()
                        Task { try? await Task.sleep(for: .milliseconds(450)); option.action() }
                    } label: {
                        HStack(spacing: 12) {
                            if let workspace = option.workspace { WorkspaceBadge(workspace, size: 36) }
                            else if let icon = option.icon {
                                Image(systemName: icon).font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(option.destructive ? Color.appError : Color.appTextSecondary)
                                    .frame(width: 36, height: 36).background(Color.appFill, in: Circle())
                            }
                            Text(option.title).font(.app(16, weight: .medium))
                                .foregroundStyle(option.destructive ? Color.appError : Color.appText)
                            Spacer(minLength: 8)
                        }
                        .frame(minHeight: 56).contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                }
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Color.appText)
        .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 12)
        .filterSheet { SmartSheetFooter(secondary: L("Batal"), onSecondary: { dismiss() }) }
        .background(Color.appBackground)
    }
}
