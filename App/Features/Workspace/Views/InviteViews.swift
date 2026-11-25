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

    private static let phaseChange = AnyTransition.asymmetric(
        insertion: .opacity.combined(with: .offset(y: 14)), removal: .opacity)
    /// Counts refused codes, so the code box shakes once per refusal.
    @State private var refusals = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch phase {
            case .entry: entry.transition(Self.phaseChange)
            case .preview(let preview): previewView(preview).transition(Self.phaseChange)
            case .joined(let id): joined(id).transition(Self.phaseChange)
            }
        }
        .animation(.settle(0.36), value: phase)
        .disabled(isBusy)
        .filterSheet(detent: $detent, atLeastMedium: true) { footer }
        // the buttons ride up above the keyboard while it is open, like the other flows
        .scrollDismissesKeyboard(.interactively)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in detent = .large }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in detent = .medium }
    }

    // MARK: Phases

    private var entry: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Gabung ke Workspace")).font(.app(22, weight: .bold)).tracking(-0.3).foregroundStyle(Color.appText)
            Text(L("Masukkan kode 8 karakter dari Pemilik Workspace."))
                .font(.app(15)).foregroundStyle(Color.appTextSecondary)
            codeSlots
                .frame(maxWidth: .infinity).frame(height: 84)
                .background(Color.appSheetField, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(problem != nil ? Color.appError : (focused ? Color.appPrimary : Color.clear), lineWidth: 1.5)
                }
                .animation(.settle(0.2), value: problem)
                .animation(.settle(0.2), value: focused)
                .keyframeAnimator(initialValue: 0.0, trigger: refusals) { view, x in view.offset(x: x) } keyframes: { _ in
                    KeyframeTrack {
                        LinearKeyframe(-9, duration: 0.05); LinearKeyframe(9, duration: 0.08)
                        LinearKeyframe(-6, duration: 0.08); LinearKeyframe(4, duration: 0.07); LinearKeyframe(0, duration: 0.06)
                    }
                }
                .padding(.top, 24)
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
                .onTapGesture { openKeyboard() }
            // the error shows under the box and gives way again when it clears
            if let problem {
                Text(problem).foregroundStyle(Color.appError)
                    .font(.app(14)).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10).padding(.horizontal, 4)
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }
            Button { text = InviteCode.normalized(UIPasteboard.general.string ?? ""); problem = nil } label: {
                Label(L("Tempel dari papan klip"), systemImage: "doc.on.clipboard")
                    .font(.app(14, weight: .semibold)).foregroundStyle(Color.appPrimary)
                    .padding(.horizontal, 20).frame(height: 44)
                    .background(Color.appPrimary.opacity(0.12), in: Capsule())
            }
            .buttonStyle(PressScaleStyle())
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
        }
        .animation(.settle(0.25), value: problem)
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
        VStack(spacing: 0) {
            WorkspaceBadge(icon: preview.icon, color: preview.color, size: 88, imageUrl: preview.imageUrl).popIn()
            Text(preview.name ?? "").font(.app(24, weight: .bold)).tracking(-0.3).foregroundStyle(Color.appText)
                .multilineTextAlignment(.center).lineLimit(2).padding(.top, 16)
            VStack(spacing: 0) {
                previewRow(L("Pemilik"), preview.ownerName ?? "-")
                Divider().overlay(Color.appBorder.opacity(0.6))
                previewRow(L("Anggota"), L("%lld dari 5", preview.memberCount ?? 0))
            }
            .padding(.horizontal, 16)
            .background(Color.appSheetField, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.top, 24)
            if let problem {
                Text(problem).font(.app(13)).foregroundStyle(Color.appError).multilineTextAlignment(.center).padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24).padding(.top, 20)
    }

    private func previewRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.app(15)).foregroundStyle(Color.appTextSecondary)
            Spacer(minLength: 12)
            Text(value).font(.app(15, weight: .semibold)).foregroundStyle(Color.appText).lineLimit(1)
        }
        .frame(minHeight: 52)
    }

    private func joined(_ id: UUID) -> some View {
        let workspace = store.spaces.first { $0.id == id }
        return VStack(spacing: 8) {
            if let workspace { WorkspaceBadge(workspace, size: 72).padding(.top, 8).popIn() }
            Text(L("Kamu sudah bergabung")).font(.app(22, weight: .bold)).tracking(-0.3).foregroundStyle(Color.appText)
            Text(L("%@ ada di daftar Workspace-mu.", workspace?.displayName ?? ""))
                .font(.app(15)).foregroundStyle(Color.appTextSecondary).multilineTextAlignment(.center)
            if wasFirst {
                Toggle(isOn: $opensAtLaunch) {
                    Text(L("Jadikan Default Workspace")).font(.app(16)).foregroundStyle(Color.appText)
                }
                .tint(Color.appPrimary)
                .frame(minHeight: 48)
                .padding(.top, 14)
            }
            // K39: the offer to bring history, once, right after joining
            Button(L("Bawa data pribadi saya")) { mergeTarget = id; showsMerge = true }
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

    /// The sheet grows first and the keyboard follows, so the buttons never ride up inside a sheet that is still short.
    private func openKeyboard() {
        guard !focused else { return }
        detent = .large
        Task {
            try? await Task.sleep(for: .milliseconds(280))
            focused = true
        }
    }

    private func refuse(_ message: String) {
        problem = message
        refusals += 1
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

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
                refuse(result.status.problem ?? L("Kode belum bisa dicek. Coba lagi."))
            }
        } catch let error as WorkspaceError {
            refuse(error == .guest ? L("Gabung ke Workspace perlu akun.") : L("Kode belum bisa dicek. Coba lagi."))
        } catch { refuse(L("Kode belum bisa dicek. Coba lagi.")) }
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


/// The badge grows in with a soft spring when its screen appears.
private struct PopIn: ViewModifier {
    @State private var shown = false
    func body(content: Content) -> some View {
        content.scaleEffect(shown ? 1 : 0.7).opacity(shown ? 1 : 0)
            .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.72).delay(0.08)) { shown = true } }
    }
}
private extension View { func popIn() -> some View { modifier(PopIn()) } }
