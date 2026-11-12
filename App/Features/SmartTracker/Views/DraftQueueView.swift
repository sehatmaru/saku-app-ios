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

    /// Oldest first: the order the drafts came in, and the order "Simpan semua" records them.
    private var queue: [Draft] { store.drafts.sorted { $0.createdAt < $1.createdAt } }

    private var ready: [Draft] { queue.filter { $0.isComplete && !store.needsPeriodChoice($0) } }

    /// Swiping only browses: left brings the next draft to the front, right the one before it, round and round.
    @State private var browse = 0
    @State private var drag: CGFloat = 0

    private var stackPosition: Int {
        let n = queue.count
        return n == 0 ? 0 : min(max(browse, 0), n - 1)
    }

    /// `queue` turned so the browsed draft is first.
    private var stack: [Draft] {
        let q = queue, i = stackPosition
        return Array(q[i...] + q[..<i])
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

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .global)
            .onChanged { value in
                guard queue.count > 1, abs(value.translation.width) > abs(value.translation.height) else { return }
                // the first draft cannot be pulled right, the last one cannot be pulled left
                swiping = true
                if (stackPosition == 0 && value.translation.width > 0) || (stackPosition == queue.count - 1 && value.translation.width < 0) {
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
                guard queue.count > 1, abs(drag) > 0, abs(drag) > 90 || abs(flick) > 220 else { drag = 0; return }
                commit(step: (drag < 0 || flick < -220) ? 1 : -1)
            }
    }

    /// Brings another draft to the front: the old front card leaves to the side while the next one grows from behind.
    private func commit(step: Int) {
        let target = min(max(stackPosition + step, 0), queue.count - 1)
        guard !busy, queue.count > 1, target != stackPosition else { drag = 0; return }
        busy = true
        Task { try? await Task.sleep(for: .milliseconds(300)); busy = false }
        focusedId = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        exiting = queue[stackPosition].id
        exitDir = target > stackPosition ? -1 : 1
        browse = target
        drag = 0
    }

    /// Where draft `j` sits relative to the front one: 0 front, 1 and 2 behind it, -1 the one before it.
    private func relative(_ j: Int, _ pos: Int, _ n: Int) -> Int { j - pos }

    private static let ease = Animation.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.28)

    /// Every draft is a real card. The front one follows the finger; the ones behind sit higher, smaller and blurred, and
    /// sharpen as the front one is pulled away.
    private var cardStack: some View {
        let n = queue.count, pos = stackPosition
        let t = min(abs(drag) / 140, 1)
        return ZStack(alignment: .top) {
            ForEach(Array(queue.enumerated()), id: \.element.id) { j, d in
                let rel = relative(j, pos, n)
                if (rel >= -1 && rel <= 2) || d.id == exiting {
                    let front = rel == 0
                    let out = d.id == exiting && !front
                    let under = (drag < 0 && rel > 0) || (drag > 0 && rel == -1)
                    let behind = !out && (rel > 0 || (rel == -1 && drag > 0))
                    let eff = max(0, Double(abs(rel)) - (under ? t : 0))
                    card(d)
                        .frame(height: Self.cardHeight)
                        .allowsHitTesting(front)
                        .simultaneousGesture(swipe)
                        .blur(radius: behind ? 2.5 * eff : 0)
                        .scaleEffect(behind ? 1 - 0.06 * eff : 1, anchor: .top)
                        .opacity(out ? 0 : behind ? (eff > 2 ? 0 : 1 - 0.12 * eff) : front ? 1 : 0)
                        .offset(x: front ? drag : out ? exitDir * 520 : behind ? 0 : -520,
                                y: behind ? (eff > 2 ? -32 : -18 * eff) : 0)
                        .zIndex(out ? 6 : front ? 5 : behind ? 4 - eff : 1)
                        .animation(dragging ? nil : Self.ease, value: drag)
                        .animation(Self.ease, value: pos)
                        .animation(Self.ease, value: exiting)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: Self.cardHeight, alignment: .top)
    }

    /// One height for every card, state and kind: the tallest realistic content, capped so it fits small screens.
    private static var cardHeight: CGFloat { min(580, max(500, UIScreen.main.bounds.height - 300)) }

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
                    .padding(.horizontal, 20).padding(.top, queue.count > 2 ? 46 : queue.count > 1 ? 28 : 12)
                // the marks sit halfway between the card and the bar below
                Spacer(minLength: 0)
                pageDots
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
            }

            // Notifications already recorded: information only, kept for 7 days (K5, K10).
            if !store.notices.isEmpty {
                VStack(spacing: 10) {
                    ForEach(store.notices) { notice in
                        noticeRow(notice)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .animation(.settle(0.3), value: store.notices.map(\.id))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .pinnedFooter(separator: true) {
            if store.drafts.count > 1 && focusedId == nil { bulkBar }
        }
    }

    /// One mark per draft in the colour of its kind. The track slides so the front draft is centred; the front mark is the
    /// tallest, the ones further away shrink and fade out.
    private var pageDots: some View {
        let sizes: [(CGFloat, CGFloat)] = [(22, 30), (16, 22), (12, 18), (9, 14)]
        let n = queue.count, pos = stackPosition
        let curve = Animation.timingCurve(0.22, 0.9, 0.25, 1, duration: 0.45)
        return GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(Array(queue.enumerated()), id: \.element.id) { k, d in
                    let dist = abs(k - pos)
                    let size = dist < sizes.count ? sizes[dist] : (8, 12)
                    Button { commit(step: k - pos) } label: {
                        RoundedRectangle(cornerRadius: dist == 0 ? 6 : 4)
                            .fill(headerColor(d))
                            .frame(width: size.0, height: size.1)
                            .opacity(dist > 3 ? 0 : dist == 0 ? 1 : 0.55)
                            .frame(width: 24, height: 44)
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(dist <= 3)
                    .accessibilityLabel(d.kindTitle)
                }
            }
            .frame(width: CGFloat(n) * 24, alignment: .leading)
            .offset(x: geo.size.width / 2 - 24 * CGFloat(pos) - 12)
            .animation(curve, value: pos)
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
            cardHeader(d, reading: rescanning.contains(d.id))
                .zIndex(1)
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
                // name first, then the rest, one line each
                HStack(spacing: 14) {
                    Image(systemName: "square.and.pencil").font(.system(size: 20)).foregroundStyle(Color.appTextSecondary).frame(width: 24)
                    Text(L("Nama")).font(.app(16)).foregroundStyle(Color.appTextSecondary)
                    TextField("", text: nameBinding(d), prompt: Text("Nama transaksi").foregroundStyle(Color.appTextTertiary))
                        .font(.app(16)).foregroundStyle(Color.appText).multilineTextAlignment(.trailing)
                        .focused($focusedId, equals: d.id)
                        .submitLabel(.done)
                        .onSubmit { focusedId = nil }
                    Image(systemName: "pencil").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.appTextTertiary)
                }
                .frame(height: 44)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.appDivider).frame(height: 1) }
                ForEach(Array(rows.enumerated()), id: \.element.label) { _, field in
                    fieldRow(d, field)
                }

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
            .padding(.horizontal, 20).padding(.top, 30).padding(.bottom, 14)
            .frame(maxWidth: .infinity, minHeight: Self.cardHeight - 150, alignment: .topLeading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .frame(height: Self.cardHeight - 150)
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
                        Image(systemName: d.kindIcon).font(.system(size: 14, weight: .bold))
                        Text(d.kindTitle)
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                    }
                    .font(.app(15, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).frame(height: 44)
                    .background(Color.white.opacity(0.22), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Tipe"))
                .accessibilityValue(d.kindTitle)
                Spacer(minLength: 0)
                Label(DateFormatter.arrivalTime.string(from: d.createdAt), systemImage: "clock")
                    .font(.app(13, weight: .medium)).monospacedDigit().foregroundStyle(.white.opacity(0.92))
                    .padding(.trailing, 4)
                Button { if !swiping { sourceSheet = DraftImageItem(id: d.id) } } label: {
                    Group {
                        if let thumb {
                            Image(uiImage: thumb).resizable().scaledToFill()
                        } else {
                            Image(systemName: d.sourceIcon).font(.system(size: 18, weight: .medium)).foregroundStyle(.white)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.28))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        if thumb != nil { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white, lineWidth: 2) }
                    }
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
                                Text("Rp").font(.app(18)).opacity(0.85).padding(.top, 7)
                                Text(amount.formattedAsDigits())
                                    .font(.app(amount.formattedAsDigits().count > 7 ? 44 : 52, weight: .ultraLight)).tracking(-2.5).monospacedDigit()
                                    .lineLimit(1).minimumScaleFactor(0.5)
                            }
                        } else {
                            HStack(spacing: 16) {
                                HStack(alignment: .top, spacing: 8) {
                                    Text("Rp").font(.app(20)).padding(.top, 10)
                                    Text("0").font(.app(52, weight: .ultraLight)).tracking(-2.5)
                                }
                                .opacity(0.5)
                                Label("Ketuk untuk isi nominal", systemImage: "pencil").font(.app(13, weight: .semibold))
                                    .multilineTextAlignment(.leading).frame(maxWidth: 130, alignment: .leading)
                            }
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Nominal"))
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 150, alignment: .topLeading)
        .background(headerColor(d), in: RoundedRectangle(cornerRadius: 32))
        .overlay(alignment: .bottomTrailing) {
            if canRescan(d) || rescanning.contains(d.id) {
                HStack(spacing: 8) {
                    if failed {
                        Label(L("Gagal. Ketuk untuk coba lagi"), systemImage: "arrow.counterclockwise")
                            .font(.app(13, weight: .semibold)).foregroundStyle(Color.appError)
                            .padding(.horizontal, 12).frame(height: 40)
                            .background(Color.appBackground, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.appDivider, lineWidth: 1))
                    }
                    sparkleButton(d)
                }
                .offset(y: 24).padding(.trailing, 20)
            }
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
        if image != nil { content.filterSheet(detent: .constant(.large)) } else { content.filterSheet() }
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
        return Button { if !swiping { rescan(d) } } label: {
            Group {
                if busy { ProgressView().tint(.white) } else { Image(systemName: failed ? "exclamationmark.circle.fill" : "sparkles").font(.system(size: 22)) }
            }
            .foregroundStyle(failed ? Color.appError : .white)
            .frame(width: 52, height: 52)
            .background(failed ? Color.stDangerBg : out ? Color.appTextTertiary : Color.appPrimary, in: Circle())
            .overlay(Circle().strokeBorder(Color.appBackground, lineWidth: 3))
        }
        .buttonStyle(PressScaleStyle())
        .disabled(busy || out)
        .accessibilityLabel(busy ? L("Memindai ulang…") : failed ? L("Gagal. Ketuk untuk coba lagi") : out ? L("Jatah habis") : L("Baca dengan AI"))
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
        var result: [Field] = []
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
        return Button { if !swiping { sheet = DraftSheet(draftId: d.id, kind: f.kind) } } label: {
            HStack(spacing: 14) {
                Image(systemName: f.isMissing ? "plus.circle" : f.icon).font(.system(size: 20))
                    .foregroundStyle(f.isMissing ? Color.stWarn : Color.appTextSecondary).frame(width: 24)
                Text(f.label).font(.app(16, weight: f.isMissing ? .semibold : .regular))
                    .foregroundStyle(f.isMissing ? Color.stWarn : Color.appTextSecondary)
                Spacer(minLength: 8)
                if !f.isMissing {
                    Text(f.value).font(.app(16)).foregroundStyle(Color.appText).lineLimit(1)
                }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.appTextTertiary)
            }
            .frame(height: 44)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(Color.appDivider).frame(height: 1) }
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
    /// Abaikan). Sits just above the bottom bar, where the Simpan and Abaikan buttons are.
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
