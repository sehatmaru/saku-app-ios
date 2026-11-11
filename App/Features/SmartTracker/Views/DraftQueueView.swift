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
        return n == 0 ? 0 : ((browse % n) + n) % n
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

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard stack.count > 1, abs(value.translation.width) > abs(value.translation.height) else { return }
                swiping = true
                drag = value.translation.width
            }
            .onEnded { value in
                let flick = value.predictedEndTranslation.width
                Task { try? await Task.sleep(for: .milliseconds(350)); swiping = false }
                guard stack.count > 1, abs(drag) > 0, abs(drag) > 90 || abs(flick) > 220 else {
                    withAnimation(.spring(duration: 0.35, bounce: 0.25)) { drag = 0 }
                    return
                }
                let step = (drag < 0 || flick < -220) ? 1 : -1
                focusedId = nil
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                // The front card leaves to the side; the card under it has grown to full size by then, so swapping is invisible.
                withAnimation(.easeIn(duration: 0.2)) { drag = CGFloat(-step) * 480 }
                Task {
                    try? await Task.sleep(for: .milliseconds(210))
                    var instant = SwiftUI.Transaction(); instant.disablesAnimations = true
                    withTransaction(instant) { browse += step; drag = 0 }
                }
            }
    }

    /// What waits behind the front card. The next draft (or the previous one when dragging right) is drawn for real,
    /// small at first and growing to full size as the front card is pulled away; a third card is a plain shape.
    @ViewBuilder private func stackPeek() -> some View {
        let n = stack.count
        ZStack {
            if n > 2 {
                RoundedRectangle(cornerRadius: 24).fill(Color.stChip.opacity(0.55))
                    .scaleEffect(x: 0.86, y: 1, anchor: .bottom).offset(y: 24)
            }
            if n > 1 {
                let progress = min(abs(drag) / 200, 1)
                GeometryReader { geo in
                    card(drag > 0 ? stack[n - 1] : stack[1])
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                        .background(Color.appFill)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .allowsHitTesting(false)
                        .scaleEffect(0.93 + 0.07 * progress, anchor: .bottom)
                        .offset(y: 12 * (1 - progress))
                }
            }
        }
        .accessibilityHidden(true)
    }

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
        ScrollView {
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

                if let front = stack.first {
                    Text(L("%lld dari %lld", stackPosition + 1, stack.count))
                        .font(.app(13, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(Color.appTextSecondary)
                        .padding(.horizontal, 24).padding(.top, 20)
                    // The oldest draft sits in front; up to two cards peek out below it.
                    ZStack {
                        card(front)
                            .offset(x: drag)
                            .simultaneousGesture(swipe)
                            .background(alignment: .bottom) { stackPeek() }
                            .transition(.opacity)
                    }
                    .padding(.horizontal, 16).padding(.top, 10)
                    .padding(.bottom, stack.count > 2 ? 40 : stack.count > 1 ? 28 : 24)
                }

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
        .pinnedFooter(separator: true) {
            if store.drafts.count > 1 && focusedId == nil { bulkBar }
        }
    }

    private var bulkBar: some View {
        SmartSheetFooter(primary: L("Simpan (%lld)", ready.count), isEnabled: !ready.isEmpty,
                         secondary: L("Abaikan (%lld)", store.drafts.count),
                         onPrimary: { showsSaveAll = true }) { showsDeleteAll = true }
    }

    // MARK: Card

    private func card(_ d: Draft) -> some View {
        let lv = level(d)
        let isSaving = saving.contains(d.id)
        let failure = failures[d.id]
        let reading = rescanning.contains(d.id)
        let rows = fields(d)
        return VStack(alignment: .leading, spacing: 8) {
            // kind on the left, where it came from on the right
            HStack(spacing: 8) {
                Button { if !swiping { sheet = DraftSheet(draftId: d.id, kind: .type) } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: d.kindIcon).font(.system(size: 12, weight: .bold))
                        Text(d.kindTitle)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                    }
                    .font(.app(14, weight: .semibold)).foregroundStyle(d.kindColor)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.appBackground, in: Capsule())
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Tipe"))
                .accessibilityValue(d.kindTitle)
                Spacer(minLength: 0)
                Button {
                    if swiping { return }
                    withAnimation(.settle(0.3)) {
                        if expandedSource.contains(d.id) { expandedSource.remove(d.id) } else { expandedSource.insert(d.id) }
                    }
                } label: {
                    Image(systemName: d.sourceIcon).font(.system(size: 15, weight: .medium)).foregroundStyle(Color.appPrimaryText)
                        .frame(width: 32, height: 32).background(Color.appBackground, in: Circle())
                        .opacity(reading && pulse ? 0.45 : 1)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel(d.sourceLabel)
            }

            if let words = d.rawText?.trimmingCharacters(in: .whitespacesAndNewlines), !words.isEmpty, !d.isUnreadable {
                originalText(d, words)
            }

            if expandedSource.contains(d.id) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: d.sourceIcon).font(.system(size: 16)).foregroundStyle(Color.appPrimaryText).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sourceLine(d, reading: reading))
                        if let why = d.fallbackReason { Text(L("Dibaca tanpa AI · %@", why)) }
                    }
                    .font(.app(13)).foregroundStyle(Color.appTextSecondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 16))
                .transition(.opacity)
            }

            if d.isUnreadable {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Smart Tracker belum paham kalimat ini").font(.app(15, weight: .semibold))
                    Text("“\(d.title)”").font(.app(15)).italic().foregroundStyle(Color.appTextSecondary)
                    Text("Isi nominal dan detailnya di bawah.").font(.app(13)).foregroundStyle(Color.appTextSecondary)
                }
                .padding(.top, 6)
            }

            if reading {
                Capsule().fill(Color.stChip).frame(width: 200, height: 44)
                    .frame(maxWidth: .infinity).padding(.top, 14).padding(.bottom, 4)
                    .opacity(pulse ? 0.45 : 1)
                    .accessibilityHidden(true)
            } else {
                Button { if !swiping { sheet = DraftSheet(draftId: d.id, kind: .amount) } } label: {
                    HStack(alignment: .top, spacing: 4) {
                        Text("Rp").font(.app(18)).foregroundStyle(Color.appTextTertiary).padding(.top, 8)
                        Text(d.amount.map { $0.formattedAsDigits() } ?? "0")
                            .font(.app(56, weight: .ultraLight)).tracking(-2).monospacedDigit()
                            .foregroundStyle(d.amount == nil ? Color.appTextTertiary : d.kind == .income ? Color.stGreen : Color.appText)
                            .lineLimit(1).minimumScaleFactor(0.5)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10).padding(.bottom, d.amount == nil ? 0 : 6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Nominal"))
                if d.amount == nil {
                    Text("Ketuk untuk isi nominal").font(.app(13)).foregroundStyle(Color.stWarn)
                        .frame(maxWidth: .infinity).padding(.bottom, 6)
                }
            }

            // name first, then the rest as plain rows
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "textformat").font(.system(size: 17)).foregroundStyle(Color.appTextSecondary).frame(width: 24)
                    TextField("", text: nameBinding(d), prompt: Text("Nama transaksi").foregroundStyle(Color.appTextTertiary))
                        .font(.app(16)).foregroundStyle(Color.appText)
                        .focused($focusedId, equals: d.id)
                        .submitLabel(.done)
                        .onSubmit { focusedId = nil }
                    Image(systemName: "pencil").font(.system(size: 14)).foregroundStyle(Color.appTextTertiary)
                }
                .frame(minHeight: 52)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.appSeparator).frame(height: 1) }
                ForEach(Array(rows.enumerated()), id: \.element.label) { index, field in
                    fieldRow(d, field, isLast: index == rows.count - 1)
                }
            }
            .padding(.horizontal, 16)
            .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 16))

            if let note = d.duplicateNote {
                Label {
                    Text(L("Mirip transaksi lain.")).fontWeight(.semibold).foregroundStyle(Color.stWarn)
                        + Text(" " + note).foregroundStyle(Color.appTextSecondary)
                } icon: { Image(systemName: "doc.on.doc").foregroundStyle(Color.stWarn) }
                    .font(.app(13))
                    .padding(.top, 4)
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
            if aiOn && aiOut && d.reader != .ai {
                Button { plusReason = .aiHelp } label: {
                    Text(L("Coba Saku Plus untuk AI tanpa batas")).font(.app(15, weight: .semibold)).foregroundStyle(Color.appPrimaryText)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }

            // one row of buttons: Baca dengan AI, then Simpan (complete) or Abaikan (not yet)
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    if canRescan(d) { sparkleButton(d) }
                    if lv == .complete {
                        Button { if !swiping { save(d) } } label: {
                            HStack(spacing: 8) {
                                if isSaving { ProgressView().tint(.white).scaleEffect(0.8) }
                                Text(isSaving ? L("Menyimpan…") : failure != nil ? L("Coba lagi") : L("Simpan"))
                            }
                            .font(.app(16, weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(Color.appPrimary, in: Capsule())
                        }
                        .buttonStyle(PressScaleStyle())
                        .disabled(isSaving)
                    } else {
                        Button { if !swiping { ignore(d) } } label: {
                            Text("Abaikan").font(.app(16, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
                                .frame(maxWidth: .infinity).frame(height: 48)
                                .overlay(Capsule().strokeBorder(Color.appBorder, lineWidth: 1))
                        }
                        .buttonStyle(PressScaleStyle())
                        .disabled(isSaving)
                    }
                }
                if lv == .complete {
                    Button { if !swiping { ignore(d) } } label: {
                        Text("Abaikan").font(.app(15, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                }
            }
            .padding(.top, 6)
        }
        .padding(20)
        .background(lv == .unread ? Color.appBackground : Color.appFill, in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            if lv == .unread {
                RoundedRectangle(cornerRadius: 24).strokeBorder(Color.stDash, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
        }
        .id(d.id)
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
                if busy { ProgressView().controlSize(.small) } else { Image(systemName: "sparkles").font(.system(size: 20)) }
            }
            .foregroundStyle(failed ? Color.appError : out ? Color.appTextSecondary : Color.appPrimaryText)
            .frame(width: 56, height: 48)
            .background(failed || out ? Color.clear : Color.appPrimary.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(failed ? Color.appError : out ? Color.appDivider : Color.clear, lineWidth: 1))
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
                Image(systemName: "quote.opening").font(.system(size: 12, weight: .heavy)).foregroundStyle(Color.appTextTertiary)
                    .padding(.top, 3)
                Text(words).font(.system(size: 14, design: .monospaced)).foregroundStyle(Color.appText)
                    .lineLimit(open ? nil : 1).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isLong {
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.appTextTertiary).padding(.top, 4)
                }
            }
            .padding(.top, 2).padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isLong)
        .accessibilityLabel(L("Teks asli"))
        .accessibilityValue(words)
    }

    /// One plain row: icon, value (or a prompt in the warning colour when it is missing), chevron.
    private func fieldRow(_ d: Draft, _ f: Field, isLast: Bool) -> some View {
        let prompt: String = switch f.kind {
        case .category: L("Pilih kategori")
        case .target: L("Pilih dompet tujuan")
        default: L("Pilih dompet")
        }
        return Button { if !swiping { sheet = DraftSheet(draftId: d.id, kind: f.kind) } } label: {
            HStack(spacing: 12) {
                Image(systemName: f.icon).font(.system(size: 17))
                    .foregroundStyle(f.isMissing ? Color.stWarn : Color.appTextSecondary).frame(width: 24)
                if d.kind == .transfer, f.kind == .wallet || f.kind == .target, !f.isMissing {
                    Text(f.label).font(.app(14)).foregroundStyle(Color.appTextSecondary)
                }
                Text(f.isMissing ? prompt : f.value)
                    .font(.app(16, weight: f.isMissing ? .semibold : .regular)).lineLimit(1)
                    .foregroundStyle(f.isMissing ? Color.stWarn : Color.appText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.appTextTertiary)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { if !isLast { Rectangle().fill(Color.appSeparator).frame(height: 1) } }
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
