import SwiftUI

/// "Perlu dicek": every draft in one place. One tap saves, tap a row to edit, swipe to delete.
struct DraftQueueView: View {
    let userId: String
    @ObservedObject private var store = DraftStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Draft?
    @State private var savingIds: Set<UUID> = []
    @State private var isSavingAll = false
    @State private var errorMessage: String?
    @AppStorage("isBalanceVisible") private var isBalanceVisible = true

    private var ready: [Draft] { store.drafts.filter(\.isComplete) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("Perlu dicek")).font(.app(24, weight: .bold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.appText)
                        .frame(width: 32, height: 32)
                        .background(Color.appFill, in: Circle())
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            if store.expiringSoon > 0 {
                Label(L("%lld draf akan dihapus dalam 3 hari jika tidak diproses.", store.expiringSoon), systemImage: "clock")
                    .font(.app(13))
                    .foregroundStyle(Color.appWarning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
            }

            if store.drafts.isEmpty {
                EmptyMessage(icon: "checkmark.circle", title: L("Semua sudah dicek"),
                             message: L("Draf dari Catat cepat, Siri, Bagikan, dan notifikasi muncul di sini."))
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.drafts) { draft in
                        DraftRow(draft: draft, store: store, isBalanceVisible: isBalanceVisible,
                                 isSaving: savingIds.contains(draft.id), onSave: { save(draft) })
                            .contentShape(Rectangle())
                            .onTapGesture { editing = draft }
                            .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 20))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.appBackground)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { store.discard(draft.id) } label: { Label(L("Hapus"), systemImage: "trash") }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)

                Button(action: saveAll) {
                    ZStack {
                        if isSavingAll { ProgressView().tint(Color.appBackground) } else {
                            Text(L("Simpan semua (%lld)", ready.count))
                        }
                    }
                    .font(.app(16, weight: .semibold))
                    .foregroundStyle(Color.appBackground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(ready.isEmpty ? Color.appTextTertiary : Color.appText, in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
                .disabled(ready.isEmpty || isSavingAll)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
        }
        .background(Color.appBackground)
        .presentationDetents([.large])
        .presentationBackground(Color.appBackground)
        .sheet(item: $editing) { draft in DraftEditView(draft: draft, store: store) }
        .confirmDialog(isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
                       icon: "exclamationmark.triangle", title: L("Gagal menyimpan"),
                       message: errorMessage ?? "", confirmTitle: nil, cancelTitle: L("Tutup"))
        .task { await store.refreshReferenceData(userId: userId) }
    }

    private func save(_ draft: Draft) {
        guard draft.isComplete else { editing = draft; return }
        savingIds.insert(draft.id)
        Task {
            do { try await store.save(draft, userId: userId) } catch { errorMessage = error.localizedDescription }
            savingIds.remove(draft.id)
        }
    }

    private func saveAll() {
        isSavingAll = true
        Task {
            for draft in ready {
                do { try await store.save(draft, userId: userId) } catch {
                    errorMessage = error.localizedDescription
                    break
                }
            }
            isSavingAll = false
        }
    }
}

private struct DraftRow: View {
    let draft: Draft
    @ObservedObject var store: DraftStore
    let isBalanceVisible: Bool
    let isSaving: Bool
    let onSave: () -> Void

    private func name(_ id: String?) -> String? { store.accounts.first { $0.id == id }?.name }
    private var category: Category? { store.categories.first { $0.id == draft.categoryId } }

    private var sourceIcon: String {
        switch draft.source {
        case .typed: return "keyboard"
        case .voice: return "mic"
        case .siri: return "waveform"
        case .share: return "square.and.arrow.up"
        case .notification: return "bell"
        }
    }

    private var kindLabel: String {
        switch draft.kind {
        case .expense: return L("Pengeluaran")
        case .income: return L("Pemasukan")
        case .transfer: return L("Transfer")
        case .cardPayment: return L("Bayar kartu")
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: category?.icon ?? sourceIcon)
                .font(.system(size: 20))
                .foregroundStyle(Color.appTextSecondary)
                .frame(width: 24)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(draft.title.isEmpty ? kindLabel : draft.title)
                        .font(.app(16, weight: .medium))
                        .foregroundStyle(Color.appText)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text(draft.amount.map { isBalanceVisible ? $0.formattedAsCurrency() : "Rp" + hiddenAmount } ?? "—")
                        .font(.app(16))
                        .monospacedDigit()
                        .foregroundStyle(draft.amount == nil ? Color.appTextTertiary : Color.appText)
                }
                Text([kindLabel, subtitle].compactMap { $0 }.joined(separator: " · "))
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
                    .lineLimit(1)
                ForEach(flags, id: \.self) { flag in
                    Label(flag, systemImage: "exclamationmark.circle")
                        .font(.app(12))
                        .foregroundStyle(Color.appWarning)
                }
                if let note = draft.duplicateNote {
                    Label(note, systemImage: "doc.on.doc")
                        .font(.app(12))
                        .foregroundStyle(Color.appWarning)
                        .lineLimit(2)
                }
            }
            Button(action: onSave) {
                Group {
                    if isSaving { ProgressView() } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(draft.isComplete ? Color.white : Color.appTextTertiary)
                    }
                }
                .frame(width: 36, height: 36)
                .background(draft.isComplete ? Color.appPrimary : Color.appFill, in: Circle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel(L("Simpan"))
        }
        .padding(.vertical, 12)
        .rowSeparator()
    }

    private var subtitle: String? {
        let day = DateFormatter.shortDay.string(from: draft.date)
        switch draft.kind {
        case .transfer, .cardPayment:
            let route = [name(draft.accountId), name(draft.counterpartyAccountId)].compactMap { $0 }.joined(separator: " → ")
            return [route.isEmpty ? nil : route, day].compactMap { $0 }.joined(separator: " · ")
        default:
            return [name(draft.accountId), category?.name, day].compactMap { $0 }.joined(separator: " · ")
        }
    }

    private var flags: [String] {
        if draft.isUnreadable { return [L("Tidak terbaca. Isi nominalnya dulu.")] }
        return draft.missing.compactMap {
            switch $0 {
            case .amount: return L("Isi nominal")
            case .account: return L("Pilih dompet")
            case .counterparty: return draft.needsInvestmentWallet ? L("Pilih dompet aset") : L("Pilih dompet tujuan")
            case .category: return L("Pilih kategori")
            }
        }
    }
}

extension DateFormatter {
    static let shortDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        f.locale = AppLanguage.locale
        return f
    }()
}
