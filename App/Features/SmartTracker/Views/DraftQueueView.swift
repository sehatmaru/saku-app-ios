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

/// "Konfirmasi catatan" (design 4a): the drafts as a deck of cards. The top card shows everything and every
/// field can be changed in place; swipe it sideways to look at the next one, Simpan or Abaikan to deal with it
/// (with Urungkan for a few seconds), "Simpan semua" for the rest. Saving and deleting are held back until
/// the Urungkan toast is gone, so undoing never has to reverse a saved transaction.
struct DraftQueueView: View {
    let userId: String
    @ObservedObject private var store = DraftStore.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage("isBalanceVisible") private var isBalanceVisible = true

    private enum Outcome { case saved, ignored }
    private enum Field { case name, amount, type, category, wallet, date }
    private enum Sheet: String, Identifiable { case category, type, wallet, date, amount, name, all; var id: String { rawValue } }


    private struct Toast: Equatable { var text: String; var icon: String; var ids: [UUID]; var token = UUID() }

    /// The drafts present when the page opened, in order.
    @State private var session: [UUID] = []
    @State private var outcomes: [UUID: Outcome] = [:]
    @State private var committed: Set<UUID> = []
    @State private var commits: [UUID: Task<Void, Never>] = [:]
    @State private var selectedId: UUID?
    @State private var pose: CardPose = .rest
    @State private var sheet: Sheet?
    @State private var amountText = 0
    @State private var showsMenu = false
    @State private var flash: Field?
    @State private var editing: Draft?
    @State private var toast: Toast?
    @State private var toastShown = false
    @State private var errorMessage: String?
    @State private var original: [UUID: String?] = [:]
    @State private var remember: [UUID: Bool] = [:]
    @State private var hinted = false

    private var pending: [Draft] { session.compactMap { id in outcomes[id] == nil ? store.drafts.first { $0.id == id } : nil } }
    private var current: Draft? { pending.first { $0.id == selectedId } ?? pending.first }
    private var ready: [Draft] { pending.filter(\.isComplete) }
    private var savedCount: Int { outcomes.values.filter { $0 == .saved }.count }
    private var ignoredCount: Int { outcomes.values.filter { $0 == .ignored }.count }
    private var isPlain: Bool { current.map { $0.kind == .expense || $0.kind == .income } ?? true }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                topBar
                if let current {
                    // A scroll view that does not scroll: when the keyboard of a sheet squeezes the screen, the
                    // page stays pinned to the top instead of sliding up under the status bar.
                    GeometryReader { geo in
                        ScrollView {
                            VStack(spacing: 0) {
                                header(current)
                                deck(current)
                                dots(current)
                                actions(current)
                                Spacer(minLength: 8)
                                bulk
                            }
                            .frame(minHeight: geo.size.height)
                        }
                        .scrollDisabled(true)
                        .scrollClipDisabled()
                    }
                } else if session.isEmpty {
                    emptyQueue
                } else {
                    done
                }
            }
            if showsMenu { menu }
            toastView
        }
        .sheet(item: $sheet) { kind in sheetPanel(kind) }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        // outermost, after the frame: the keyboard (it opens in the sheet) must not squeeze this page
        .ignoresSafeArea(.keyboard)
        .toolbar(.hidden, for: .navigationBar)
        .hidesSmartButton()
        .navigationDestination(item: $editing) { draft in DraftEditView(draft: draft, store: store).detailPage() }
        .confirmDialog(isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
                       icon: "exclamationmark.triangle", title: L("Gagal menyimpan"),
                       message: errorMessage ?? "", confirmTitle: nil, cancelTitle: L("Tutup"))
        .onAppear {
            if session.isEmpty {
                session = store.drafts.map(\.id)
                original = Dictionary(uniqueKeysWithValues: store.drafts.map { ($0.id, $0.categoryId) })
            }
            if let id = store.editRequest, let draft = store.drafts.first(where: { $0.id == id }) {
                store.editRequest = nil
                selectedId = id
                editing = draft
            }
            nudgeOnce()
        }
        .onDisappear { flushCommits() }
        .task { await store.refreshReferenceData(userId: userId) }
    }

    // MARK: Top

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold)).foregroundStyle(Color.stGreen)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(L("Kembali"))
            Spacer()
            Text(L("Konfirmasi catatan")).font(.app(17, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            Spacer()
            Button { withAnimation(.settle(0.26)) { showsMenu.toggle() } } label: {
                Image(systemName: "ellipsis").font(.system(size: 20, weight: .bold)).foregroundStyle(Color.appText)
                    .frame(width: 44, height: 44)
                    .background(showsMenu ? Color.stChip : .clear, in: Circle())
            }
            .opacity(current == nil ? 0 : 1).disabled(current == nil)
            .accessibilityLabel(L("Lainnya"))
        }
        .padding(.horizontal, 14).frame(height: 44)
    }

    private var menu: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear.contentShape(Rectangle()).ignoresSafeArea()
                .onTapGesture { withAnimation(.settle(0.26)) { showsMenu = false } }
            Button { ignoreAll() } label: {
                Label(L("Hapus semua (%lld)", pending.count), systemImage: "trash")
                    .font(.app(15)).foregroundStyle(Color.stDangerText)
                    .padding(.horizontal, 12).frame(width: 188, height: 44, alignment: .leading)
            }
            .padding(6).frame(width: 200)
            .background(Color.stBar, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.14), radius: 16, y: 10)
            .padding(.trailing, 20).padding(.top, 48)
            .transition(.scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity))
        }
        .zIndex(20)
    }

    private func header(_ draft: Draft) -> some View {
        HStack {
            Label(L("Dicatat Smart Tracker · periksa dulu"), systemImage: "sparkles")
                .font(.app(13)).foregroundStyle(Color.appTextSecondary)
            Spacer()
            if let index = pending.firstIndex(where: { $0.id == draft.id }) {
                Text(L("%lld dari %lld", index + 1, pending.count)).font(.app(13)).monospacedDigit().foregroundStyle(Color.appTextSecondary)
            }
        }
        .padding(.horizontal, 24).padding(.top, 14)
    }

    // MARK: Deck

    private func deck(_ top: Draft) -> some View {
        let count = pending.count
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 26).fill(Color(light: 0xF2F2F4, dark: 0x242426))
                .padding(.horizontal, 24).offset(y: 20).opacity(count > 2 ? 1 : 0)
            RoundedRectangle(cornerRadius: 26).fill(Color(light: 0xEDEDF0, dark: 0x2C2C2E))
                .padding(.horizontal, 12).offset(y: 10).opacity(count > 1 ? 1 : 0)
            card(top)
                .modifier(CardPoseEffect(pose: pose))
                .gesture(count > 0 ? swipe(count: count) : nil)
        }
        .animation(.easeOut(duration: 0.3), value: count)
        .frame(height: 420).padding(.horizontal, 24).padding(.top, 22)
    }

    private func card(_ draft: Draft) -> some View {
        let wallet = store.accounts.first { $0.id == draft.accountId }
        let counter = store.accounts.first { $0.id == draft.counterpartyAccountId }
        let category = store.categories.first { $0.id == draft.categoryId }
        let isIncome = draft.kind == .income
        let plain = draft.kind == .expense || draft.kind == .income
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: category?.icon ?? draft.kindIcon).font(.system(size: 21)).foregroundStyle(Color.appText)
                    .frame(width: 44, height: 44).background(Color.stRaised, in: Circle())
                Spacer()
                Label(draft.sourceLabel, systemImage: draft.sourceIcon)
                    .font(.app(12)).foregroundStyle(Color.appTextSecondary)
                    .padding(.horizontal, 10).frame(height: 26).background(Color.stRaised, in: Capsule())
            }
            Button { plain ? open(.name, draft) : (editing = draft) } label: {
                HStack(spacing: 6) {
                    Text(draft.title.isEmpty ? draft.kindTitle : draft.title).font(.app(17, weight: .semibold)).lineLimit(1)
                    Image(systemName: "pencil").font(.system(size: 13)).foregroundStyle(Color.appTextTertiary)
                }
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(highlight(.name), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain).padding(.top, 14).padding(.leading, -6)
            Button { plain ? open(.amount, draft) : (editing = draft) } label: {
                Text(draft.amount.map { (draft.kind == .income ? "+" : (draft.kind == .expense ? "−" : "")) + (isBalanceVisible ? $0.formattedAsCurrency() : "Rp" + hiddenAmount) } ?? "—")
                    .font(.app(42, weight: .ultraLight)).tracking(-1.6).monospacedDigit()
                    .foregroundStyle(isIncome ? Color.stGreen : Color.appText)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .padding(.horizontal, 6)
                    .background(highlight(.amount), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain).padding(.top, 2).padding(.leading, -6)
            if draft.isUnreadable {
                Text(L("Tidak terbaca. Isi nominalnya dulu.")).font(.app(13)).foregroundStyle(Color.stWarn).padding(.top, 4)
            }
            if let note = draft.duplicateNote {
                Label(note, systemImage: "doc.on.doc").font(.app(12)).foregroundStyle(Color.stWarn).padding(.top, 6)
            }
            Spacer(minLength: 8)
            VStack(spacing: 0) {
                if plain {
                    detail(L("Tipe"), field: .type, draft) {
                        Label(draft.kindTitle, systemImage: draft.kindIcon).labelStyle(CompactLabelStyle())
                            .foregroundStyle(isIncome ? Color.stGreen : Color.appText)
                    }
                    detail(Lx("Kategori", en: "Category"), field: .category, draft) { Text(category?.name ?? L("Belum dipilih")).foregroundStyle(category == nil ? Color.stWarn : Color.appText) }
                    detail(Lx("Dompet", en: "Wallet"), field: .wallet, draft, warn: wallet == nil) {
                        if wallet == nil { Image(systemName: "exclamationmark.circle.fill").font(.system(size: 15)) }
                        Text(wallet?.name ?? L("Belum dipilih")).fontWeight(wallet == nil ? .semibold : .regular)
                            .foregroundStyle(wallet == nil ? Color.stWarn : Color.appText)
                    }
                } else {
                    detail(L("Jenis"), field: .type, draft) { Text(draft.kindTitle) }
                    detail(L("Dari"), field: .wallet, draft, warn: wallet == nil && draft.kind == .transfer) {
                        Text(wallet?.name ?? L("Belum dipilih")).foregroundStyle(wallet == nil && draft.kind == .transfer ? Color.stWarn : Color.appText)
                    }
                    detail(draft.kind == .cardPayment ? L("Kartu") : L("Ke"), field: .category, draft, warn: counter == nil) {
                        Text(counter?.name ?? L("Belum dipilih")).foregroundStyle(counter == nil ? Color.stWarn : Color.appText)
                    }
                }
                detail(L("Tanggal"), field: .date, draft, last: !(plain && showsRemember(draft))) { Text(Self.dateLabel(draft.date)) }
                if plain && showsRemember(draft) { rememberRow(draft, category: category) }
            }
            .background(Color.stRaised, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 26))
        .shadow(color: .black.opacity(isDragging ? 0.1 : 0), radius: 12, y: 8)
    }

    private var isDragging: Bool { if case .drag = pose { return true } else { return false } }

    private func highlight(_ field: Field) -> Color { flash == field ? Color.stSuccessBg : Color.stSuccessBg.opacity(0) }

    private func detail<V: View>(_ title: String, field: Field, _ draft: Draft, warn: Bool = false, last: Bool = false,
                                  @ViewBuilder value: () -> V) -> some View {
        Button { open(field, draft) } label: {
            HStack(spacing: 8) {
                Text(title).font(.app(15)).foregroundStyle(Color.appTextSecondary)
                Spacer()
                HStack(spacing: 5) { value() }
                    .font(.app(15)).foregroundStyle(warn ? Color.stWarn : Color.appText)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(highlight(field), in: RoundedRectangle(cornerRadius: 8))
                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(Color.appTextTertiary)
            }
            .padding(.horizontal, 14).frame(height: 46)
            .background(warn ? Color.stWarnBg : .clear)
            .overlay(alignment: .bottom) { if !last { Rectangle().fill(Color.appSeparator).frame(height: 1) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Changing the category offers to remember it for this word (it is on by default; the switch turns it off).
    private func showsRemember(_ draft: Draft) -> Bool {
        guard let id = draft.categoryId else { return false }
        return original[draft.id].map { $0 != id } ?? false
    }

    private func rememberRow(_ draft: Draft, category: Category?) -> some View {
        let on = remember[draft.id] ?? true
        return HStack(spacing: 10) {
            Image(systemName: "brain").font(.system(size: 17)).foregroundStyle(Color.stGreen)
            VStack(alignment: .leading, spacing: 1) {
                Text(L("Ingat pilihan ini")).font(.app(14, weight: .semibold))
                Text(L("Lain kali “%@” langsung jadi %@", draft.title, category?.name ?? "")).font(.app(12)).foregroundStyle(Color.appTextSecondary)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(get: { on }, set: { remember[draft.id] = $0 })).labelsHidden().tint(Color.stGreen)
        }
        .padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 56)
        .background(Color.stSuccessBg)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func dots(_ draft: Draft) -> some View {
        HStack(spacing: 5) {
            ForEach(pending) { d in
                Capsule().fill(d.id == draft.id ? Color.appText : Color.appSeparator)
                    .frame(width: d.id == draft.id ? 18 : 6, height: 6)
            }
        }
        .animation(.settle(0.3), value: draft.id)
        .animation(.settle(0.3), value: pending.count)
        .padding(.top, 34).frame(height: 40)
    }

    private func actions(_ draft: Draft) -> some View {
        let ok = draft.isComplete
        let walletMissing = (draft.kind == .expense || draft.kind == .income) && draft.amount != nil && draft.accountId == nil
        return GeometryReader { geo in
            let total = geo.size.width - 10
            HStack(spacing: 10) {
                Button { act(.ignored) } label: {
                    Label(L("Abaikan"), systemImage: "xmark").font(.app(16, weight: .semibold)).foregroundStyle(Color.appText)
                        .frame(maxWidth: .infinity).frame(height: 54).background(Color.stChip, in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
                .frame(width: total / 2.4)
                Button { act(.saved) } label: {
                    Label(ok ? L("Simpan") : (walletMissing ? L("Pilih dompet") : L("Lengkapi")),
                          systemImage: ok ? "checkmark" : (walletMissing ? "wallet.bifold" : "pencil"))
                        .font(.app(16, weight: .semibold)).foregroundStyle(ok ? Color.white : Color.stWarn)
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .background(ok ? Color.stGreen : Color.stWarnBg, in: Capsule())
                        .animation(.easeOut(duration: 0.25), value: ok)
                }
                .buttonStyle(PressScaleStyle())
                .frame(width: total / 2.4 * 1.4)
            }
        }
        .frame(height: 54)
        .padding(.horizontal, 24).padding(.top, 18)
    }

    private var bulk: some View {
        Button { open(all: true) } label: {
            Label(L("Simpan semua (%lld)", ready.count), systemImage: "checkmark.circle")
                .font(.app(15, weight: .semibold)).foregroundStyle(Color.stGreen).frame(height: 44)
        }
        .opacity(ready.isEmpty ? 0.4 : 1).disabled(ready.isEmpty)
        .padding(.bottom, 20)
    }

    // MARK: Empty and done

    private var done: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark").font(.system(size: 26, weight: .bold)).foregroundStyle(Color.stGreen)
                .frame(width: 56, height: 56).background(Color.stSuccessBg, in: Circle()).stEnter(0)
            Text(L("Semua sudah dicek")).font(.app(17, weight: .semibold)).padding(.top, 6).stEnter(1)
            Text(L("%lld disimpan · %lld diabaikan", savedCount, ignoredCount)).font(.app(15)).foregroundStyle(Color.appTextSecondary).stEnter(2)
            Button { dismiss() } label: {
                Text(L("Kembali ke Beranda")).font(.app(15, weight: .semibold)).foregroundStyle(Color.appText)
                    .padding(.horizontal, 20).frame(height: 44).background(Color.stChip, in: Capsule())
            }
            .padding(.top, 14).stEnter(3)
            Spacer()
        }
        .padding(.horizontal, 40).padding(.top, 130)
    }

    /// Konfirmasi catatan with nothing in it (design 3d): what lands here, and a way to start.
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

    // MARK: Toast

    @ViewBuilder private var toastView: some View {
        if let toast {
            HStack(spacing: 10) {
                Image(systemName: toast.icon).font(.system(size: 18)).foregroundStyle(Color(hex: "4CD497"))
                Text(toast.text).font(.app(14, weight: .medium)).lineLimit(1)
                Spacer(minLength: 8)
                Button { undo(toast) } label: {
                    Label(L("Urungkan"), systemImage: "arrow.counterclockwise").font(.app(14, weight: .semibold))
                        .foregroundStyle(Color(hex: "4CD497")).padding(.horizontal, 12).frame(height: 36)
                }
            }
            .foregroundStyle(.white)
            .padding(.leading, 16).padding(.trailing, 6).frame(minWidth: 270, minHeight: 48)
            .background(Color(hex: "1C1C1E"), in: Capsule())
            .overlay(alignment: .bottom) {
                GeometryReader { geo in
                    Capsule().fill(.white.opacity(0.25)).frame(width: geo.size.width * (toastShown ? 0 : 1), height: 2)
                        .animation(toastShown ? .linear(duration: 4.1) : nil, value: toastShown)
                }
                .frame(height: 2).padding(.horizontal, 24)
            }
            .shadow(color: .black.opacity(0.18), radius: 12, y: 8)
            .padding(.horizontal, 20).padding(.top, 8)
            .opacity(toastShown ? 1 : 0).offset(y: toastShown ? 0 : -14)
            .animation(.settle(0.36), value: toastShown)
            .zIndex(25)
        }
    }

    private func showToast(_ text: String, icon: String, ids: [UUID]) {
        let t = Toast(text: text, icon: icon, ids: ids)
        toast = t
        toastShown = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { toastShown = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) {
            if toast?.token == t.token { toastShown = false }
        }
    }

    // MARK: Sheets

    private func sheetPanel(_ kind: Sheet) -> some View {
        let draft = current
        return ConfirmSheetBody(title: sheetTitle(kind), onClose: { sheet = nil }) {
            switch kind {
            case .category: ConfirmCategoryList(categories: categoriesFor(draft), selectedId: draft?.categoryId,
                                                onPick: { c in pick(.category) { $0.categoryId = c.id; $0.fromMemory = false } }, onCreate: createCategory)
            case .type:
                VStack(spacing: 2) {
                    ConfirmPickRow(icon: "arrow.up.right", title: L("Pengeluaran"), subtitle: L("Uang keluar dari dompet"), isOn: draft?.kind == .expense) { setKind(.expense) }
                    ConfirmPickRow(icon: "arrow.down.left", iconBg: .stSuccessBg, iconFg: .stGreen, title: L("Pemasukan"),
                                   subtitle: L("Uang masuk ke dompet"), isOn: draft?.kind == .income) { setKind(.income) }
                }
            case .wallet:
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(WalletRules.spendingSources(store.accounts)) { w in
                            ConfirmPickRow(icon: Self.walletSymbol(w.type), title: w.name,
                                           subtitle: w.balance.formattedAsCurrency(), isOn: w.id == draft?.accountId) {
                                pick(.wallet) { $0.accountId = w.id }
                            }
                        }
                    }
                }.frame(maxHeight: 360)
            case .date:
                if let draft {
                    DayPicker(selected: draft.date, color: .stGreen) { day in
                        pick(.date) { $0.date = Self.keepingTime(of: $0.date, on: day) }
                    }
                    .padding(.horizontal, 6)
                }
            case .amount:
                ConfirmAmountPad(amount: amountText, isIncome: draft?.kind == .income,
                                 onPress: { key in if let next = NumberPad.apply(key, to: amountText) { withAnimation(.easeOut(duration: 0.14)) { amountText = next } } },
                                 onDone: { if amountText > 0 { pick(.amount, delay: 0.06) { $0.amount = Double(amountText) } } })
            case .name:
                NameField(initial: draft?.title ?? "") { name in
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    pick(.name, delay: 0.06) { if !trimmed.isEmpty { $0.title = trimmed } }
                }
            case .all:
                allSheet
            }
        }
    }

    private static func walletSymbol(_ type: Account.AccountType) -> String {
        switch type {
        case .cash: return "banknote"
        case .bank: return "building.columns"
        case .ewallet: return "iphone"
        case .credit: return "creditcard"
        case .investment: return "chart.line.uptrend.xyaxis"
        }
    }

    private func sheetTitle(_ kind: Sheet) -> String {
        switch kind {
        case .category: return "Pilih kategori"
        case .type: return "Tipe transaksi"
        case .wallet: return "Pilih dompet"
        case .date: return "Pilih tanggal"
        case .amount: return "Ubah nominal"
        case .name: return "Ubah nama"
        case .all: return "Simpan semua?"
        }
    }

    private var allSheet: some View {
        let outflow = ready.filter { $0.kind == .expense }.compactMap(\.amount).reduce(0, +)
        let inflow = ready.filter { $0.kind == .income }.compactMap(\.amount).reduce(0, +)
        let skipped = pending.filter { !$0.isComplete }
        return VStack(spacing: 0) {
            ForEach(ready) { d in
                HStack(spacing: 12) {
                    Image(systemName: store.categories.first { $0.id == d.categoryId }?.icon ?? d.kindIcon).font(.system(size: 16))
                        .frame(width: 34, height: 34).background(Color.stChip, in: Circle())
                    Text(d.title.isEmpty ? d.kindTitle : d.title).font(.app(15)).lineLimit(1)
                    Spacer()
                    Text((d.kind == .income ? "+" : (d.kind == .expense ? "−" : "")) + (d.amount ?? 0).formattedAsCurrency()).font(.app(15)).monospacedDigit()
                        .foregroundStyle(d.kind == .income ? Color.stGreen : Color.appText)
                }
                .frame(height: 52).padding(.horizontal, 6)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.appSeparator).frame(height: 1) }
            }
            VStack(spacing: 6) {
                if outflow > 0 { totalRow(L("Total pengeluaran"), "−" + outflow.formattedAsCurrency(), Color.appText) }
                if inflow > 0 { totalRow(L("Total pemasukan"), "+" + inflow.formattedAsCurrency(), Color.stGreen) }
            }
            .padding(.top, 14).padding(.horizontal, 6)
            if !skipped.isEmpty {
                Label(L("%@ dilewati karena belum lengkap. Tetap ada di sini untuk dicek.", skipped.map { $0.title.isEmpty ? $0.kindTitle : $0.title }.joined(separator: ", ")),
                      systemImage: "exclamationmark.circle.fill")
                    .font(.app(13)).foregroundStyle(Color.stWarn).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 10).background(Color.stWarnBg, in: RoundedRectangle(cornerRadius: 12)).padding(.top, 10)
            }
            VStack(spacing: 8) {
                Button { saveAll() } label: {
                    Text(L("Simpan %lld catatan", ready.count)).font(.app(16, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 52).background(Color.stGreen, in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
                Button { sheet = nil } label: {
                    Text(L("Batal")).font(.app(16, weight: .semibold)).foregroundStyle(Color.appText)
                        .frame(maxWidth: .infinity).frame(height: 52).background(Color.stChip, in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
            }
            .padding(.top, 16)
        }
    }

    private func totalRow(_ title: String, _ value: String, _ color: Color) -> some View {
        HStack { Text(title).foregroundStyle(Color.appTextSecondary); Spacer(); Text(value).fontWeight(.semibold).monospacedDigit().foregroundStyle(color) }
            .font(.app(15))
    }

    // MARK: Editing

    private func categoriesFor(_ draft: Draft?) -> [Category] {
        store.categories.filter { $0.type == (draft?.kind == .income ? .income : .expense) && !CategoryCatalog.isSystem($0) }
    }

    private func open(_ field: Field, _ draft: Draft) {
        guard draft.kind == .expense || draft.kind == .income else { editing = draft; return }
        switch field {
        case .name: sheet = .name
        case .amount: amountText = Int(draft.amount ?? 0); sheet = .amount
        case .type: sheet = .type
        case .category: sheet = .category
        case .wallet: sheet = .wallet
        case .date: sheet = .date
        }
    }

    private func open(all: Bool) { guard !ready.isEmpty else { return }; showsMenu = false; sheet = .all }

    /// Applies a change to the top card, closes the sheet a moment later and lights the changed field green for a second.
    private func pick(_ field: Field, delay: Double = 0.28, _ change: (inout Draft) -> Void) {
        guard var draft = current else { return }
        change(&draft)
        store.update(draft)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { sheet = nil; flash = field }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 1.0) { if flash == field { flash = nil } }
    }

    private static func keepingTime(of old: Date, on day: Date) -> Date {
        let cal = Calendar.current
        let t = cal.dateComponents([.hour, .minute], from: old)
        return cal.date(bySettingHour: t.hour ?? 12, minute: t.minute ?? 0, second: 0, of: day) ?? day
    }

    private func setKind(_ kind: Draft.Kind) {
        guard var draft = current, draft.kind != kind else { sheet = nil; return }
        draft.kind = kind
        draft.categoryId = nil
        store.update(draft)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { sheet = nil; flash = .type }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.28) { if flash == .type { flash = nil } }
    }

    private func createCategory(_ name: String) {
        guard !name.isEmpty, var draft = current else { return }
        let type: CategoryType = draft.kind == .income ? .income : .expense
        Task {
            do {
                let made = try await SupabaseRepository.shared.createCategory(name: name, type: type, icon: "tag", color: nil, userId: userId)
                await store.refreshReferenceData(userId: userId)
                draft.categoryId = made.id
                store.update(draft)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { sheet = nil; flash = .category }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.28) { if flash == .category { flash = nil } }
            } catch {
                sheet = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: Swipe

    private func swipe(count: Int) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard pose == .rest || isDragging else { return }
                pose = .drag(count < 2 ? value.translation.width * 0.3 : value.translation.width)
            }
            .onEnded { value in
                let dx = value.translation.width
                if count > 1, dx < -70 { go(1) } else if count > 1, dx > 70 { go(-1) } else { withAnimation(.settle(0.38)) { pose = .rest } }
            }
    }

    /// Flies the card out and brings the next (or previous) one in; the deck loops.
    private func go(_ step: Int) {
        let list = pending
        guard list.count > 1, let index = list.firstIndex(where: { $0.id == current?.id }) else { pose = .rest; return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.settle(0.24)) { pose = step > 0 ? .flyLeft : .flyRight }
        Task {
            try? await Task.sleep(for: .milliseconds(240))
            selectedId = list[(index + step + list.count) % list.count].id
            pose = step > 0 ? .enterRise : .enterLeft
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(.settle(0.38)) { pose = .rest }
        }
    }

    /// A small nudge of the top card after a moment, so people find out it can be swiped.
    private func nudgeOnce() {
        guard !hinted else { return }
        hinted = true
        Task {
            try? await Task.sleep(for: .milliseconds(1700))
            guard pending.count > 1, pose == .rest else { return }
            withAnimation(.timingCurve(0.3, 0.7, 0.3, 1, duration: 0.42)) { pose = .nudge }
            try? await Task.sleep(for: .milliseconds(460))
            if pose == .nudge { withAnimation(.settle(0.38)) { pose = .rest } }
        }
    }

    // MARK: Save, ignore, undo

    private func act(_ outcome: Outcome) {
        guard let draft = current, pose == .rest || isDragging || pose == .nudge else { return }
        if outcome == .saved, !draft.isComplete {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            if draft.kind == .expense || draft.kind == .income {
                if draft.amount == nil { open(.amount, draft) }
                else if draft.accountId == nil { open(.wallet, draft) }
                else { open(.category, draft) }
            } else { editing = draft }
            return
        }
        if outcome == .saved { UINotificationFeedbackGenerator().notificationOccurred(.success) } else { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        let title = draft.title.isEmpty ? draft.kindTitle : draft.title
        withAnimation(.settle(0.26)) { pose = outcome == .saved ? .exitSave : .exitIgnore }
        showToast(title + " " + (outcome == .saved ? L("disimpan") : L("diabaikan")), icon: outcome == .saved ? "checkmark.circle.fill" : "xmark.circle.fill", ids: [draft.id])
        Task {
            try? await Task.sleep(for: .milliseconds(260))
            resolve([draft], outcome)
            pose = .enterRise
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(.settle(0.38)) { pose = .rest }
        }
    }

    /// Marks drafts as dealt with now; the real save or delete follows when the Urungkan toast is gone.
    private func resolve(_ drafts: [Draft], _ outcome: Outcome) {
        let list = pending
        let first = drafts.first.flatMap { d in list.firstIndex { $0.id == d.id } } ?? 0
        let after = list.filter { l in !drafts.contains { $0.id == l.id } }
        withAnimation(.settle(0.4)) {
            for d in drafts { outcomes[d.id] = outcome }
            selectedId = after.isEmpty ? nil : after[min(first, after.count - 1)].id
        }
        for d in drafts {
            commits[d.id]?.cancel()
            commits[d.id] = Task {
                try? await Task.sleep(for: .seconds(4.3))
                guard !Task.isCancelled else { return }
                await commit(d, outcome)
            }
        }
    }

    private func commit(_ draft: Draft, _ outcome: Outcome) async {
        guard !committed.contains(draft.id) else { return }
        committed.insert(draft.id)
        if outcome == .ignored { store.discard(draft.id); return }
        do { try await store.save(store.drafts.first { $0.id == draft.id } ?? draft, userId: userId, remember: remember[draft.id] ?? true) }
        catch {
            committed.remove(draft.id)
            withAnimation(.settle(0.4)) { outcomes[draft.id] = nil; selectedId = draft.id }
            errorMessage = error.localizedDescription
        }
    }

    private func flushCommits() {
        for (id, outcome) in outcomes where !committed.contains(id) {
            commits[id]?.cancel()
            guard let draft = store.drafts.first(where: { $0.id == id }) else { continue }
            Task { await commit(draft, outcome) }
        }
    }

    private func undo(_ toast: Toast) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        for id in toast.ids { commits[id]?.cancel(); commits[id] = nil }
        withAnimation(.settle(0.4)) {
            for id in toast.ids { outcomes[id] = nil }
            selectedId = toast.ids.first
            pose = .enterRise
        }
        toastShown = false
        Task {
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(.settle(0.38)) { pose = .rest }
            try? await Task.sleep(for: .milliseconds(300))
            self.toast = nil
        }
    }

    private func saveAll() {
        let drafts = ready
        guard !drafts.isEmpty else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        sheet = nil
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            resolve(drafts, .saved)
            showToast(L("%lld catatan disimpan", drafts.count), icon: "checkmark.circle.fill", ids: drafts.map(\.id))
        }
    }

    private func ignoreAll() {
        let drafts = pending
        guard !drafts.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.settle(0.26)) { showsMenu = false }
        resolve(drafts, .ignored)
        showToast(L("%lld draf dihapus", drafts.count), icon: "trash.fill", ids: drafts.map(\.id))
    }

    static func dateLabel(_ date: Date) -> String {
        let cal = Calendar.current
        let day = DateFormatter.shortDay.string(from: date)
        if cal.isDateInToday(date) { return L("Hari ini") + ", " + day }
        if cal.isDateInYesterday(date) { return L("Kemarin") + ", " + day }
        return day
    }
}

/// Where the top card is, for its animation (design 4a: drag, fly out, enter, exit by Simpan or Abaikan, nudge).
enum CardPose: Equatable { case rest, drag(CGFloat), flyLeft, flyRight, enterRise, enterLeft, exitSave, exitIgnore, nudge }

/// The deck's top card pose as one modifier, so every movement of the design is one animated value.
private struct CardPoseEffect: ViewModifier {
    let pose: CardPose

    private var tx: CGFloat {
        switch pose {
        case .drag(let dx): return dx
        case .flyLeft, .enterLeft: return -440
        case .flyRight: return 440
        case .exitSave: return 90
        case .exitIgnore: return -90
        case .nudge: return -40
        case .rest, .enterRise: return 0
        }
    }
    private var rotation: Double {
        switch pose {
        case .drag(let dx): return Double(dx) / 22
        case .flyLeft, .enterLeft: return -12
        case .flyRight: return 12
        case .exitSave: return 6
        case .exitIgnore: return -6
        case .nudge: return -2
        case .rest, .enterRise: return 0
        }
    }
    private var rises: Bool { pose == .enterRise }
    private var opacity: Double {
        switch pose { case .exitSave, .exitIgnore, .enterRise: return 0; default: return 1 }
    }

    func body(content: Content) -> some View {
        content
            .offset(x: tx, y: rises ? 24 : 0)
            .rotationEffect(.degrees(rotation))
            .scaleEffect(rises ? 0.94 : 1)
            .opacity(opacity)
            .transaction { if case .drag = pose { $0.animation = nil } else if pose == .enterRise || pose == .enterLeft { $0.animation = nil } }
    }
}

/// A one-line text field for renaming a draft, with Selesai.
private struct NameField: View {
    let initial: String
    let onDone: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 14) {
            TextField(L("Nama catatan"), text: $text).font(.app(17)).focused($focused)
                .padding(.horizontal, 14).frame(height: 52).background(Color.stChip, in: RoundedRectangle(cornerRadius: 14))
                .submitLabel(.done).onSubmit { onDone(text) }
            Button { onDone(text) } label: {
                Text(L("Selesai")).font(.app(16, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 52).background(Color.stGreen, in: Capsule())
            }
            .buttonStyle(PressScaleStyle())
        }
        .padding(.horizontal, 6)
        .onAppear { text = initial; focused = true }
    }
}

/// An icon next to a text, close together (the Tipe chip).
private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) { configuration.icon.font(.system(size: 13, weight: .bold)); configuration.title }
    }
}

extension DateFormatter {
    /// "12 Okt" / "12 Oct", in the app's language at the moment it is asked for (it can change while the app runs).
    static var shortDay: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        f.locale = AppLanguage.locale
        return f
    }
}
