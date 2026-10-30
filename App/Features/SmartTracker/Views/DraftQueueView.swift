import SwiftUI

extension Draft {
    /// Where it came from, in words ("Suara", "Notifikasi BCA").
    var sourceLabel: String {
        switch source {
        case .typed: return L("Ketikan")
        case .voice: return L("Suara")
        case .siri: return "Siri"
        case .share: return L("Dibagikan")
        case .notification: return sourceName.map { L("Notifikasi %@", $0) } ?? L("Notifikasi")
        case .photo: return L("Foto")
        }
    }

    var sourceIcon: String {
        switch source {
        case .typed: return "keyboard"
        case .voice: return "mic"
        case .siri: return "waveform"
        case .share: return "square.and.arrow.up"
        case .notification: return "bell"
        case .photo: return "photo"
        }
    }

    var kindColor: Color {
        switch kind {
        case .expense: return Color.stExpense
        case .income: return Color.stGreen
        case .transfer: return Color.stTransfer
        case .cardPayment: return Color.stCardPayment
        }
    }

    var kindTitle: String {
        switch kind {
        case .expense: return L("Pengeluaran")
        case .income: return L("Pemasukan")
        case .transfer: return L("Transfer")
        case .cardPayment: return L("Bayar kartu")
        }
    }

    var kindIcon: String {
        switch kind {
        case .expense: return "arrow.up.right"
        case .income: return "arrow.down.left"
        case .transfer: return "arrow.left.arrow.right"
        case .cardPayment: return "creditcard"
        }
    }
}

/// "Konfirmasi transaksi" (design "Konfirmasi Transaksi", layout A): every draft is a card you can fix in place.
/// Kategori, Dompet, Tanggal, Tipe and Nominal open the same sheets as Tambah transaksi; Simpan and Abaikan
/// can be undone from the toast. "Simpan semua" only takes the complete ones.
struct DraftQueueView: View {
    let userId: String
    @ObservedObject private var store = DraftStore.shared
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedId: UUID?

    /// Counted for "Semua sudah dicek".
    @State private var saved = 0
    @State private var ignored = 0
    @State private var saving: Set<UUID> = []
@State private var periodChoice: Draft?
    @State private var failures: [UUID: Failure] = [:]
    @State private var sheet: DraftSheet?
    @State private var toast: Toast?
    @State private var showsSaveAll = false
    @State private var showsDeleteAll = false
    @State private var errorMessage: String?

    struct Failure {
        let isOffline: Bool
        let message: String

        init(_ error: Error) {
            let ns = error as NSError
            let offlineCodes = [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut,
                                NSURLErrorCannotConnectToHost, NSURLErrorDataNotAllowed]
            isOffline = ns.domain == NSURLErrorDomain && offlineCodes.contains(ns.code)
            message = FreeLimits.friendly(error).localizedDescription
        }
    }

    struct DraftSheet: Identifiable {
        let draftId: UUID
        let kind: DraftFieldSheet.Kind
        var id: String { "\(draftId)-\(kind)" }
    }

    struct Toast: Identifiable {
        enum Kind { case saved, ignored }
        let id = UUID()
        let text: String
        let drafts: [Draft]
        let transactionIds: [String]
        let kind: Kind
    }

    private enum Level { case unread, partial, complete }

    private func level(_ d: Draft) -> Level {
        if d.isUnreadable { return .unread }
        return d.missing.isEmpty ? .complete : .partial
    }

    private func missingNames(_ d: Draft) -> [String] {
        d.missing.map {
            switch $0 {
            case .amount: L("nominal")
            case .account: L("dompet")
            case .counterparty: L("dompet tujuan")
            case .category: L("kategori")
            }
        }
    }

    private var ready: [Draft] { store.drafts.filter { $0.isComplete && !store.needsPeriodChoice($0) } }

    // MARK: Body

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if !store.drafts.isEmpty || !store.notices.isEmpty {
                    list
                } else if saved + ignored == 0 {
                    emptyQueue
                } else {
                    allChecked
                }
            }
            toastView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .animation(.settle(0.4), value: store.drafts.map(\.id))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !store.drafts.isEmpty {
                    Button { showsDeleteAll = true } label: { Text("Hapus semua").foregroundStyle(Color.appText) }
                }
            }
        }
        .hidesSmartButton()
        .onChange(of: sheet?.id) { focusedId = nil }
        .sheet(item: $sheet) { item in sheetContent(item) }
        .sheet(isPresented: $showsSaveAll) { saveAllSheet }
.sheet(item: $periodChoice) { d in
    EarlySalarySheet(date: d.date) { choice in
        var chosen = d
        chosen.startsPeriod = choice
        save(chosen)
    }
}
        .confirmDialog(isPresented: $showsDeleteAll, icon: "trash", destructive: true,
                       title: L("Hapus semua draf?"),
                       message: L("Semua %lld draf dari Smart Tracker akan dibuang. Transaksi yang sudah tersimpan tidak terpengaruh.", store.drafts.count),
                       confirmTitle: L("Hapus semua")) { deleteAll() }
        .confirmDialog(isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
                       icon: "exclamationmark.triangle", title: L("Gagal"),
                       message: errorMessage ?? "", confirmTitle: nil, cancelTitle: L("Tutup"))
        .onAppear {
            if let id = store.editRequest, store.drafts.contains(where: { $0.id == id }) {
                store.editRequest = nil
                sheet = DraftSheet(draftId: id, kind: .amount)
            }
        }
        .task { await store.refreshReferenceData(userId: userId) }
    }

    // MARK: List

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Konfirmasi transaksi").font(.app(34, weight: .bold)).tracking(0.2)
                    .padding(.horizontal, 24).padding(.top, 6)
                Label {
                    Text(L("%lld draf dicatat otomatis oleh Smart Tracker. Cek dan lengkapi sebelum disimpan.", store.drafts.count))
                } icon: {
                    Image(systemName: "sparkle").foregroundStyle(Color.appPrimary)
                }
                .font(.app(15)).foregroundStyle(Color.appTextSecondary)
                .padding(.horizontal, 24).padding(.top, 8)

                // TC 45: a head-up in the last days before drafts expire (restored after the layout-A redesign dropped it).
                if store.expiringSoon > 0 {
                    Label(L("%lld draf akan dihapus dalam 3 hari jika tidak diproses.", store.expiringSoon), systemImage: "clock")
                        .font(.app(13))
                        .foregroundStyle(Color.appWarning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.top, 10)
                }

                VStack(spacing: 12) {
                    ForEach(store.drafts) { draft in
                        card(draft)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 16)),
                                                    removal: .opacity.combined(with: .offset(x: -28))))
                    }
                }
                .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 24)

                // Notifications already recorded: information only, kept for 7 days (K5, K10).
                if !store.notices.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(store.notices) { notice in
                            noticeRow(notice)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    .animation(.settle(0.3), value: store.notices.map(\.id))
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if store.drafts.count > 1 && focusedId == nil { bulkBar }
        }
    }

    private var bulkBar: some View {
        VStack(spacing: 8) {
            PrimaryButton(title: ready.isEmpty ? L("Belum ada yang lengkap") : L("Simpan %lld yang lengkap", ready.count),
                          isEnabled: !ready.isEmpty) { showsSaveAll = true }
            let rest = store.drafts.count - ready.count
            Text(rest > 0 ? L("%lld draf yang belum lengkap tetap di daftar", rest) : L("Semua draf sudah lengkap"))
                .font(.app(13)).foregroundStyle(Color.appTextSecondary)
        }
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(Color.appBackground)
        .overlay(alignment: .top) { Rectangle().fill(Color.appSeparator).frame(height: 1) }
    }

    // MARK: Card

    private func card(_ d: Draft) -> some View {
        let lv = level(d)
        let isSaving = saving.contains(d.id)
        let failure = failures[d.id]
        let tint: Color = lv == .unread ? .stDangerText : lv == .partial ? .stWarn : .stGreen
        let pillBg: Color = lv == .unread ? .stDangerBg : lv == .partial ? .stWarnBg : .stSuccessBg
        let pillIcon = lv == .unread ? "questionmark" : lv == .partial ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
        let pillText = lv == .unread ? L("Tidak terbaca") : lv == .partial ? L("Kurang %@", missingNames(d).joined(separator: ", ")) : L("Siap disimpan")
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label(L("%@ · Smart Tracker", d.sourceLabel), systemImage: d.sourceIcon)
                        .font(.app(13)).foregroundStyle(Color.appTextSecondary).lineLimit(1).minimumScaleFactor(0.85)
                    Spacer(minLength: 4)
                    Text(Self.arrival(d.createdAt)).font(.app(12)).foregroundStyle(Color.appTextTertiary).lineLimit(1)
                }
                Label(pillText, systemImage: pillIcon)
                    .font(.app(12, weight: .semibold)).foregroundStyle(tint)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(pillBg, in: Capsule())
            }

            if d.isUnreadable {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Smart Tracker belum paham kalimat ini").font(.app(15, weight: .semibold))
                    Text("“\(d.title)”").font(.app(15)).italic().foregroundStyle(Color.appTextSecondary)
                    Text("Isi nominal dan detailnya di bawah.").font(.app(13)).foregroundStyle(Color.appTextSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                TextField("", text: nameBinding(d), prompt: Text("Nama transaksi").foregroundStyle(Color.appTextTertiary))
                    .font(.app(17, weight: .semibold))
                    .focused($focusedId, equals: d.id)
                    .submitLabel(.done)
                    .onSubmit { focusedId = nil }
                Button { sheet = DraftSheet(draftId: d.id, kind: .amount) } label: {
                    HStack(alignment: .top, spacing: 3) {
                        Text("Rp").font(.app(15)).foregroundStyle(Color.appTextTertiary).padding(.top, 8)
                        Text(d.amount.map { $0.formattedAsDigits() } ?? "0")
                            .font(.app(44, weight: .light)).tracking(-1.2).monospacedDigit()
                            .foregroundStyle(d.amount == nil ? Color.appTextTertiary : d.kind == .income ? Color.stGreen : Color.appText)
                            .lineLimit(1).minimumScaleFactor(0.5)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Nominal"))
                if d.amount == nil {
                    Text("Ketuk untuk isi nominal").font(.app(13)).foregroundStyle(Color.stWarn)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(fields(d), id: \.label) { field in fieldButton(d, field) }
            }

            if let note = d.duplicateNote {
                Label {
                    Text(L("Mirip transaksi lain.")).fontWeight(.semibold).foregroundStyle(Color.stWarn)
                        + Text(" " + note).foregroundStyle(Color.appTextSecondary)
                } icon: { Image(systemName: "doc.on.doc").foregroundStyle(Color.stWarn) }
                    .font(.app(13))
            }
            if let note = d.note {
                Label(note, systemImage: "eye").font(.app(13)).foregroundStyle(Color.stWarn)
            }
            if let days = Calendar.current.dateComponents([.day], from: Date(), to: d.expiresAt).day, days <= 3 {
                Label(L("Dibuang otomatis dalam %lld hari", max(days, 1)), systemImage: "hourglass")
                    .font(.app(13)).foregroundStyle(Color.appTextSecondary)
            }
            if let failure {
                Label {
                    Text(failure.isOffline ? L("Gagal menyimpan.") : L("Gagal menyimpan:")).fontWeight(.semibold).foregroundStyle(Color.stDangerText)
                        + Text(" " + (failure.isOffline ? L("Kamu sedang offline. Draf tetap aman di sini, coba lagi saat tersambung.") : failure.message))
                        .foregroundStyle(Color.appTextSecondary)
                } icon: { Image(systemName: failure.isOffline ? "wifi.slash" : "exclamationmark.triangle").foregroundStyle(Color.stDangerText) }
                    .font(.app(13))
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.stDangerBg, in: RoundedRectangle(cornerRadius: 12))
            }

            HStack(spacing: 10) {
                Button { ignore(d) } label: {
                    Text("Abaikan").font(.app(15, weight: .medium)).foregroundStyle(Color.appText)
                        .padding(.horizontal, 18).frame(height: 44)
                        .overlay(Capsule().strokeBorder(Color(light: 0xD2D2D7, dark: 0x48484A), lineWidth: 1))
                }
                .buttonStyle(PressScaleStyle())
                .disabled(isSaving)
                Button { save(d) } label: {
                    HStack(spacing: 8) {
                        if isSaving { ProgressView().tint(.white).scaleEffect(0.8) }
                        Text(isSaving ? L("Menyimpan…") : failure != nil ? L("Coba lagi") : lv == .complete ? L("Simpan") : L("Lengkapi dulu"))
                    }
                    .font(.app(15, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(lv == .complete ? Color.stGreen : Color.appTextTertiary, in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
                .disabled(isSaving)
            }
        }
        .padding(16)
        .background(lv == .unread ? Color.appBackground : Color.appFill, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            if lv == .unread {
                RoundedRectangle(cornerRadius: 20).strokeBorder(Color.stDash, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
        }
        .id(d.id)
    }

    /// "Notifikasi BCA sudah tercatat sebagai cicilan iPhone 15": information only, with Batalkan (K5).
    private func noticeRow(_ notice: SkippedNotice) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 17)).foregroundStyle(Color.stGreen).padding(.top, 1)
            VStack(alignment: .leading, spacing: 8) {
                Text(noticeText(notice))
                    .font(.app(14)).foregroundStyle(Color.appTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button { withAnimation(.settle(0.3)) { store.cancelNotice(notice) } } label: {
                    Text("Batalkan").font(.app(14, weight: .semibold)).foregroundStyle(Color.appPrimary)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16))
        .transition(.opacity.combined(with: .offset(y: 12)))
    }

    private func noticeText(_ notice: SkippedNotice) -> String {
        let name = notice.draft.sourceName ?? notice.draft.title
        return switch notice.match {
        case .installment(let title): L("Notifikasi %@ sudah tercatat sebagai cicilan %@", name, title)
        case .bill(let bill): L("Notifikasi %@ sudah tercatat sebagai tagihan berulang %@", name, bill)
        }
    }

    private struct Field {
        let label: String
        let value: String
        let icon: String
        let isMissing: Bool
        let kind: DraftFieldSheet.Kind
    }

    private func fields(_ d: Draft) -> [Field] {
        let wallet = store.accounts.first { $0.id == d.accountId }
        let target = store.accounts.first { $0.id == d.counterpartyAccountId }
        let category = store.categories.first { $0.id == d.categoryId }
        var result = [Field(label: L("Tipe"), value: d.kindTitle, icon: d.kindIcon, isMissing: false, kind: .type)]
        if d.kind == .expense || d.kind == .income {
            result.append(Field(label: L("Kategori"), value: category?.name ?? "", icon: category?.icon ?? "tag", isMissing: category == nil, kind: .category))
        }
        result.append(Field(label: d.kind == .transfer ? L("Dari dompet") : L("Dompet"), value: wallet?.name ?? "", icon: "wallet.bifold",
                            isMissing: wallet == nil, kind: .wallet))
        if d.kind == .transfer {
            result.append(Field(label: L("Ke dompet"), value: target?.name ?? "", icon: "arrow.right", isMissing: target == nil, kind: .target))
        }
        result.append(Field(label: L("Tanggal"), value: Self.dateLabel(d.date), icon: "calendar", isMissing: false, kind: .date))
        return result
    }

    private func fieldButton(_ d: Draft, _ f: Field) -> some View {
        Button { sheet = DraftSheet(draftId: d.id, kind: f.kind) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(f.label).font(.app(12)).foregroundStyle(Color.appTextSecondary)
                HStack(spacing: 6) {
                    Image(systemName: f.isMissing ? "plus.circle" : f.icon).font(.system(size: 14))
                    Text(f.isMissing ? L("Pilih") : f.value).font(.app(15, weight: .medium)).lineLimit(1)
                }
                .foregroundStyle(f.isMissing ? Color.stWarn : Color.appText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(f.isMissing ? Color.clear : Color.appBackground, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                if f.isMissing {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(Color.stWarn, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(f.label)
    }

    // MARK: Other screens

    private var emptyQueue: some View {
        VStack(spacing: 0) {
            Text("Konfirmasi transaksi").font(.app(34, weight: .bold)).tracking(0.2)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.top, 6)
            VStack(spacing: 10) {
                Image(systemName: "tray").font(.system(size: 44, weight: .light)).foregroundStyle(Color.appTextTertiary).stFloat()
                Text("Belum ada draf").font(.app(20, weight: .semibold))
                Text("Transaksi yang dicatat Smart Tracker dari ketikan, suara, Siri, bagikan teks, atau notifikasi akan muncul di sini untuk kamu cek.")
                    .font(.app(15)).foregroundStyle(Color.appTextSecondary).multilineTextAlignment(.center).frame(maxWidth: 300)
            }
            .frame(maxHeight: .infinity)
            .stEnter(0)
            PrimaryButton(title: L("Buka Smart Tracker")) {
                SmartButtonGate.shared.opensBarOnShow = true
                dismiss()
            }
            .padding(.horizontal, 24).padding(.bottom, 30)
        }
    }

    private var allChecked: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Konfirmasi transaksi").font(.app(34, weight: .bold)).tracking(0.2).padding(.top, 6)
            Spacer()
            Image(systemName: "checkmark").font(.system(size: 28, weight: .bold)).foregroundStyle(Color.appPrimary)
                .frame(width: 64, height: 64).background(Color.stSuccessBg, in: Circle()).stEnter(0)
            Text("Semua sudah dicek").font(.app(26, weight: .bold)).padding(.top, 28).stEnter(1)
            Text("Tidak ada draf Smart Tracker yang menunggu. Draf baru akan muncul di sini.")
                .font(.app(15)).foregroundStyle(Color.appTextSecondary).padding(.top, 8).stEnter(2)
            HStack(spacing: 0) {
                stat(saved, "disimpan ke transaksi", color: Color.appPrimary).frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(Color.appSeparator).frame(width: 1)
                stat(ignored, "diabaikan", color: Color.appText).padding(.leading, 20).frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
            .overlay(alignment: .top) { Rectangle().fill(Color.appSeparator).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Color.appSeparator).frame(height: 1) }
            .padding(.top, 28).stEnter(3)
            Spacer()
            PrimaryButton(title: L("Kembali ke Smart Tracker")) {
                SmartButtonGate.shared.opensBarOnShow = true
                dismiss()
            }
            .padding(.bottom, 30)
        }
        .padding(.horizontal, 24)
    }

    private func stat(_ value: Int, _ label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(.app(52, weight: .ultraLight)).tracking(-1.5).monospacedDigit().foregroundStyle(color)
            Text(L(label)).font(.app(13)).foregroundStyle(Color.appTextSecondary)
        }
        .padding(.vertical, 18)
    }

    @ViewBuilder private var toastView: some View {
        if let toast {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(light: 0x3DDC97, dark: 0x3DDC97))
                Text(toast.text).font(.app(15, weight: .medium)).lineLimit(1)
                Button { undo(toast) } label: {
                    Text("Urungkan").font(.app(14, weight: .semibold)).foregroundStyle(Color(light: 0x3DDC97, dark: 0x3DDC97))
                        .padding(.horizontal, 12).frame(height: 32)
                        .background(Color.white.opacity(0.14), in: Capsule())
                }
            }
            .foregroundStyle(.white)
            .padding(.leading, 14).padding(.trailing, 6).frame(height: 44)
            .background(Color(light: 0x111111, dark: 0x2C2C2E), in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
            .padding(.bottom, store.drafts.isEmpty ? 110 : store.drafts.count > 1 && focusedId == nil ? 124 : 40)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: Sheets

    @ViewBuilder private func sheetContent(_ item: DraftSheet) -> some View {
        if let d = store.drafts.first(where: { $0.id == item.draftId }) {
            DraftFieldSheet(draft: d, kind: item.kind, accounts: store.accounts, categories: store.categories,
                            edit: { change in edit(d.id, change) }, learn: { learn(d.id) }, close: { sheet = nil })
        }
    }

    private var saveAllSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Simpan %lld transaksi yang lengkap?", ready.count)).font(.app(20, weight: .semibold))
                let rest = store.drafts.count - ready.count
                Text(rest > 0 ? L("%lld draf yang belum lengkap tetap di daftar supaya bisa kamu cek nanti.", rest)
                     : L("Semua draf akan disimpan ke transaksimu."))
                    .font(.app(15)).foregroundStyle(Color.appTextSecondary)
            }
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(ready) { d in
                        HStack(spacing: 14) {
                            Image(systemName: store.categories.first { $0.id == d.categoryId }?.icon ?? d.kindIcon)
                                .font(.system(size: 18)).foregroundStyle(Color.appTextSecondary).frame(width: 24)
                            Text(d.title.isEmpty ? d.kindTitle : d.title).font(.app(16)).lineLimit(1)
                            Spacer()
                            Text((d.amount ?? 0).formattedAsCurrency()).font(.app(16)).monospacedDigit()
                        }
                    }
                }
            }
            PrimaryButton(title: L("Simpan %lld transaksi", ready.count)) { saveAllComplete() }
            Button { showsSaveAll = false } label: {
                Text("Batal").font(.app(17, weight: .medium)).foregroundStyle(Color.appText).frame(maxWidth: .infinity).frame(height: 44)
            }
        }
        .padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 16)
        .presentationDetents([.medium, .large])

        .background(Color.appBackground)
    }

    // MARK: Editing

    private func edit(_ id: UUID, _ change: (inout Draft) -> Void) {
        guard var draft = store.drafts.first(where: { $0.id == id }) else { return }
        change(&draft)
        failures[id] = nil
        store.update(draft)
    }

    private func nameBinding(_ d: Draft) -> Binding<String> {
        Binding(get: { d.isUnreadable ? "" : d.title },
                set: { value in edit(d.id) { $0.clearUnreadable(); $0.title = value } })
    }

    /// A correction teaches Ingatan, same as saving does.
    private func learn(_ id: UUID) {
        if let draft = store.drafts.first(where: { $0.id == id }) { store.learnCorrection(from: draft) }
    }

    private func openFirstMissing(_ d: Draft) {
        let kind: DraftFieldSheet.Kind
        switch d.missing.first {
        case .amount, .none: kind = .amount
        case .account: kind = .wallet
        case .counterparty: kind = .target
        case .category: kind = .category
        }
        sheet = DraftSheet(draftId: d.id, kind: kind)
    }

    // MARK: Actions

    private func save(_ d: Draft) {
        guard d.isComplete else { openFirstMissing(d); return }
        guard !saving.contains(d.id) else { return }
        if store.needsPeriodChoice(d) { periodChoice = d; return }
        focusedId = nil
        saving.insert(d.id)
        failures[d.id] = nil
        Task {
            do {
                let transactionId = try await store.save(d, userId: userId)
                saving.remove(d.id)
                saved += 1
                show(Toast(text: Self.savedText(d.kind), drafts: [d], transactionIds: transactionId.map { [$0] } ?? [], kind: .saved))
            } catch {
                saving.remove(d.id)
                failures[d.id] = Failure(error)
            }
        }
    }

    private func saveAllComplete() {
        let items = ready
        showsSaveAll = false
        Task {
            var done: [Draft] = []
            var ids: [String] = []
            for d in items {
                saving.insert(d.id)
                do {
                    if let id = try await store.save(d, userId: userId) { ids.append(id) }
                    done.append(d)
                    saved += 1
                } catch {
                    failures[d.id] = Failure(error)
                }
                saving.remove(d.id)
            }
            if !done.isEmpty {
                show(Toast(text: done.count > 1 ? L("%lld transaksi tersimpan", done.count) : Self.savedText(done[0].kind),
                           drafts: done, transactionIds: ids, kind: .saved))
            }
        }
    }

    private func ignore(_ d: Draft) {
        focusedId = nil
        store.discard(d.id)
        ignored += 1
        show(Toast(text: L("Draf diabaikan"), drafts: [d], transactionIds: [], kind: .ignored))
    }

    private func deleteAll() {
        showsDeleteAll = false
        let all = store.drafts
        all.forEach { store.discard($0.id) }
        ignored += all.count
        show(Toast(text: L("%lld draf dihapus", all.count), drafts: all, transactionIds: [], kind: .ignored))
    }

    /// Urungkan: a saved transaction is removed again (balances go back) and its draft returns; an ignored draft just returns.
    private func undo(_ t: Toast) {
        toast = nil
        Task {
            do {
                for id in t.transactionIds { try await SupabaseRepository.shared.softDeleteTransaction(id: id) }
                if !t.transactionIds.isEmpty { NotificationCenter.default.post(name: .dataDidChange, object: nil) }
                t.drafts.forEach { store.restore($0) }
                if t.kind == .saved { saved -= t.drafts.count } else { ignored -= t.drafts.count }
            } catch {
                errorMessage = FreeLimits.friendly(error).localizedDescription
            }
        }
    }

    private func show(_ t: Toast) {
        withAnimation(.settle(0.4)) { toast = t }
        Task {
            try? await Task.sleep(for: .seconds(5))
            if toast?.id == t.id { withAnimation(.settle(0.3)) { toast = nil } }
        }
    }

    // MARK: Words

    private static func savedText(_ kind: Draft.Kind) -> String {
        switch kind {
        case .expense: return L("Pengeluaran tersimpan")
        case .income: return L("Pemasukan tersimpan")
        case .transfer, .cardPayment: return L("Transfer tersimpan")
        }
    }

    /// "Masuk 09.41", "Masuk kemarin 09.41" or "Masuk 10 Okt 09.41": when the draft arrived.
    private static func arrival(_ date: Date) -> String {
        let time = DateFormatter.arrivalTime.string(from: date)
        if Calendar.current.isDateInToday(date) { return L("Masuk %@", time) }
        if Calendar.current.isDateInYesterday(date) { return L("Masuk kemarin %@", time) }
        return L("Masuk %@ %@", DateFormatter.shortDay.string(from: date), time)
    }

    private static func dateLabel(_ date: Date) -> String {
        let cal = Calendar.current
        let day = DateFormatter.shortDay.string(from: date)
        if cal.isDateInToday(date) { return L("Hari ini") + ", " + day }
        if cal.isDateInYesterday(date) { return L("Kemarin") + ", " + day }
        return day
    }
}

extension DateFormatter {
    /// Computed, not cached: the language can change while the app runs.
    static var shortDay: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        f.locale = AppLanguage.locale
        return f
    }

    static var arrivalTime: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX") // always 24-hour, whatever the phone's clock setting
        f.dateFormat = "HH.mm"
        return f
    }
}
