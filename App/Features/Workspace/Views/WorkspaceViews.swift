import SwiftUI

/// The colour a workspace carries: one of `WalletIcon.presetColors` by name (K32).
enum WorkspaceStyle {
    static func color(_ name: String?) -> Color {
        name.flatMap(WalletIcon.presetColor(named:)) ?? Color.appPrimary
    }
}

/// A workspace's face: its colour with its icon in white.
struct WorkspaceBadge: View {
    let icon: String?
    let color: String?
    var size: CGFloat = 40

    init(icon: String?, color: String?, size: CGFloat = 40) {
        self.icon = icon; self.color = color; self.size = size
    }

    init(_ workspace: Workspace, size: CGFloat = 40) {
        self.init(icon: workspace.isPersonal ? "person.fill" : workspace.icon, color: workspace.isPersonal ? "abu" : workspace.color, size: size)
    }

    var body: some View {
        Circle()
            .fill(WorkspaceStyle.color(color))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: icon ?? "person.2.fill")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
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
                Text(secondLine)
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
                    .lineLimit(1)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Workspace"))
                .font(.app(22, weight: .bold)).tracking(-0.3)
                .foregroundStyle(Color.appText)
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

            ForEach(store.spaces) { workspace in
                Button { choose(workspace) } label: {
                    WorkspaceRow(workspace: workspace) {
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
            SmartSheetFooter(primary: L("Buat Workspace"), primaryIcon: "plus", onPrimary: { dismiss(); onCreate() })
        }
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

    func body(content: Content) -> some View {
        content
            .onChange(of: store.createRequests) { _, _ in start() }
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
