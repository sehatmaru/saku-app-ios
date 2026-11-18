import SwiftUI

/// Gabungkan Workspace Pribadi ke Workspace bersama, dengan riwayat (K39, A6), and Bawa data saya from a Workspace that is
/// being deleted (K42). One wizard: the summary and warnings, the category map, the confirmation. All or nothing.
struct MergeWizardView: View {
    enum Mode: Equatable {
        /// Workspace Pribadi into one of the person's shared Workspaces; `target` preselects it.
        case merge(target: UUID?)
        /// The person's own wallets of a Workspace in its grace period, into Workspace Pribadi.
        case rescue(space: UUID)
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = WorkspaceStore.shared
    let mode: Mode

    private enum Step { case summary, mapping, confirm, done }
    private enum Load { case loading, ready, failed, limit }

    @State private var step: Step = .summary
    @State private var targetId: UUID?
    @State private var preview: MovePreview?
    @State private var load: Load = .loading
    @State private var choice: [String: String] = [:]
    @State private var isMoving = false
    @State private var result: MoveResult?
    @State private var notice: String?

    private var isRescue: Bool { if case .rescue = mode { true } else { false } }

    /// Shared Workspaces that take records: not read-only, not waiting to be deleted.
    private var targets: [Workspace] { store.shared.filter { !$0.isReadOnly && $0.daysUntilDeletion == nil } }
    private var spaceId: UUID? {
        if case .rescue(let space) = mode { return space }
        return targetId ?? targets.first?.id
    }
    private var needsMapping: [MovePreview.Source] { preview?.needsMapping ?? [] }
    private var mappingComplete: Bool { needsMapping.allSatisfy { choice[$0.id] != nil } }
    private var destinationName: String {
        isRescue ? L("Workspace Pribadi") : (preview?.targetName ?? targets.first(where: { $0.id == spaceId })?.displayName ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                content.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            buttons
        }
        .background(Color.appBackground)
        .foregroundStyle(Color.appText)
        .interactiveDismissDisabled(isMoving)
        .task { if case .merge(let preset) = mode { targetId = preset ?? targets.first?.id }; await reload() }
    }

    // MARK: Chrome

    private var topBar: some View {
        ZStack {
            HStack {
                if step == .done { Color.clear.frame(width: 44) }
                else {
                    Button(step == .summary ? L("Batal") : L("Kembali")) { back() }
                        .font(.app(17)).foregroundStyle(Color.appPrimary).disabled(isMoving)
                }
                Spacer()
            }
            Text(isRescue ? L("Bawa data saya") : L("Gabungkan dengan riwayat")).font(.app(17, weight: .semibold)).lineLimit(1).padding(.horizontal, 90)
        }
        .padding(.horizontal, 20).frame(height: 44)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .summary: summary
        case .mapping: mapping
        case .confirm: confirm
        case .done: done
        }
    }

    // MARK: Steps

    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isRescue ? L("Bawa dompetmu keluar") : L("Ke Workspace mana?")).font(.app(22, weight: .bold)).tracking(-0.3)
            if isRescue {
                Text(L("%@ akan dihapus. Dompet yang kamu buat dan semua transaksinya pindah ke Workspace Pribadi-mu. Dompet anggota lain tetap di sana.", preview?.targetName ?? ""))
                    .font(.app(15)).foregroundStyle(Color.appTextSecondary).lineSpacing(2).padding(.top, 6)
            } else if targets.count > 1 {
                VStack(spacing: 0) {
                    ForEach(targets) { workspace in
                        Button {
                            targetId = workspace.id
                            Task { await reload() }
                        } label: {
                            HStack(spacing: 12) {
                                WorkspaceBadge(workspace, size: 36)
                                Text(workspace.displayName).font(.app(16, weight: .medium))
                                Spacer(minLength: 8)
                                Image(systemName: "checkmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.appPrimary)
                                    .opacity(workspace.id == spaceId ? 1 : 0)
                            }
                            .frame(minHeight: 56).contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                    }
                }
                .padding(.top, 8)
            }
            switch load {
            case .loading: ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
            case .failed:
                Text(L("Ringkasan belum bisa dimuat. Periksa koneksi lalu coba lagi.")).font(.app(15)).foregroundStyle(Color.appTextSecondary).padding(.top, 16)
                Button(L("Coba lagi")) { Task { await reload() } }.font(.app(15, weight: .semibold)).foregroundStyle(Color.appPrimary).padding(.top, 8)
            case .ready, .limit:
                if let notice { Text(notice).font(.app(14)).foregroundStyle(Color.appError).padding(.top, 12) }
                if let preview {
                    VStack(alignment: .leading, spacing: 10) {
                        statRow("wallet.bifold", L("%lld dompet", preview.wallets) + (preview.cards > 0 ? L(" · %lld kartu kredit", preview.cards) : ""))
                        statRow("list.bullet", L("%lld transaksi", preview.transactions))
                    }
                    .padding(.top, 16)
                    if load == .limit {
                        warning(L("%@ sudah hampir penuh. Batas dompet gratis Workspace mengikuti Pemilik, jadi %lld dompet uang tidak muat. Kurangi dompet dulu atau minta Pemilik berlangganan Plus.", preview.targetName, preview.moneyAfter))
                    }
                    warning(isRescue ? L("Budget, preferensi kategori, dan draf tidak ikut pindah.")
                            : L("Seluruh riwayatmu akan terlihat semua anggota %@. Tidak bisa dibatalkan.", preview.targetName))
                    if !isRescue {
                        warning(L("Data yang sudah pindah tetap ada di %@ meski nanti kamu keluar atau dikeluarkan. Budget, preferensi kategori, awal periode, dan draf tidak ikut.", preview.targetName))
                    }
                }
            }
        }
    }

    private var mapping: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Samakan kategorinya")).font(.app(22, weight: .bold)).tracking(-0.3)
            Text(preview?.canCreate == true
                 ? L("Kategori dengan nama yang sama sudah dicocokkan. Sisanya dibuat baru di %@, atau kamu pilih kategori yang ada.", destinationName)
                 : L("Hanya Pemilik yang bisa membuat kategori baru. Pilih kategori %@ untuk setiap kategori di bawah.", destinationName))
                .font(.app(15)).foregroundStyle(Color.appTextSecondary).lineSpacing(2).padding(.top, 6)
            VStack(spacing: 0) {
                ForEach(needsMapping) { category in mappingRow(category) }
            }
            .padding(.top, 12)
        }
    }

    private func mappingRow(_ category: MovePreview.Source) -> some View {
        let options = (preview?.destination ?? []).filter { $0.kind == category.kind }
        let picked = choice[category.id]
        let label: String = picked == "new" ? L("Buat baru")
            : options.first(where: { $0.id == picked })?.name ?? L("Pilih kategori")
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name).font(.app(16, weight: .medium)).lineLimit(1)
                Text(L("%lld catatan", category.uses)).font(.app(13)).foregroundStyle(Color.appTextSecondary)
            }
            Spacer(minLength: 8)
            Menu {
                if preview?.canCreate == true {
                    Button(L("Buat baru")) { choice[category.id] = "new" }
                }
                ForEach(options) { option in
                    Button(option.hidden ? L("%@ · disembunyikan", option.name) : option.name) { choice[category.id] = option.id }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(label).font(.app(15, weight: .medium)).foregroundStyle(picked == nil ? Color.appError : Color.appPrimary).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.appTextTertiary)
                }
            }
        }
        .frame(minHeight: 60)
    }

    private var confirm: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isRescue ? L("Bawa data ke Workspace Pribadi?") : L("Gabungkan ke %@?", destinationName)).font(.app(22, weight: .bold)).tracking(-0.3)
            if let preview {
                Text(L("%lld dompet dan %lld transaksi pindah. Semua atau tidak sama sekali.", preview.wallets, preview.transactions))
                    .font(.app(15)).foregroundStyle(Color.appTextSecondary).lineSpacing(2).padding(.top, 6)
                warning(isRescue ? L("Setelah pindah, datanya ada di Workspace Pribadi-mu dan tidak ikut terhapus bersama %@.", preview.targetName)
                        : L("Seluruh riwayat ini terlihat semua anggota %@ dan tidak bisa dibatalkan.", preview.targetName))
            }
            if let notice { Text(notice).font(.app(14)).foregroundStyle(Color.appError).padding(.top, 12) }
        }
    }

    private var done: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(Color.appPrimary).padding(.top, 40)
            Text(L("Sudah pindah")).font(.app(22, weight: .semibold)).tracking(-0.3)
            Text(L("%lld dompet dan %lld transaksi sekarang ada di %@.", result?.wallets ?? 0, result?.transactions ?? 0, destinationName))
                .font(.app(15)).foregroundStyle(Color.appTextSecondary).multilineTextAlignment(.center).lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
    }

    private func statRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(Color.appTextSecondary).frame(width: 24)
            Text(text).font(.app(16))
        }
    }

    private func warning(_ text: String) -> some View {
        Text(text).font(.app(14)).foregroundStyle(Color.appTextSecondary).lineSpacing(2)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 14)
    }

    // MARK: Buttons

    private var buttons: some View {
        VStack(spacing: 10) {
            switch step {
            case .summary:
                primary(L("Lanjut"), enabled: load == .ready && (preview?.wallets ?? 0) + (preview?.transactions ?? 0) > 0) { step = needsMapping.isEmpty ? .confirm : .mapping }
                if load == .ready, let preview, preview.wallets + preview.transactions == 0 {
                    Text(L("Tidak ada dompet atau transaksi yang bisa dipindah.")).font(.app(13)).foregroundStyle(Color.appTextSecondary)
                }
            case .mapping: primary(L("Lanjut"), enabled: mappingComplete) { step = .confirm }
            case .confirm: primary(isRescue ? L("Bawa data saya") : L("Gabungkan"), enabled: true, busy: isMoving) { Task { await move() } }
            case .done: primary(L("Selesai"), enabled: true) { dismiss() }
            }
        }
        .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 12).background(Color.appBackground)
    }

    private func primary(_ title: String, enabled: Bool, busy: Bool = false, action: @escaping () -> Void) -> some View {
        PrimaryButton(title: title, isLoading: busy, isEnabled: enabled, action: action)
    }

    // MARK: Actions

    private func back() {
        switch step {
        case .summary: dismiss()
        case .mapping: step = .summary
        case .confirm: step = needsMapping.isEmpty ? .summary : .mapping
        case .done: break
        }
    }

    private func reload() async {
        guard let space = spaceId else { load = .failed; return }
        load = .loading
        do {
            let fresh = try await store.movePreview(rescue: isRescue, space: space)
            preview = fresh
            // the answers follow the fresh suggestions; a category the person already chose keeps the choice if it still exists
            var next: [String: String] = [:]
            for category in fresh.needsMapping {
                if let old = choice[category.id], old == "new" ? fresh.canCreate : fresh.destination.contains(where: { $0.id == old }) { next[category.id] = old }
                else if let suggested = category.suggested { next[category.id] = suggested }
                else if fresh.canCreate { next[category.id] = "new" }
            }
            choice = next
            load = fresh.limitOk ? .ready : .limit
        } catch { load = .failed }
    }

    private func move() async {
        guard let space = spaceId else { return }
        isMoving = true
        notice = nil
        defer { isMoving = false }
        do {
            result = try await store.moveApply(rescue: isRescue, space: space, map: choice)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            step = .done
        } catch let error as WorkspaceError {
            switch error {
            case .walletLimit:
                notice = L("Batas dompet gratis di %@ terlampaui, jadi tidak ada yang dipindah.", destinationName)
            case .mapInvalid, .readOnly:
                // A7: the destination changed since the preview; everything failed and the preview is read again
                notice = L("Workspace tujuan berubah. Tidak ada yang dipindah. Periksa lagi ringkasan dan kategorinya.")
                step = .summary
                await reload()
            case .ownerDeleting: notice = L("Akunmu sedang dalam proses penghapusan, jadi belum bisa memindahkan data.")
            default: notice = L("Belum berhasil. Periksa koneksi lalu coba lagi.")
            }
        } catch { notice = L("Belum berhasil. Periksa koneksi lalu coba lagi.") }
    }
}
