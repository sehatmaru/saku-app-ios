import SwiftUI

/// Who read the draft: "AI" or "Aturan" (the on-device rules).
struct ReaderBadge: View {
    let reader: Draft.Reader

    var body: some View {
        Group {
            if reader == .ai { Label("AI", systemImage: "sparkles").labelStyle(.titleAndIcon) } else { Text(L("Aturan")) }
        }
        .font(.app(13, weight: .bold))
        .foregroundStyle(reader == .ai ? Color.appPrimaryText : Color.appTextSecondary)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(reader == .ai ? Color.appPrimary.opacity(0.12) : Color.stChip, in: Capsule())
    }
}

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

    /// Slow fade of the "Membaca dengan AI" label and skeleton while a rescan runs (design 1e).
    @State private var pulse = false
    @State private var rescanning: Set<UUID> = []
    @State private var rescanFailed: Set<UUID> = []
    @State private var plusReason: PlusReason?
    @ObservedObject private var quotaStore = AIQuotaStore.shared
    @AppStorage(SmartTrackerConsent.key) private var aiOn = false

    /// A short head-up in the draft list when the allowance runs low (10 left, 3 left) or is used up.
    private var quotaNote: String? {
        guard aiOn, let quota = quotaStore.quota, !quota.isPlus, let left = quota.left else { return nil }
        if left == 0 { return L("Jatah AI habis. Dibaca dengan aturan di perangkat.") }
        if left <= 3 { return L("Sisa %lld jatah AI. Setelah itu dibaca dengan aturan.", left) }
        if left <= 10 { return L("Sisa %lld jatah AI bulan ini", left) }
        return nil
    }

    /// A draft the rules read can be read again by AI on request, as long as its original text is still here (only while AI is on).
    private func canRescan(_ d: Draft) -> Bool {
        d.rawText != nil && d.reader != .ai && aiOn && RemoteSmartParser.isAvailable
    }

    private var aiOut: Bool { quotaStore.quota?.isOut == true }

    private func rescanButton(_ d: Draft) -> some View {
        let busy = rescanning.contains(d.id), failed = rescanFailed.contains(d.id), out = aiOut
        return Button { if !swiping { rescan(d) } } label: {
            HStack(spacing: 8) {
                if busy { ProgressView().controlSize(.small) } else { Image(systemName: "sparkles").font(.system(size: 16)) }
                Text(busy ? L("Memindai ulang…") : failed ? L("Gagal. Ketuk untuk coba lagi") : out ? L("Jatah habis") : L("Baca dengan AI"))
            }
            .font(.app(16, weight: .semibold))
            .foregroundStyle(failed ? Color.appError : out ? Color.appTextSecondary : Color.appPrimaryText)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(failed || out ? Color.clear : Color.appPrimary.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(failed ? Color.appError : out ? Color.appDivider : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(busy || out)
    }

    private func rescan(_ d: Draft) {
        rescanFailed.remove(d.id)
        rescanning.insert(d.id)
        Task {
            let result = await store.rescan(d.id)
            rescanning.remove(d.id)
            switch result {
            case .done: break
            case .outOfQuota: plusReason = .aiHelp
            case .failed: rescanFailed.insert(d.id)
            }
        }
    }

    /// Newest first, left to right. "Simpan semua" still records them oldest first.
    private var queue: [Draft] { store.drafts.sorted { $0.createdAt > $1.createdAt } }

    /// The stack: notices already recorded first, then the drafts.
    private enum StackItem: Identifiable {
        case notice(SkippedNotice), draft(Draft)
        var id: UUID { switch self { case .notice(let n): n.id; case .draft(let d): d.id } }
    }

    private var items: [StackItem] { store.notices.map(StackItem.notice) + queue.map(StackItem.draft) }

    private var ready: [Draft] { queue.filter { $0.isComplete && !store.needsPeriodChoice($0) } }

    /// Swiping only browses: left brings the next draft to the front, right the one before it, round and round.
    @State private var browse = 0
    @State private var drag: CGFloat = 0

    private var stackPosition: Int {
        let n = items.count
        return n == 0 ? 0 : min(max(browse, 0), n - 1)
    }

    /// True from the first sideways move until a moment after the finger lifts, so a swipe that starts on a chip
    /// or button never counts as a tap on it.
    @State private var swiping = false
    @State private var expandedWords: Set<UUID> = []
    @State private var expandedSource: Set<UUID> = []
    @State private var viewingImage: DraftImageItem?
    @State private var sourceSheet: DraftImageItem?
    @State private var dragging = false
    @State private var exiting: UUID?
    @State private var exitDir: CGFloat = 0
    @State private var busy = false
    /// Why the round AI button does nothing, shown beside it for a few seconds.
    @State private var aiReason: (id: UUID, text: String)?

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .global)
            .onChanged { value in
                guard items.count > 1, abs(value.translation.width) > abs(value.translation.height) else { return }
                // the first draft cannot be pulled right, the last one cannot be pulled left
                swiping = true
                if (stackPosition == 0 && value.translation.width > 0) || (stackPosition == items.count - 1 && value.translation.width < 0) {
                    drag = 0
                    return
                }
                dragging = true
                drag = value.translation.width
            }
            .onEnded { value in
                dragging = false
                let flick = value.predictedEndTranslation.width
                Task { try? await Task.sleep(for: .milliseconds(350)); swiping = false }
                guard items.count > 1, abs(drag) > 0, abs(drag) > 90 || abs(flick) > 220 else { drag = 0; return }
                commit(step: (drag < 0 || flick < -220) ? 1 : -1)
            }
    }

    /// A draft arriving at the front must not push the card being looked at out of view.
    private func keepFront(_ old: [UUID], _ new: [UUID]) {
        guard !old.isEmpty else { return }
        let front = old[min(max(browse, 0), old.count - 1)]
        guard let at = new.firstIndex(of: front), at != browse else { return }
        var t = SwiftUI.Transaction(); t.disablesAnimations = true
        withTransaction(t) { browse = at }
    }

    /// Brings another draft to the front: the old front card leaves to the side while the next one grows from behind.
    private func commit(step: Int) {
        let target = min(max(stackPosition + step, 0), items.count - 1)
        guard !busy, items.count > 1, target != stackPosition else { drag = 0; return }
        busy = true
        Task { try? await Task.sleep(for: .milliseconds(300)); busy = false }
        focusedId = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // only a card leaving forward flies off; going back, the old front simply sinks behind the stack
        let leaving = target > stackPosition ? items[stackPosition].id : nil
        exiting = leaving
        exitDir = -1
        Task { try? await Task.sleep(for: .milliseconds(400)); if exiting == leaving { exiting = nil } }
        browse = target
        drag = 0
    }

    /// Where draft `j` sits relative to the front one: 0 front, 1 and 2 behind it, -1 the one before it.
    private func relative(_ j: Int, _ pos: Int, _ n: Int) -> Int { j - pos }

    private static let ease = Animation.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.28)

    /// Every draft is a real card. The front one follows the finger; the ones behind sit higher, smaller and blurred, and
    /// sharpen as the front one is pulled away.
    private var cardStack: some View {
        let n = items.count, pos = stackPosition
        let t = min(abs(drag) / 140, 1)
        return ZStack(alignment: .top) {
            ForEach(Array(items.enumerated()), id: \.element.id) { j, item in
                let d = item
                let rel = relative(j, pos, n)
                if (rel >= -1 && rel <= 2) || d.id == exiting {
                    let front = rel == 0
                    // swiping right brings the previous draft in from the left over the front one
                    let prev = rel == -1 && drag > 0
                    let out = d.id == exiting && !front && !prev
                    let under = drag < 0 && rel > 0
                    let behind = !out && !prev && rel > 0
                    let eff = max(0, Double(abs(rel)) - (under ? t : 0))
                    let sink = front && drag > 0 ? t : 0
                    cardView(item)
                        .frame(height: cardHeight)
                        .allowsHitTesting(front)
                        .blur(radius: behind ? 2.5 * eff : 2.5 * sink)
                        .scaleEffect(behind ? 1 - 0.06 * eff : 1 - 0.06 * sink, anchor: .top)
                        .opacity(out ? 0 : prev ? 1 : behind ? (eff > 2 ? 0 : 1 - 0.12 * eff) : front ? 1 - 0.12 * sink : 0)
                        .offset(x: prev ? drag - Self.cardWidth : front ? (drag > 0 ? 0 : drag) : out ? exitDir * 520 : behind ? drag * 0.08 * Double(rel) : -520,
                                y: behind ? (eff > 2 ? -32 : -18 * eff) : -18 * sink)
                        .zIndex(prev ? 7 : out ? 6 : front ? 5 : behind ? 4 - eff : 1)
                        .animation(dragging ? nil : Self.ease, value: drag)
                        .animation(Self.ease, value: pos)
                        .animation(Self.ease, value: exiting)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: cardHeight, alignment: .top)
        // the strip where the cards behind peek out is part of the swipe area too
        .padding(.top, n > 2 ? 46 : n > 1 ? 28 : 12)
        .contentShape(Rectangle())
        .simultaneousGesture(swipe)
    }

    /// One height for every card, state and kind: the tallest realistic content, capped so it fits small screens.
    /// The coloured head is about a third of the card; 24 pt side padding matches the rows below.
    private static let heroHeight: CGFloat = 176
    private static var cardWidth: CGFloat { UIScreen.main.bounds.width }
    private static var baseCardHeight: CGFloat { min(580, max(500, UIScreen.main.bounds.height - 300)) }

    private var cardHeight: CGFloat { Self.baseCardHeight }

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
            if store.drafts.isEmpty { toastView.padding(.bottom, 110) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .animation(.settle(0.4), value: store.drafts.map(\.id))
        .navigationTitle(L("Draf Transaksi"))
        .navigationBarTitleDisplayMode(.inline)
        .hidesSmartButton()
        .background(NoSwipeBack())
        .onChange(of: sheet?.id) { focusedId = nil }
        .plusOffer($plusReason)
        .sheet(item: $sheet) { item in sheetContent(item) }
        .fullScreenCover(item: $viewingImage) { DraftImageViewer(id: $0.id) }
        .sheet(item: $sourceSheet) { item in
            if let d = store.drafts.first(where: { $0.id == item.id }) { sourceSheetContent(d) }
        }
        .sheet(isPresented: $showsSaveAll) { saveAllSheet }
.sheet(item: $periodChoice) { d in
    EarlySalarySheet(date: d.date) { choice in
        var chosen = d
        chosen.startsPeriod = choice
        save(chosen)
    }
}
        .confirmDialog(isPresented: $showsDeleteAll, icon: "eye.slash", inkButton: true,
                       title: L("Abaikan semua draf?"),
                       message: L("Semua %lld draf dari Smart Tracker akan dibuang. Transaksi yang sudah tersimpan tidak terpengaruh.", store.drafts.count),
                       confirmTitle: L("Abaikan semua")) { deleteAll() }
        .confirmDialog(isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
                       icon: "exclamationmark.triangle", title: L("Gagal"),
                       message: errorMessage ?? "", confirmTitle: nil, cancelTitle: L("Tutup"))
        .onAppear {
            if let id = store.editRequest, store.drafts.contains(where: { $0.id == id }) {
                store.editRequest = nil
                sheet = DraftSheet(draftId: id, kind: .amount)
            }
        }
        .task { await store.refreshReferenceData(userId: userId); await quotaStore.refresh() }
        .onChange(of: rescanning.isEmpty) { _, idle in
            if idle { withAnimation(.default) { pulse = false } }
            else { withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true } }
        }
    }

    // MARK: List

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            // TC 45: a head-up in the last days before drafts expire (restored after the layout-A redesign dropped it).
            if store.expiringSoon > 0 {
                Label(L("%lld draf akan dihapus dalam 3 hari jika tidak diproses.", store.expiringSoon), systemImage: "clock")
                    .font(.app(13))
                    .foregroundStyle(Color.appWarning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
            }

            if let note = quotaNote {
                let low = quotaStore.quota?.isOut == true || (quotaStore.quota?.left ?? 99) <= 3
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").font(.system(size: 18)).foregroundStyle(low ? Color.appWarning : Color.appPrimary)
                    Text(note).font(.app(14)).lineSpacing(2).foregroundStyle(Color.appText)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 44)
                .background(low ? Color.appFill : Color.appPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 24).padding(.top, 12)
            }

            if !queue.isEmpty {
                cardStack
                    .padding(.horizontal, 20)
                    .onChange(of: queue.map(\.id)) { old, new in keepFront(old, new) }
                // the marks sit halfway between the card and the bar below
                Spacer(minLength: 0)
                pageDots.overlay { toastView }
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .pinnedFooter(separator: true) {
            if store.drafts.count > 1 && focusedId == nil { bulkBar }
        }
    }

    /// One mark per draft in the colour of its kind. The track slides so the front draft is centred; the front mark is the
    /// tallest, the ones further away shrink and fade out.
    @State private var dotStart: Int?

    /// One gesture on the strip: a short touch jumps to the mark under the finger, a drag scrubs through the drafts, one
    /// per mark, and the card stays on whichever draft the finger was lifted over.
    private func dotGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { v in
                guard !items.isEmpty, abs(v.translation.width) > 8 else { return }
                swiping = true
                let start = dotStart ?? stackPosition
                dotStart = start
                let target = min(max(start - Int((v.translation.width / 24).rounded()), 0), items.count - 1)
                guard target != stackPosition else { return }
                focusedId = nil
                UISelectionFeedbackGenerator().selectionChanged()
                browse = target
            }
            .onEnded { v in
                let scrubbed = dotStart != nil
                dotStart = nil
                if scrubbed {
                    Task { try? await Task.sleep(for: .milliseconds(350)); swiping = false }
                } else if abs(v.translation.width) <= 8, abs(v.translation.height) <= 12 {
                    // a tap: the strip's first mark sits at width/2 - 24 * position - 12
                    let k = Int(((v.startLocation.x - width / 2 + 24 * CGFloat(stackPosition) + 12) / 24).rounded(.down))
                    if k >= 0 && k < items.count && abs(k - stackPosition) <= 3 { commit(step: k - stackPosition) }
                }
            }
    }

    private var pageDots: some View {
        let sizes: [(CGFloat, CGFloat)] = [(22, 30), (16, 22), (12, 18), (9, 14)]
        let n = items.count, pos = stackPosition
        let curve = Animation.timingCurve(0.22, 0.9, 0.25, 1, duration: 0.45)
        return GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { k, d in
                    let dist = abs(k - pos)
                    let size = dist < sizes.count ? sizes[dist] : (8, 12)
                    RoundedRectangle(cornerRadius: dist == 0 ? 6 : 4)
                        .fill(itemColor(d))
                        .frame(width: size.0, height: size.1)
                        .opacity(dist > 3 ? 0 : dist == 0 ? 1 : 0.55)
                        .overlay(alignment: .topTrailing) {
                            // a draft that still lacks something wears the same amber as its dashed card
                            if case .draft(let draft) = d, !draft.isComplete, dist <= 3 {
                                Image(systemName: "exclamationmark.circle.fill").font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color.stWarn)
                                    .background(Color.appBackground, in: Circle())
                                    .offset(x: 5, y: -5)
                            }
                        }
                        .frame(width: 24, height: 44)
                        .accessibilityElement()
                        .accessibilityLabel(itemTitle(d))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { commit(step: k - pos) }
                }
            }
            .frame(width: CGFloat(n) * 24, alignment: .leading)
            .offset(x: geo.size.width / 2 - 24 * CGFloat(pos) - 12)
            .animation(curve, value: pos)
            .frame(width: geo.size.width, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(dotGesture(width: geo.size.width))
        }
        .frame(height: 44)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("%lld dari %lld", pos + 1, n))
    }

    private var bulkBar: some View {
        SmartSheetFooter(primary: L("Simpan (%lld)", ready.count), isEnabled: !ready.isEmpty,
                         secondary: L("Abaikan (%lld)", store.drafts.count),
                         onPrimary: { showsSaveAll = true }) { showsDeleteAll = true }
    }

    // MARK: Card

    private func headerColor(_ d: Draft) -> Color {
        switch d.kind {
        case .expense: Color(light: 0xD93636, dark: 0xB3302B)
        case .income: Color(light: 0x1A8A5B, dark: 0x1B7A52)
        case .transfer: Color(light: 0x143A73, dark: 0x1D4E96)
        case .cardPayment: Color.stCardPayment
        }
    }

    private func card(_ d: Draft) -> some View {
        let lv = level(d)
        let isSaving = saving.contains(d.id)
        let failure = failures[d.id]
        let rows = fields(d)
        return VStack(spacing: 0) {
            cardHeader(d, reading: rescanning.contains(d.id)).zIndex(1)
            ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if d.isUnreadable {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Smart Tracker belum paham kalimat ini").font(.app(15, weight: .semibold))
                        Text("“\(d.title)”").font(.app(15)).italic().foregroundStyle(Color.appTextSecondary)
                        Text("Isi nominal dan detailnya di bawah.").font(.app(13)).foregroundStyle(Color.appTextSecondary)
                    }
                    .padding(.bottom, 8)
                }
                // the same rows as the manual form: label, mark and value, chevron; the name field closes the list
                ForEach(Array(rows.enumerated()), id: \.element.label) { _, field in
                    fieldRow(d, field).padding(.horizontal, -24).padding(.trailing, 4)
                }
                HStack(spacing: 12) {
                    Text(L("Judul")).font(.app(15)).foregroundStyle(Color.appTextSecondary).frame(width: 76, alignment: .leading)
                    TextField("", text: nameBinding(d), prompt: Text("Judul transaksi").foregroundStyle(Color.appTextTertiary))
                        .font(.app(16, weight: .medium)).foregroundStyle(Color.appText)
                        .focused($focusedId, equals: d.id)
                        .submitLabel(.done)
                        .onSubmit { focusedId = nil }
                }
                .frame(height: 48)
                
                chips(d)
                if let note = d.note {
                    Label(note, systemImage: "eye").font(.app(13)).foregroundStyle(Color.stWarn).padding(.top, 8)
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
                        .padding(.top, 8)
                }
                if aiOn && aiOut && d.reader != .ai {
                    Button { plusReason = .aiHelp } label: {
                        Text(L("Coba Saku Plus untuk AI tanpa batas")).font(.app(15, weight: .semibold)).foregroundStyle(Color.appPrimaryText)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                }

                Spacer(minLength: 16)

                HStack(spacing: 12) {
                    if lv == .complete {
                        Button { if !swiping { ignore(d) } } label: {
                            Text("Abaikan").font(.app(16, weight: .medium)).foregroundStyle(Color.appTextSecondary)
                                .padding(.horizontal, 12).frame(height: 48)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving)
                        Button { if !swiping { save(d) } } label: {
                            HStack(spacing: 8) {
                                if isSaving { ProgressView().tint(.white).scaleEffect(0.8) }
                                Text(isSaving ? L("Menyimpan…") : failure != nil ? L("Coba lagi") : L("Simpan"))
                            }
                            .font(.app(17, weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(Color.appPrimary, in: Capsule())
                        }
                        .buttonStyle(PressScaleStyle())
                        .disabled(isSaving)
                    } else {
                        Button { if !swiping { ignore(d) } } label: {
                            Text("Abaikan").font(.app(17, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
                                .frame(maxWidth: .infinity).frame(height: 48)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving)
                    }
                }
            }
            .padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 16)
            .frame(maxWidth: .infinity, minHeight: cardHeight - Self.heroHeight, alignment: .topLeading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .frame(height: cardHeight - Self.heroHeight)
        }
        .background(Color.appBackground)
        .clipShape(RoundedRectangle(cornerRadius: 32))
        .overlay {
            RoundedRectangle(cornerRadius: 32)
                .strokeBorder(lv == .complete ? Color.appDivider : Color.stDash,
                              style: lv == .complete ? StrokeStyle(lineWidth: 1) : StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        }
        .id(d.id)
    }

    /// The coloured top of the card: kind, arrival time and source on the first line, the amount below, the AI button
    /// hanging over its lower edge.
    private func cardHeader(_ d: Draft, reading: Bool) -> some View {
        let thumb = d.imageId.flatMap { DraftImageStore.thumbnail($0) }
        let failed = rescanFailed.contains(d.id)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button { if !swiping { sheet = DraftSheet(draftId: d.id, kind: .type) } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: d.kindIcon).font(.system(size: 13, weight: .bold))
                        Text(d.kindTitle)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                    }
                    .font(.app(14, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(height: 36)
                    .background(Color.white.opacity(0.22), in: Capsule())
                    .padding(.vertical, 4).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Tipe"))
                .accessibilityValue(d.kindTitle)
                Spacer(minLength: 0)
                Label(DateFormatter.arrivalTime.string(from: d.createdAt), systemImage: "clock")
                    .font(.app(12, weight: .medium)).monospacedDigit().foregroundStyle(.white.opacity(0.92))
                    .padding(.trailing, 4)
                Button { if !swiping { sourceSheet = DraftImageItem(id: d.id) } } label: {
                    Group {
                        if let thumb {
                            Image(uiImage: thumb).resizable().scaledToFill()
                        } else {
                            Image(systemName: d.sourceIcon).font(.system(size: 16, weight: .medium)).foregroundStyle(.white)
                        }
                    }
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.28))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        if thumb != nil { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white, lineWidth: 2) }
                    }
                    .padding(4).contentShape(Rectangle())
                    .opacity(reading && pulse ? 0.45 : 1)
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel(thumb != nil ? L("Lihat gambar asli") : d.sourceLabel)
            }

            if reading {
                Capsule().fill(Color.white.opacity(0.22)).frame(width: 200, height: 44)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .opacity(pulse ? 0.45 : 1)
                    .accessibilityHidden(true)
            } else {
                Button { if !swiping { sheet = DraftSheet(draftId: d.id, kind: .amount) } } label: {
                    Group {
                        if let amount = d.amount {
                            HStack(alignment: .top, spacing: 2) {
                                Text("Rp").font(.app(16, weight: .medium)).opacity(0.85).padding(.top, 6)
                                Text(amount.formattedAsDigits())
                                    .font(.app(amount.formattedAsDigits().count > 7 ? 38 : 46, weight: .light)).tracking(-1.5).monospacedDigit()
                                    .lineLimit(1).minimumScaleFactor(0.5)
                            }
                        } else {
                            HStack(spacing: 16) {
                                HStack(alignment: .top, spacing: 8) {
                                    Text("Rp").font(.app(16, weight: .medium)).padding(.top, 6)
                                    Text("0").font(.app(46, weight: .light)).tracking(-1.5)
                                }
                                .opacity(0.5)
                                Label("Ketuk untuk isi nominal", systemImage: "pencil").font(.app(13, weight: .semibold))
                                    .multilineTextAlignment(.leading).frame(maxWidth: 130, alignment: .leading)
                            }
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Nominal"))
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: Self.heroHeight, maxHeight: Self.heroHeight, alignment: .topLeading)
        .background(headerColor(d), in: RoundedRectangle(cornerRadius: 32))
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 8) {
                    if let r = aiReason, r.id == d.id, !failed {
                        Text(r.text).font(.app(13, weight: .semibold)).foregroundStyle(Color.appText)
                            .padding(.horizontal, 12).frame(height: 40)
                            .background(Color.appBackground, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.appDivider, lineWidth: 1))
                            .transition(.opacity)
                    }
                    if failed {
                        Label(L("Gagal. Ketuk untuk coba lagi"), systemImage: "arrow.counterclockwise")
                            .font(.app(13, weight: .semibold)).foregroundStyle(Color.appError)
                            .padding(.horizontal, 12).frame(height: 40)
                            .background(Color.appBackground, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.appDivider, lineWidth: 1))
                    }
                    sparkleButton(d)
                }
                .offset(y: 24).padding(.trailing, 24)
        }
    }

    /// Short flags under the rows: looks like another draft, about to expire.
    @ViewBuilder private func chips(_ d: Draft) -> some View {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: d.expiresAt).day.map { max($0, 1) }
        let expiring = (days ?? 99) <= 3
        if d.duplicateNote != nil || expiring {
            HStack(spacing: 6) {
                if let note = d.duplicateNote {
                    chip("doc.on.doc", L("Mirip"), tint: Color.stWarn, label: L("Mirip transaksi lain.") + " " + note)
                }
                if expiring, let days {
                    chip("hourglass", L("%lld hari", days), tint: Color.appTextSecondary, label: L("Dibuang otomatis dalam %lld hari", days))
                }
            }
            .padding(.top, 8)
        }
    }

    private func chip(_ icon: String, _ text: String, tint: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 12, weight: .bold)).foregroundStyle(tint)
            Text(text).font(.app(12, weight: .medium)).foregroundStyle(Color.appText)
        }
        .padding(.horizontal, 10).frame(height: 32)
        .background(Color.appFill, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    /// The source of a draft: the picture it was read from (full height) or the words it was made from (as tall as the text).
    @ViewBuilder private func sourceSheetContent(_ d: Draft) -> some View {
        let words = d.rawText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let image = d.imageId.flatMap { DraftImageStore.image($0) }
        let content = VStack(alignment: .leading, spacing: 12) {
            Text(image != nil ? L("Gambar asli") : L("Teks asli")).font(.app(22, weight: .bold)).tracking(-0.3)
            Text(sourceLine(d, reading: false)).font(.app(14)).foregroundStyle(Color.appTextSecondary)
            if let why = d.fallbackReason { Text(L("Dibaca tanpa AI · %@", why)).font(.app(13)).foregroundStyle(Color.appTextSecondary) }
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.appDivider, lineWidth: 1))
                    .padding(.top, 4)
            } else if !words.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "quote.opening").font(.system(size: 12, weight: .heavy)).foregroundStyle(Color.appTextTertiary).padding(.top, 3)
                    Text(words).font(.system(size: 14, design: .monospaced)).foregroundStyle(Color.appText).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .foregroundStyle(Color.appText)
        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        let close = PrimaryButton(title: L("Tutup")) { sourceSheet = nil }
        if image != nil { content.filterSheet(fullHeight: true) { close } } else { content.filterSheet { close } }
    }

    /// "Notifikasi BCA · Masuk 09.41 · AI": shown when the source icon is tapped.
    private func sourceLine(_ d: Draft, reading: Bool) -> String {
        if reading { return L("Membaca dengan AI") }
        let reader = d.reader.map { $0 == .ai ? " · AI" : " · " + L("Aturan") } ?? ""
        return d.sourceLabel + " · " + Self.arrival(d.createdAt) + reader
    }

    /// The "Baca dengan AI" button as a round-ended icon beside Simpan.
    private func sparkleButton(_ d: Draft) -> some View {
        let busy = rescanning.contains(d.id), failed = rescanFailed.contains(d.id), out = aiOut
        let done = d.reader == .ai
        // why the button cannot read again: nothing left to read, or AI is off
        let blocked: String? = done ? L("Sudah dibaca AI") : d.rawText == nil ? L("Tidak ada teks asli") : !(aiOn && RemoteSmartParser.isAvailable) ? L("AI belum aktif") : nil
        let grey = blocked != nil && !done
        return Button {
            if swiping { return }
            if let blocked {
                let note = (id: d.id, text: blocked)
                withAnimation(.settle(0.3)) { aiReason = note }
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    if aiReason?.id == note.id && aiReason?.text == note.text { withAnimation(.settle(0.3)) { aiReason = nil } }
                }
            } else {
                rescan(d)
            }
        } label: {
            Group {
                if busy { ProgressView().tint(.white) }
                else { Image(systemName: failed ? "exclamationmark.circle.fill" : done ? "checkmark" : "sparkles").font(.system(size: 22, weight: done ? .bold : .regular)) }
            }
            .foregroundStyle(failed ? Color.appError : .white)
            .frame(width: 52, height: 52)
            .background(failed ? Color.stDangerBg : (out && blocked == nil) || grey ? Color.appTextTertiary : Color.appPrimary, in: Circle())
            .overlay(Circle().strokeBorder(Color.appBackground, lineWidth: 3))
        }
        .buttonStyle(PressScaleStyle())
        .disabled(busy || (out && blocked == nil))
        .accessibilityLabel(busy ? L("Memindai ulang…") : failed ? L("Gagal. Ketuk untuk coba lagi") : blocked ?? (out ? L("Jatah habis") : L("Baca dengan AI")))
    }

    /// "Notifikasi BCA sudah tercatat sebagai cicilan iPhone 15": information only, with Batalkan (K5).
    private func cardView(_ item: StackItem) -> some View {
        switch item {
        case .draft(let d): AnyView(card(d))
        case .notice(let n): AnyView(noticeCard(n))
        }
    }

    private func itemColor(_ item: StackItem) -> Color {
        switch item {
        case .draft(let d): headerColor(d)
        case .notice: Self.noticeGray
        }
    }

    private func itemTitle(_ item: StackItem) -> String {
        switch item {
        case .draft(let d): d.kindTitle
        case .notice: L("Sudah tercatat")
        }
    }

    private static let noticeGray = Color(light: 0x5F5E5A, dark: 0x4A4944)

    /// "Notifikasi myBCA sudah tercatat sebagai tagihan berulang Spotify": a card at the front of the stack, same size as
    /// a draft. Information only: Mengerti dismisses it for good, Batalkan hands the notification back as a draft (K5).
    private func noticeCard(_ n: SkippedNotice) -> some View {
        let d = n.draft
        let (kind, name): (String, String) = switch n.match {
        case .installment(let t): (L("cicilan"), t)
        case .bill(let b): (L("tagihan berulang"), b)
        }
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Label(L("Sudah tercatat"), systemImage: "checkmark.circle")
                        .font(.app(14, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(height: 36)
                        .background(Color.white.opacity(0.22), in: Capsule())
                    Spacer(minLength: 0)
                    Label(DateFormatter.arrivalTime.string(from: n.at), systemImage: "clock")
                        .font(.app(12, weight: .medium)).monospacedDigit().foregroundStyle(.white.opacity(0.92))
                }
                if let amount = d.amount {
                    HStack(alignment: .top, spacing: 2) {
                        Text("Rp").font(.app(16, weight: .medium)).opacity(0.85).padding(.top, 6)
                        Text(amount.formattedAsDigits())
                            .font(.app(amount.formattedAsDigits().count > 7 ? 38 : 46, weight: .light)).tracking(-1.5).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.5)
                    }
                    .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: Self.heroHeight, maxHeight: Self.heroHeight, alignment: .topLeading)
            .background(Self.noticeGray, in: RoundedRectangle(cornerRadius: 32))
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        noticeRow(L("Judul"), name)
                        noticeRow(L("Tanggal"), Self.dateLabel(d.date), icon: "calendar")
                        HStack(alignment: .top, spacing: 12) {
                            Text(L("Notifikasi")).font(.app(15)).foregroundStyle(Color.appTextSecondary)
                                .frame(width: 76, alignment: .leading)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(d.sourceName ?? d.sourceLabel).font(.app(16, weight: .medium)).foregroundStyle(Color.appText)
                                if let words = d.rawText?.trimmingCharacters(in: .whitespacesAndNewlines), !words.isEmpty {
                                    Text(words).font(.app(14)).foregroundStyle(Color.appTextSecondary).lineLimit(2)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 13)
                        richText(L("Sudah ada di %@ **%@**, jadi notifikasi ini tidak dibuat draf agar tidak tercatat dua kali. Bukan itu? Ketuk **Batalkan**.", kind, name))
                            .font(.app(14)).foregroundStyle(Color.appText).lineSpacing(2)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.stGreen.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(alignment: .leading) { Capsule().fill(Color.stGreen).frame(width: 3).padding(.vertical, 8) }
                            .padding(.top, 14)
                    }
                }
                .scrollBounceBehavior(.basedOnSize).scrollIndicators(.hidden)
                Spacer(minLength: 8)
                HStack(spacing: 12) {
                    Button { if !swiping { withAnimation(.settle(0.3)) { store.cancelNotice(n) } } } label: {
                        Text("Batalkan").font(.app(16, weight: .medium)).foregroundStyle(Color.appTextSecondary)
                            .padding(.horizontal, 12).frame(height: 48)
                    }
                    .buttonStyle(.plain)
                    Button { if !swiping { withAnimation(.settle(0.3)) { store.dismissNotice(n) } } } label: {
                        Text("Mengerti").font(.app(17, weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(Color.appPrimary, in: Capsule())
                    }
                    .buttonStyle(PressScaleStyle())
                }
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color.appBackground)
        .clipShape(RoundedRectangle(cornerRadius: 32))
        .overlay { RoundedRectangle(cornerRadius: 32).strokeBorder(Color.appDivider, lineWidth: 1) }
        .id(n.id)
    }

    /// Same row as the draft fields, without the chevron.
    private func noticeRow(_ label: String, _ value: String, icon: String? = nil) -> some View {
        DetailRow(label: label, value: value, icon: icon, showsChevron: false, height: 48)
            .padding(.horizontal, -24).padding(.trailing, 4)
    }

    private struct Field {
        let label: String
        let value: String
        let icon: String
        let isMissing: Bool
        let kind: DraftFieldSheet.Kind
        var wallet: Account?
        var category: Category?
    }

    private func fields(_ d: Draft) -> [Field] {
        let wallet = store.accounts.first { $0.id == d.accountId }
        let target = store.accounts.first { $0.id == d.counterpartyAccountId }
        let category = store.categories.first { $0.id == d.categoryId }
        var result: [Field] = []
        if d.kind == .expense || d.kind == .income {
            result.append(Field(label: L("Kategori"), value: category?.name ?? "", icon: category?.icon ?? "tag", isMissing: category == nil, kind: .category, category: category))
        }
        result.append(Field(label: d.kind == .transfer ? L("Dari dompet") : L("Dompet"), value: wallet?.name ?? "", icon: "wallet.bifold",
                            isMissing: wallet == nil, kind: .wallet, wallet: wallet))
        if d.kind == .transfer {
            result.append(Field(label: L("Ke dompet"), value: target?.name ?? "", icon: "arrow.right", isMissing: target == nil, kind: .target, wallet: target))
        }
        result.append(Field(label: L("Tanggal"), value: Self.dateLabel(d.date), icon: "calendar", isMissing: false, kind: .date))
        return result
    }

    /// What the user typed, said or was notified with. One line at first; a tap opens all of it.
    private func originalText(_ d: Draft, _ words: String) -> some View {
        let open = expandedWords.contains(d.id)
        let isLong = words.contains("\n") || words.count > 34
        return Button {
            if swiping { return }
            withAnimation(.settle(0.3)) { if open { expandedWords.remove(d.id) } else { expandedWords.insert(d.id) } }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Spacer(minLength: 0)
                Image(systemName: "quote.opening").font(.system(size: 12, weight: .heavy)).foregroundStyle(Color.appTextTertiary)
                    .padding(.top, 3)
                Text(words).font(.app(14)).foregroundStyle(Color.appTextSecondary)
                    .lineLimit(open ? nil : 1).multilineTextAlignment(.center)
                if isLong {
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.appTextTertiary).padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 2).padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isLong)
        .accessibilityLabel(L("Teks asli"))
        .accessibilityValue(words)
    }

    private func iconBubble(_ name: String, missing: Bool) -> some View {
        Image(systemName: name).font(.system(size: 15, weight: .medium))
            .foregroundStyle(missing ? Color.stWarn : Color.appTextSecondary)
            .frame(width: 36, height: 36)
            .background(Color.appFill, in: Circle())
    }

    /// One line: icon, label, value at the end, chevron. A missing value turns icon and label amber with a plus.
    private func fieldRow(_ d: Draft, _ f: Field) -> some View {
        let isDate = f.kind == .date
        return Button { if !swiping { sheet = DraftSheet(draftId: d.id, kind: f.kind) } } label: {
            DetailRow(label: f.label, value: f.isMissing ? (f.kind == .category ? L("Belum dipilih") : L("Pilih")) : f.value,
                      wallet: f.isMissing ? nil : f.wallet, categoryMark: f.isMissing ? nil : f.category,
                      icon: isDate ? "calendar" : nil, showsChevron: true, height: 48, isPlaceholder: f.isMissing)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(f.label)
        .accessibilityValue(f.isMissing ? "" : f.value)
    }

    // MARK: Other screens

    private var emptyQueue: some View {
        VStack(spacing: 0) {
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

    /// "Draf diabaikan  Urungkan": a dark pill with words only (a check mark would read as "done", which is wrong for
    /// Abaikan). Sits in the band of page marks between the card and the bottom bar, so it never covers a button.
    @ViewBuilder private var toastView: some View {
        if let toast {
            HStack(spacing: 14) {
                Text(toast.text).font(.app(15, weight: .medium)).lineLimit(1)
                Button { undo(toast) } label: {
                    Text("Urungkan").font(.app(15, weight: .semibold)).foregroundStyle(Color(light: 0x3DDC97, dark: 0x3DDC97))
                        .padding(.horizontal, 14).frame(height: 36)
                        .background(Color.white.opacity(0.12), in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
            }
            .foregroundStyle(.white)
            .padding(.leading, 20).padding(.trailing, 6).frame(height: 48)
            .background(Color(light: 0x111111, dark: 0x2C2C2E), in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
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
        let rest = store.drafts.count - ready.count
        return SmartSheet(tone: .consent, icon: "checkmark.circle", title: L("Simpan %lld transaksi yang lengkap?", ready.count),
                          message: rest > 0 ? L("%lld draf yang belum lengkap tetap di daftar supaya bisa kamu cek nanti.", rest)
                              : L("Semua draf akan disimpan ke transaksimu.")) {
            SmartSheetFooter(primary: L("Simpan %lld transaksi", ready.count), secondary: L("Batal"),
                             onPrimary: { saveAllComplete() }) { showsSaveAll = false }
        }
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
        let items = Array(ready.reversed())
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
            try? await Task.sleep(for: .seconds(6))
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

/// Turns the edge-swipe back gesture off while the screen is open, so a swipe on the card stack never pops the page.
/// The back button still works.
private struct NoSwipeBack: UIViewControllerRepresentable {
    final class Host: UIViewController {
        /// Both back gestures: the one from the left edge and, on newer iOS, the one that works from anywhere on the page.
        private func setBackSwipe(_ enabled: Bool) {
            navigationController?.interactivePopGestureRecognizer?.isEnabled = enabled
            if #available(iOS 26.0, *) {
                navigationController?.interactiveContentPopGestureRecognizer?.isEnabled = enabled
            }
        }
        override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); setBackSwipe(false) }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); setBackSwipe(false) }
        // SwiftUI may turn the gesture back on while it lays the page out
        override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); setBackSwipe(false) }
        override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); setBackSwipe(true) }
    }
    func makeUIViewController(context: Context) -> Host { Host() }
    func updateUIViewController(_ uiViewController: Host, context: Context) {}
}
