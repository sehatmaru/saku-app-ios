import SwiftUI

private let expiryFormat: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "d MMM"
    f.locale = AppLanguage.locale
    return f
}()

/// Undang anggota (K7, K23): the live code to share, copy, renew or revoke. Typed in, not a link (TD: no domain yet).
struct InviteSheet: View {
    let workspace: Workspace
    @ObservedObject private var store = WorkspaceStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var invite: WorkspaceInvite?
    @State private var isLoading = true
    @State private var failure: String?
    @State private var revoked = false
    @State private var confirmsRenew = false
    @State private var confirmsRevoke = false

    private var shareText: String {
        guard let invite else { return "" }
        let until = invite.expiryDate.map { expiryFormat.string(from: $0) } ?? ""
        return L("Gabung ke Workspace %@ di Saku. Kode undangan: %@. Berlaku sampai %@.", workspace.displayName, InviteCode.grouped(invite.code), until)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Undang anggota")).font(.app(22, weight: .bold)).tracking(-0.3).foregroundStyle(Color.appText)
                Text(L("Bagikan kode ini. Siapa pun yang punya kodenya bisa bergabung sampai Workspace berisi 5 anggota."))
                    .font(.app(15)).foregroundStyle(Color.appTextSecondary).lineSpacing(2)
            }
            .padding(.horizontal, 24).padding(.top, 20)

            codeCard.padding(.horizontal, 24).padding(.top, 18)

            if let failure {
                Text(failure).font(.app(13)).foregroundStyle(Color.appError).padding(.horizontal, 24).padding(.top, 10)
            }

            if invite != nil {
                VStack(spacing: 0) {
                    actionRow(L("Salin kode"), icon: "doc.on.doc") { copy() }
                    actionRow(L("Buat kode baru"), icon: "arrow.clockwise") { confirmsRenew = true }
                    actionRow(L("Cabut kode"), icon: "xmark.circle", destructive: true) { confirmsRevoke = true }
                }
                .padding(.horizontal, 24).padding(.top, 8)
            }
        }
        .task { await load() }
        .confirmDialog(isPresented: $confirmsRenew, icon: "arrow.triangle.2.circlepath", title: L("Buat kode baru?"),
                       message: L("Kode yang lama langsung tidak berlaku."), confirmTitle: L("Buat kode baru")) {
            confirmsRenew = false
            Task { await load(renew: true) }
        }
        .confirmDialog(isPresented: $confirmsRevoke, icon: "xmark.circle", destructive: true, title: L("Cabut kode?"),
                       message: L("Tidak ada yang bisa bergabung dengan kode ini lagi. Anggota yang sudah masuk tetap di Workspace."),
                       confirmTitle: L("Cabut kode")) {
            confirmsRevoke = false
            Task { await revoke() }
        }
        .filterSheet { footer }
    }

    private var codeCard: some View {
        VStack(spacing: 6) {
            Group {
                if let invite {
                    Text(InviteCode.grouped(invite.code))
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(Color.appText)
                        .minimumScaleFactor(0.7).lineLimit(1)
                        .textSelection(.enabled)
                } else if revoked {
                    Text(L("Tidak ada kode aktif")).font(.app(17, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
                } else {
                    ProgressView()
                }
            }
            .frame(height: 44)
            Text(subline).font(.app(13)).foregroundStyle(Color.appTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var subline: String {
        if let invite, let date = invite.expiryDate { return L("Berlaku sampai %@", expiryFormat.string(from: date)) }
        return revoked ? L("Buat kode baru untuk mengundang") : " "
    }

    private func actionRow(_ title: String, icon: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 19)).foregroundStyle(destructive ? Color.appError : Color.appTextSecondary).frame(width: 24)
                Text(title).font(.app(16)).foregroundStyle(destructive ? Color.appError : Color.appText)
                Spacer(minLength: 8)
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }

    @ViewBuilder private var footer: some View {
        if invite != nil {
            ShareLink(item: shareText) {
                Label(L("Bagikan"), systemImage: "square.and.arrow.up")
                    .font(.app(17, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(Color.appPrimary, in: Capsule())
            }
            .buttonStyle(PressScaleStyle())
        } else if revoked {
            SmartSheetFooter(primary: L("Buat kode"), isBusy: isLoading, onPrimary: { Task { await load(renew: true) } })
        } else {
            SmartSheetFooter(primary: L("Tutup"), onPrimary: { dismiss() })
        }
    }

    private func load(renew: Bool = false) async {
        isLoading = true
        failure = nil
        defer { isLoading = false }
        do {
            invite = try await store.invite(for: workspace, renew: renew)
            revoked = false
        } catch let error as WorkspaceError {
            failure = error == .ownerDeleting
                ? L("Akunmu sedang dalam masa penghapusan, jadi belum bisa membuat undangan.")
                : L("Kode belum bisa dibuat. Coba lagi.")
        } catch { failure = L("Kode belum bisa dibuat. Coba lagi.") }
    }

    private func revoke() async {
        do {
            try await store.revokeInvite(of: workspace)
            invite = nil
            revoked = true
            failure = nil
        } catch { failure = L("Kode belum bisa dicabut. Coba lagi.") }
    }

    private func copy() {
        guard let invite else { return }
        UIPasteboard.general.string = InviteCode.grouped(invite.code)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        ToastCenter.shared.show(L("Kode disalin"))
    }
}

/// Gabung dengan kode (US4): type the code, see whose Workspace it is, join. The first shared Workspace asks for the default once (A1).
struct JoinWorkspaceSheet: View {
    @ObservedObject private var store = WorkspaceStore.shared
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable { case entry, preview(InvitePreview), joined(UUID) }

    @State private var phase: Phase = .entry
    @State private var text = ""
    @State private var problem: String?
    @State private var isBusy = false
    @State private var wasFirst = false
    @State private var showsMerge = false
    @State private var mergeTarget: UUID?
    @State private var opensAtLaunch = false
    @FocusState private var focused: Bool
    /// Medium until the keyboard comes up, full while it is up, medium again after.
    @State private var detent: PresentationDetent = .medium

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch phase {
            case .entry: entry
            case .preview(let preview): previewView(preview)
            case .joined(let id): joined(id)
            }
        }
        .animation(.settle(0.36), value: phase)
        .disabled(isBusy)
        .filterSheet(detent: $detent, atLeastMedium: true) { footer }
        // the buttons stay where they are; the keyboard simply covers them while it is up
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .scrollDismissesKeyboard(.interactively)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in detent = .large }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in detent = .medium }
    }

    // MARK: Phases

    private var entry: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Gabung ke Workspace")).font(.app(22, weight: .bold)).tracking(-0.3).foregroundStyle(Color.appText)
            Text(L("Masukkan kode 8 karakter dari Pemilik Workspace."))
                .font(.app(15)).foregroundStyle(Color.appTextSecondary)
            codeSlots
                .frame(maxWidth: .infinity)
                .padding(.top, 28)
                .background {
                    // the system keyboard types into this field; the boxes only show what it holds
                    TextField("", text: $text)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit { focused = false }
                        .frame(width: 1, height: 1).clipped().opacity(0.01)
                        .onChange(of: text) { _, value in
                            let clean = InviteCode.normalized(value)
                            if clean != value { text = clean }
                            problem = nil
                        }
                }
                .contentShape(Rectangle())
                .onTapGesture { focused = true }
            Button { text = InviteCode.normalized(UIPasteboard.general.string ?? ""); problem = nil } label: {
                Label(L("Tempel dari papan klip"), systemImage: "doc.on.clipboard")
                    .font(.app(14, weight: .semibold)).foregroundStyle(Color.appPrimary)
                    .padding(.horizontal, 20).frame(height: 50)
                    .background(Color.appPrimary.opacity(0.12), in: Capsule())
            }
            .buttonStyle(PressScaleStyle())
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            if text.isEmpty {
                Text(L("Contoh: ABCD EFGH"))
                    .font(.app(14)).foregroundStyle(Color.appTextSecondary)
                    .frame(maxWidth: .infinity).padding(.top, 14)
            }
            if let problem {
                Text(problem).font(.app(14)).foregroundStyle(Color.appError).frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 16)
            }
        }
        .padding(.horizontal, 24).padding(.top, 20)
    }

    /// The typed code in the same face the Owner sees it: big, monospaced, two groups of four.
    private var codeSlots: some View {
        Text(text.isEmpty ? "ABCD EFGH" : InviteCode.grouped(text))
            .font(.system(size: 34, weight: .bold, design: .monospaced))
            .tracking(2)
            .foregroundStyle(text.isEmpty ? Color.appTextTertiary : Color.appText)
            .minimumScaleFactor(0.7).lineLimit(1)
            .accessibilityLabel(L("Kode undangan"))
            .accessibilityValue(text)
    }

    private func previewView(_ preview: InvitePreview) -> some View {
        VStack(spacing: 8) {
            WorkspaceBadge(icon: preview.icon, color: preview.color, size: 72).padding(.top, 8)
            Text(preview.name ?? "").font(.app(22, weight: .bold)).tracking(-0.3).foregroundStyle(Color.appText)
            Text(L("Pemilik: %@", preview.ownerName ?? "-")).font(.app(15)).foregroundStyle(Color.appTextSecondary)
            Text(L("%lld dari 5 anggota", preview.memberCount ?? 0)).font(.app(13)).foregroundStyle(Color.appTextSecondary)
            if let problem {
                Text(problem).font(.app(13)).foregroundStyle(Color.appError).multilineTextAlignment(.center).padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24).padding(.top, 28)
    }

    private func joined(_ id: UUID) -> some View {
        let workspace = store.spaces.first { $0.id == id }
        return VStack(spacing: 8) {
            if let workspace { WorkspaceBadge(workspace, size: 72).padding(.top, 8) }
            Text(L("Kamu sudah bergabung")).font(.app(22, weight: .bold)).tracking(-0.3).foregroundStyle(Color.appText)
            Text(L("%@ ada di daftar Workspace-mu.", workspace?.displayName ?? ""))
                .font(.app(15)).foregroundStyle(Color.appTextSecondary).multilineTextAlignment(.center)
            if wasFirst {
                Toggle(isOn: $opensAtLaunch) {
                    Text(L("Buka Workspace ini saat app dijalankan")).font(.app(16)).foregroundStyle(Color.appText)
                }
                .tint(Color.appPrimary)
                .frame(minHeight: 48)
                .padding(.top, 14)
            }
            // K39: the offer to bring history, once, right after joining
            Button(L("Gabungkan Workspace Pribadi saya")) { mergeTarget = id; showsMerge = true }
                .font(.app(15, weight: .semibold)).foregroundStyle(Color.appPrimary).frame(minHeight: 44).padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24).padding(.top, 28)
        .sheet(isPresented: $showsMerge) { MergeWizardView(mode: .merge(target: mergeTarget)) }
    }

    @ViewBuilder private var footer: some View {
        switch phase {
        case .entry:
            SmartSheetFooter(primary: L("Lanjut"), isBusy: isBusy, isEnabled: InviteCode.isComplete(text), secondary: L("Batal"),
                             onPrimary: { Task { await check() } }, onSecondary: { dismiss() })
        case .preview(let preview):
            SmartSheetFooter(primary: L("Gabung"), isBusy: isBusy, isEnabled: preview.status == .ok, secondary: L("Kembali"),
                             onPrimary: { Task { await join() } }, onSecondary: { problem = nil; phase = .entry })
        case .joined(let id):
            SmartSheetFooter(primary: L("Buka Workspace"), secondary: L("Tetap di sini"),
                             onPrimary: { Task { await finish(id, open: true) } }, onSecondary: { Task { await finish(id, open: false) } })
        }
    }

    // MARK: Actions

    private func check() async {
        focused = false
        guard InviteCode.isComplete(text) else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await store.preview(code: text)
            if result.status == .ok || result.status == .full || result.status == .alreadyMember, result.spaceId != nil {
                problem = result.status == .ok ? nil : result.status.problem
                phase = .preview(result)
            } else {
                problem = result.status.problem
            }
        } catch let error as WorkspaceError {
            problem = error == .guest ? L("Gabung ke Workspace perlu akun.") : L("Kode belum bisa dicek. Coba lagi.")
        } catch { problem = L("Kode belum bisa dicek. Coba lagi.") }
    }

    private func join() async {
        isBusy = true
        defer { isBusy = false }
        wasFirst = store.shared.isEmpty
        do {
            let result = try await store.join(code: text)
            if let id = result.spaceId, result.status == .joined || result.status == .alreadyMember {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                phase = .joined(id)
            } else {
                problem = result.status.problem
            }
        } catch { problem = L("Belum bisa bergabung. Coba lagi.") }
    }

    private func finish(_ id: UUID, open: Bool) async {
        if opensAtLaunch, let workspace = store.spaces.first(where: { $0.id == id }) { try? await store.setDefault(workspace) }
        dismiss()
        if open, let workspace = store.spaces.first(where: { $0.id == id }) {
            try? await Task.sleep(for: .milliseconds(350))
            store.open(workspace)
        }
    }
}
