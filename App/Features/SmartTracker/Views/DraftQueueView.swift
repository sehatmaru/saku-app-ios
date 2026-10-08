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
        }
    }

    var sourceIcon: String {
        switch source {
        case .typed: return "keyboard"
        case .voice: return "mic"
        case .siri: return "waveform"
        case .share: return "square.and.arrow.up"
        case .notification: return "bell"
        }
    }

    var kindColor: Color {
        switch kind {
        case .expense: return Color(hex: "D93636")
        case .income: return Color(hex: "16875A")
        case .transfer: return Color(hex: "143A73")
        case .cardPayment: return Color(hex: "6B3FA0")
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

/// "Perlu dicek" (design 1d): one draft at a time. Simpan, Ubah or Abaikan; or deal with all at once.
struct DraftQueueView: View {
    let userId: String
    @ObservedObject private var store = DraftStore.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage("isBalanceVisible") private var isBalanceVisible = true

    private enum Outcome { case saved, ignored }
    /// The drafts present when the sheet opened, in order, for the progress bar and "1 dari 4".
    @State private var session: [UUID] = []
    @State private var outcomes: [UUID: Outcome] = [:]
    @State private var editing: Draft?
    @State private var isSaving = false
    @State private var isLeaving = false
    @State private var showsDeleteAll = false
    @State private var errorMessage: String?

    private var pending: [Draft] { session.compactMap { id in outcomes[id] == nil ? store.drafts.first { $0.id == id } : nil } }
    private var current: Draft? { pending.first }
    private var savedCount: Int { outcomes.values.filter { $0 == .saved }.count }
    private var ignoredCount: Int { outcomes.values.filter { $0 == .ignored }.count }
    private var ready: [Draft] { pending.filter(\.isComplete) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("Perlu dicek")).font(.app(24, weight: .bold)).tracking(-0.4)
                if let current, let index = session.firstIndex(of: current.id) {
                    Text(L("%lld dari %lld", index + 1, session.count)).font(.app(15)).foregroundStyle(Color.appTextSecondary).monospacedDigit()
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.appText)
                        .frame(width: 36, height: 36).background(Color.appFill, in: Circle())
                }
                .accessibilityLabel(L("Tutup"))
            }
            .padding(.horizontal, 24).padding(.top, 22)

            HStack(spacing: 4) {
                ForEach(session, id: \.self) { id in
                    Capsule().fill(segment(id)).frame(height: 4)
                }
            }
            .padding(.horizontal, 24).padding(.top, 14)
            .animation(.easeInOut(duration: 0.3), value: outcomes.count)

            if store.expiringSoon > 0 && current != nil {
                Label(L("%lld draf akan dihapus dalam 3 hari jika tidak diproses.", store.expiringSoon), systemImage: "clock")
                    .font(.app(12)).foregroundStyle(Color.appWarning)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.top, 10)
            }

            if let current {
                card(current)
                    .padding(.horizontal, 24).padding(.top, 20)
                    .id(current.id)
                    .opacity(isLeaving ? 0 : 1)
                    .offset(y: isLeaving ? -16 : 0)
                    .scaleEffect(isLeaving ? 0.97 : 1)
                actions(current).padding(.top, 28)
                Spacer(minLength: 12)
                bulkBar.padding(.horizontal, 24).padding(.bottom, 24)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark").font(.system(size: 24, weight: .bold)).foregroundStyle(Color.appPrimary)
                        .frame(width: 56, height: 56).background(Color(light: 0xE6F3EC, dark: 0x1E3A2C), in: Circle())
                    Text(L("Semua sudah dicek")).font(.app(17, weight: .semibold)).padding(.top, 6)
                    if !session.isEmpty {
                        Text(L("%lld disimpan · %lld diabaikan", savedCount, ignoredCount))
                            .font(.app(15)).foregroundStyle(Color.appTextSecondary)
                    } else {
                        Text(L("Draf dari Catat cepat, Siri, Bagikan, dan notifikasi muncul di sini."))
                            .font(.app(15)).foregroundStyle(Color.appTextSecondary).multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 40).padding(.top, 110)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .presentationDetents([.large])
        .presentationBackground(Color.appBackground)
        .presentationCornerRadius(38)
        .presentationDragIndicator(.visible)
        .sheet(item: $editing) { draft in DraftEditView(draft: draft, store: store) }
        .confirmDialog(isPresented: $showsDeleteAll, icon: "trash", destructive: true,
                       title: L("Hapus %lld draf tersisa?", pending.count),
                       message: L("Draf hilang permanen dan tidak ada yang tercatat sebagai transaksi."),
                       confirmTitle: L("Hapus semua")) { ignoreAll() }
        .confirmDialog(isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
                       icon: "exclamationmark.triangle", title: L("Gagal menyimpan"),
                       message: errorMessage ?? "", confirmTitle: nil, cancelTitle: L("Tutup"))
        .onAppear { if session.isEmpty { session = store.drafts.map(\.id) } }
        .task { await store.refreshReferenceData(userId: userId) }
    }

    private func segment(_ id: UUID) -> Color {
        switch outcomes[id] {
        case .saved: return Color.appPrimary
        case .ignored: return Color.appTextTertiary.opacity(0.5)
        case nil: return id == current?.id ? Color.appText : Color.appFill
        }
    }

    // MARK: Card

    private func card(_ draft: Draft) -> some View {
        let wallet = store.accounts.first { $0.id == draft.accountId }
        let counter = store.accounts.first { $0.id == draft.counterpartyAccountId }
        let category = store.categories.first { $0.id == draft.categoryId }
        return VStack(alignment: .leading, spacing: 0) {
            Label(draft.sourceLabel, systemImage: draft.sourceIcon)
                .font(.app(13)).foregroundStyle(Color.appTextSecondary)
            Image(systemName: category?.icon ?? draft.kindIcon).font(.system(size: 24)).foregroundStyle(Color.appText)
                .frame(width: 52, height: 52).background(Color.appBackground, in: Circle()).padding(.top, 18)
            Text(draft.title.isEmpty ? draft.kindTitle : draft.title).font(.app(20, weight: .semibold)).lineLimit(2).padding(.top, 12)
            Text(draft.amount.map { (draft.kind == .expense ? "−" : "") + (isBalanceVisible ? $0.formattedAsCurrency() : "Rp" + hiddenAmount) } ?? "—")
                .font(.app(44, weight: .ultraLight)).tracking(-1.8).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.5).padding(.top, 4)
            if draft.isUnreadable {
                Text(L("Tidak terbaca. Isi nominalnya dulu.")).font(.app(13)).foregroundStyle(Color.appWarning).padding(.top, 4)
            }
            if let note = draft.duplicateNote {
                Label(note, systemImage: "doc.on.doc").font(.app(12)).foregroundStyle(Color.appWarning).padding(.top, 6)
            }
            Spacer(minLength: 12)
            VStack(spacing: 0) {
                switch draft.kind {
                case .transfer, .cardPayment:
                    cardRow(L("Dari"), wallet?.name ?? L("Belum dipilih"), warn: wallet == nil && draft.kind == .transfer)
                    cardRow(draft.kind == .cardPayment ? L("Kartu") : L("Ke"), counter?.name ?? L("Belum dipilih"), warn: counter == nil)
                default:
                    cardRow(L("Kategori"), category?.name ?? L("Belum dipilih"), warn: category == nil)
                    cardRow(L("Dompet"), wallet?.name ?? L("Belum dipilih"), warn: wallet == nil)
                }
                cardRow(L("Tanggal"), Self.dateLabel(draft.date), warn: false, last: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 392, alignment: .topLeading)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 26))
        .background(alignment: .bottom) {
            if pending.count > 1 {
                RoundedRectangle(cornerRadius: 26).fill(Color.appFill.opacity(0.6)).padding(.horizontal, 12).offset(y: 10)
            }
        }
    }

    private func cardRow(_ title: String, _ value: String, warn: Bool, last: Bool = false) -> some View {
        HStack {
            Text(title).foregroundStyle(Color.appTextSecondary)
            Spacer()
            Text(value).foregroundStyle(warn ? Color.appWarning : Color.appText).fontWeight(warn ? .semibold : .regular)
        }
        .font(.app(15)).frame(height: 42)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(Color.appSeparator).frame(height: 1) } }
    }

    private static func dateLabel(_ date: Date) -> String {
        let cal = Calendar.current
        let day = DateFormatter.shortDay.string(from: date)
        if cal.isDateInToday(date) { return L("Hari ini") + ", " + day }
        if cal.isDateInYesterday(date) { return L("Kemarin") + ", " + day }
        return day
    }

    // MARK: Actions

    private func actions(_ draft: Draft) -> some View {
        HStack(alignment: .top, spacing: 28) {
            circle(L("Abaikan"), "xmark", size: 60, fill: Color.appFill, fg: Color.appText) { resolve(draft, .ignored) }
            circle(L("Ubah"), "pencil", size: 48, fill: Color.appFill, fg: Color.appText) { editing = draft }.padding(.top, 6)
            ZStack {
                circle(L("Simpan"), "checkmark", size: 60, fill: draft.isComplete ? Color.appPrimary : Color.appTextTertiary, fg: .white) {
                    if draft.isComplete { resolve(draft, .saved) } else { editing = draft }
                }
                .opacity(isSaving ? 0.5 : 1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func circle(_ label: String, _ icon: String, size: CGFloat, fill: Color, fg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: size == 60 ? 22 : 19, weight: .bold)).foregroundStyle(fg)
                    .frame(width: size, height: size).background(fill, in: Circle())
                Text(label).font(.app(13)).foregroundStyle(Color.appTextSecondary)
            }
        }
        .buttonStyle(PressScaleStyle())
        .disabled(isSaving)
    }

    private var bulkBar: some View {
        HStack {
            Button { showsDeleteAll = true } label: {
                Label(L("Hapus semua"), systemImage: "trash")
                    .font(.app(15, weight: .semibold)).foregroundStyle(Color(light: 0xD1343A, dark: 0xFF6B6B)).frame(height: 44)
            }
            Spacer()
            Button(action: saveAll) {
                Label(L("Simpan semua (%lld)", ready.count), systemImage: "checkmark.circle")
                    .font(.app(15, weight: .semibold)).foregroundStyle(Color.appBackground)
                    .padding(.horizontal, 18).frame(height: 44)
                    .background(ready.isEmpty ? Color.appTextTertiary : Color.appText, in: Capsule())
            }
            .disabled(ready.isEmpty || isSaving)
        }
    }

    private func resolve(_ draft: Draft, _ outcome: Outcome) {
        if outcome == .ignored {
            finish(draft, .ignored) { store.discard(draft.id) }
            return
        }
        isSaving = true
        Task {
            do {
                try await store.save(draft, userId: userId)
                isSaving = false
                finish(draft, .saved) {}
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Slides the card away, then moves on to the next one.
    private func finish(_ draft: Draft, _ outcome: Outcome, _ work: @escaping () -> Void) {
        withAnimation(.easeOut(duration: 0.2)) { isLeaving = true }
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            work()
            outcomes[draft.id] = outcome
            withAnimation(.easeOut(duration: 0.2)) { isLeaving = false }
        }
    }

    private func saveAll() {
        isSaving = true
        Task {
            for draft in ready {
                do {
                    try await store.save(draft, userId: userId)
                    outcomes[draft.id] = .saved
                } catch {
                    errorMessage = error.localizedDescription
                    break
                }
            }
            isSaving = false
        }
    }

    private func ignoreAll() {
        for draft in pending {
            store.discard(draft.id)
            outcomes[draft.id] = .ignored
        }
        showsDeleteAll = false
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
