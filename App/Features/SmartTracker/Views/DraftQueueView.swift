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

/// "Perlu dicek" (design 1d): drafts as a deck of cards, one on top at a time. Simpan, Ubah or Abaikan; or deal with all at once.
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
    /// The card on screen; swiping the cards sideways moves between them.
    @State private var selectedId: UUID?
    @State private var isSaving = false
    @State private var isLeaving = false
    @State private var drag: CGFloat = 0
    @State private var showsDeleteAll = false
    @State private var errorMessage: String?

    private var pending: [Draft] { session.compactMap { id in outcomes[id] == nil ? store.drafts.first { $0.id == id } : nil } }
    private var current: Draft? { pending.first { $0.id == selectedId } ?? pending.first }
    private var savedCount: Int { outcomes.values.filter { $0 == .saved }.count }
    private var ignoredCount: Int { outcomes.values.filter { $0 == .ignored }.count }
    private var ready: [Draft] { pending.filter(\.isComplete) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 20, weight: .medium)).foregroundStyle(Color.stGreen)
                        .frame(width: 32, height: 32)
                }
                .padding(.leading, -8)
                .accessibilityLabel(L("Kembali"))
                Text(L("Perlu dicek")).font(.app(24, weight: .bold)).tracking(-0.4)
                if let current, let index = session.firstIndex(of: current.id) {
                    Text(L("%lld dari %lld", index + 1, session.count)).font(.app(15)).foregroundStyle(Color.appTextSecondary).monospacedDigit()
                }
                Spacer()
            }
            .padding(.horizontal, 24).padding(.top, 10)

            if current != nil {
                Label(L("Dicatat otomatis oleh Smart Tracker. Periksa dulu sebelum disimpan."), systemImage: "sparkles")
                    .font(.app(13)).foregroundStyle(Color.appTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.top, 10)
            }

            if store.expiringSoon > 0 && current != nil {
                Label(L("%lld draf akan dihapus dalam 3 hari jika tidak diproses.", store.expiringSoon), systemImage: "clock")
                    .font(.app(12)).foregroundStyle(Color.appWarning)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.top, 10)
            }

            if let current {
                cardStack(current)
                    .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 4)
                    .frame(height: 440 + 28)
                actions(current).padding(.top, 28)
                Spacer(minLength: 12)
                bulkBar.padding(.horizontal, 24).padding(.bottom, 24)
            } else if session.isEmpty {
                emptyQueue
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark").font(.system(size: 24, weight: .bold)).foregroundStyle(Color.stGreen)
                        .frame(width: 56, height: 56).background(Color.stSuccessBg, in: Circle())
                        .stEnter(0)
                    Text(L("Semua sudah dicek")).font(.app(17, weight: .semibold)).padding(.top, 6).stEnter(1)
                    Text(L("%lld disimpan · %lld diabaikan", savedCount, ignoredCount))
                        .font(.app(15)).foregroundStyle(Color.appTextSecondary).stEnter(2)
                }
                .padding(.horizontal, 40).padding(.top, 110)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $editing) { draft in DraftEditView(draft: draft, store: store).detailPage() }
        .confirmDialog(isPresented: $showsDeleteAll, icon: "trash", destructive: true,
                       title: L("Hapus %lld draf tersisa?", pending.count),
                       message: L("Draf hilang permanen dan tidak ada yang tercatat sebagai transaksi."),
                       confirmTitle: L("Hapus semua")) { ignoreAll() }
        .confirmDialog(isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
                       icon: "exclamationmark.triangle", title: L("Gagal menyimpan"),
                       message: errorMessage ?? "", confirmTitle: nil, cancelTitle: L("Tutup"))
        .onAppear {
            if session.isEmpty { session = store.drafts.map(\.id) }
            if let id = store.editRequest, let draft = store.drafts.first(where: { $0.id == id }) {
                store.editRequest = nil
                selectedId = id
                editing = draft
            }
        }
        .task { await store.refreshReferenceData(userId: userId) }
    }

    /// Perlu dicek with nothing in it (design 3d): what lands here, and a way to start.
    private var emptyQueue: some View {
        VStack(spacing: 0) {
            STEmptyHero(icon: "tray", title: "Belum ada draf",
                        message: "Transaksi yang ditangkap Smart Tracker menunggu di sini sampai kamu cek dan simpan.")
                .padding(.top, 48)
            Text(L("Draf datang dari")).font(.app(13, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.top, 36).padding(.bottom, 8)
                .stEnter(3)
            VStack(spacing: 0) {
                ForEach(Array(Self.sources.enumerated()), id: \.offset) { index, source in
                    HStack(spacing: 12) {
                        Image(systemName: source.icon).font(.system(size: 16)).foregroundStyle(Color.stGreen)
                            .frame(width: 32, height: 32).background(Color.stRaised, in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(L(source.title)).font(.app(16))
                            Text(L(source.detail)).font(.app(12)).foregroundStyle(Color.appTextTertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 62)
                    .stEnter(4 + index)
                }
            }
            .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)
            Spacer(minLength: 12)
            STInkButton(title: "Catat sekarang", icon: "sparkles") {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { NotificationCenter.default.post(name: .openSmartTrackerBar, object: nil) }
            }
            .padding(.horizontal, 24).padding(.bottom, 30).stEnter(7)
        }
    }

    private static let sources: [(icon: String, title: String, detail: String)] = [
        ("sparkles", "Catat cepat", "Ketik atau ucapkan dari Beranda"),
        ("bell.badge", "Notifikasi bank", "Dari aplikasi bank yang terhubung"),
        ("square.and.arrow.up", "Bagikan teks", "Dari menu Bagikan di aplikasi lain")]

    // MARK: Card

    /// The pending drafts as a deck: the first on top, the next two peeking out below. Drag the top card
    /// sideways to send it to the back of the deck.
    private func cardStack(_ top: Draft) -> some View {
        let deck = pending
        let start = deck.firstIndex { $0.id == top.id } ?? 0
        let ordered = (0..<min(deck.count, 3)).map { deck[(start + $0) % deck.count] }
        return ZStack(alignment: .top) {
            ForEach(Array(ordered.enumerated()).reversed(), id: \.element.id) { depth, draft in
                card(draft)
                    .scaleEffect(1 - CGFloat(depth) * 0.05, anchor: .top)
                    .offset(y: CGFloat(depth) * 16)
                    .opacity(depth == 2 ? 0.55 : 1)
                    .offset(x: depth == 0 ? drag : 0)
                    .rotationEffect(.degrees(depth == 0 ? Double(drag) / 28 : 0), anchor: .bottom)
                    .opacity(isLeaving && depth == 0 ? 0 : 1)
                    .allowsHitTesting(depth == 0)
                    .gesture(depth == 0 && deck.count > 1 ? swipe(deck: deck, from: start) : nil)
                    .zIndex(Double(3 - depth))
            }
        }
        .animation(.settle(0.4), value: top.id)
        .animation(.settle(0.4), value: deck.count)
    }

    private func swipe(deck: [Draft], from index: Int) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { drag = $0.translation.width }
            .onEnded { value in
                let thrown = abs(value.predictedEndTranslation.width) > 260 || abs(value.translation.width) > 90
                guard thrown else { withAnimation(.settle(0.35)) { drag = 0 }; return }
                let direction: CGFloat = value.translation.width < 0 ? -1 : 1
                withAnimation(.easeIn(duration: 0.18)) { drag = direction * 420 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    selectedId = deck[(index + 1) % deck.count].id
                    drag = 0
                }
            }
    }

    private func card(_ draft: Draft) -> some View {
        let wallet = store.accounts.first { $0.id == draft.accountId }
        let counter = store.accounts.first { $0.id == draft.counterpartyAccountId }
        let category = store.categories.first { $0.id == draft.categoryId }
        return VStack(alignment: .leading, spacing: 0) {
            Label(L("Smart Tracker · %@", draft.sourceLabel), systemImage: draft.sourceIcon)
                .font(.app(13)).foregroundStyle(Color.appTextSecondary)
            Image(systemName: category?.icon ?? draft.kindIcon).font(.system(size: 24)).foregroundStyle(Color.appText)
                .frame(width: 52, height: 52).background(Color.stRaised, in: Circle()).padding(.top, 18)
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
    }

    private func cardRow(_ title: String, _ value: String, warn: Bool, last: Bool = false) -> some View {
        HStack {
            Text(L(title)).foregroundStyle(Color.appTextSecondary)
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
            circle(L("Abaikan"), "xmark", size: 60, fill: Color.stChip, fg: Color.appText) { resolve(draft, .ignored) }
            circle(L("Ubah"), "pencil", size: 48, fill: Color.stChip, fg: Color.appText) { editing = draft }.padding(.top, 6)
            ZStack {
                circle(L("Simpan"), "checkmark", size: 60, fill: draft.isComplete ? Color.stGreen : Color.appTextTertiary, fg: .white) {
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
                Text(L(label)).font(.app(13)).foregroundStyle(Color.appTextSecondary)
            }
        }
        .buttonStyle(PressScaleStyle())
        .disabled(isSaving)
    }

    private var bulkBar: some View {
        HStack {
            Button { showsDeleteAll = true } label: {
                Label(L("Hapus semua"), systemImage: "trash")
                    .font(.app(15, weight: .semibold)).foregroundStyle(Color.stDangerText).frame(height: 44)
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

    private func resolve(_ draft: Draft, _ outcome: Outcome, animated: Bool = true) {
        if outcome == .ignored {
            finish(draft, .ignored, animated: animated) { store.discard(draft.id) }
            return
        }
        isSaving = true
        Task {
            do {
                try await store.save(draft, userId: userId)
                isSaving = false
                finish(draft, .saved, animated: animated) {}
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Slides the card away, then moves on to the next one.
    private func finish(_ draft: Draft, _ outcome: Outcome, animated: Bool = true, _ work: @escaping () -> Void) {
        // after this one goes, show the next card (or the previous when it was the last)
        let list = pending
        let index = list.firstIndex { $0.id == draft.id } ?? 0
        let neighbour = list.indices.contains(index + 1) ? list[index + 1].id : (index > 0 ? list[index - 1].id : nil)
        if animated { withAnimation(.easeOut(duration: 0.2)) { isLeaving = true } }
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            work()
            withAnimation(.settle(0.4)) {
                outcomes[draft.id] = outcome
                selectedId = neighbour
            }
            if animated { withAnimation(.easeOut(duration: 0.2)) { isLeaving = false } }
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
