import SwiftUI

/// The result of one sentence (design "Catat Cepat", layout D): a panel in the colour of the transaction type
/// with the amount and name, rows for the wallet, category and date, and Simpan right here or "Simpan nanti" to
/// Konfirmasi transaksi. Several transactions in one sentence show as a list; an unreadable sentence offers "Isi manual".
struct QuickResultSheet: View {
    let sentence: String
    let source: Draft.Source
    let userId: String
    var onSaved: (String) -> Void
    /// Drafts to park in Konfirmasi transaksi; the toast is shown through `onSaved`.
    var onSaveLater: ([Draft]) -> Void
    /// "Ulang": the sentence goes back into the bar.
    var onRedo: (String) -> Void

    @ObservedObject private var store = DraftStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [Draft]
    @State private var isUnclear: Bool
    /// Opens full height, or half for an unreadable sentence; the user can drag between the two.
    @State private var detent: PresentationDetent
    private let isMulti: Bool
    @State private var saving = false
@State private var periodChoice: Draft?
    @State private var failure: DraftQueueView.Failure?
    /// Fields the user changed ("Diganti"), as "<draft id>-<field>".
    @State private var changed: Set<String> = []
    @State private var picker: FieldPicker?
    @State private var openId: UUID?
    @State private var contentHeight: CGFloat = 420

    struct FieldPicker: Identifiable {
        let draftId: UUID
        let kind: DraftFieldSheet.Kind
        var id: String { "\(draftId)-\(kind)" }
    }

    init(sentence: String, source: Draft.Source, drafts: [Draft], userId: String,
         onSaved: @escaping (String) -> Void, onSaveLater: @escaping ([Draft]) -> Void, onRedo: @escaping (String) -> Void) {
        self.sentence = sentence
        self.source = source
        self.userId = userId
        self.onSaved = onSaved
        self.onSaveLater = onSaveLater
        self.onRedo = onRedo
        _drafts = State(initialValue: drafts)
        let unclear = drafts.count == 1 && (drafts[0].isUnreadable || drafts[0].amount == nil)
        _isUnclear = State(initialValue: unclear)
        _detent = State(initialValue: unclear ? .medium : .large)
        isMulti = drafts.count > 1
    }

    private var ready: [Draft] { drafts.filter { $0.isComplete && !store.needsPeriodChoice($0) } }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isUnclear {
                unclearBody
            } else if isMulti {
                multiBody
            } else if let draft = drafts.first {
                singleBody(draft)
            }
        }
        .padding(.top, 22)
        .filterSheet {
            if isUnclear {
                HStack(spacing: 12) {
                    Button { dismiss(); onRedo(sentence) } label: {
                        Image(systemName: "arrow.counterclockwise").font(.system(size: 20)).foregroundStyle(Color.appText)
                            .frame(width: 50, height: 50).background(Color.appFill, in: Circle())
                    }
                    .accessibilityLabel(L("Ulang"))
                    SmartSheetFooter(primary: L("Isi nominal"), secondary: nil, onPrimary: { fillManually() })
                }
                .buttonStyle(PressScaleStyle())
            } else { footer }
        }
        .presentationDetents([.medium, .large], selection: $detent)

        .sheet(item: $periodChoice) { d in
    EarlySalarySheet(date: d.date) { choice in
        guard let i = drafts.firstIndex(where: { $0.id == d.id }) else { return }
        drafts[i].startsPeriod = choice
        if drafts.count == 1 { saveSingle() } else { saveCard(drafts[i]) }
    }
}
.sheet(item: $picker) { item in
            if let d = drafts.first(where: { $0.id == item.draftId }) {
                DraftFieldSheet(draft: d, kind: item.kind, accounts: store.accounts, categories: store.categories,
                                edit: { change in edit(d.id, change, field: item.kind) },
                                learn: { if let updated = drafts.first(where: { $0.id == d.id }) { store.learnCorrection(from: updated) } },
                                close: { picker = nil })
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: source == .voice ? "mic" : source == .photo ? "photo" : "keyboard").font(.system(size: 14))
            Text(source == .voice ? L("Dari suaramu") : source == .photo ? L("Dari gambarmu") : L("Dari ketikanmu")).layoutPriority(1)
            if !isUnclear && !sentence.isEmpty {
                Text("· “\(sentence)”").foregroundStyle(Color.appTextTertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .font(.app(13)).foregroundStyle(Color.appTextSecondary)
        .padding(.horizontal, 24)
    }

    // MARK: One transaction

    private func singleBody(_ d: Draft) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            panel(d)
            VStack(spacing: 0) {
                ForEach(fields(d, includeType: false), id: \.key) { field in fieldRow(d, field) }
            }
            if let note = store.duplicateNote(for: d) {
                Label {
                    Text(L("Mirip transaksi lain.")).fontWeight(.semibold).foregroundStyle(Color.stWarn)
                        + Text(" " + note).foregroundStyle(Color.appTextSecondary)
                } icon: { Image(systemName: "doc.on.doc").foregroundStyle(Color.stWarn) }
                    .font(.app(13))
            }
            if let note = d.note {
                Label(note, systemImage: "eye").font(.app(13)).foregroundStyle(Color.stWarn)
            }
            if let failure { failureBox(failure) }
            if !d.isComplete {
                Label(incompleteText(d), systemImage: "exclamationmark.circle.fill")
                    .font(.app(13)).foregroundStyle(Color.stWarn)
            }
        }
        .padding(.horizontal, 24).padding(.top, 14)
    }

    private func panel(_ d: Draft) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { picker = FieldPicker(draftId: d.id, kind: .type) } label: {
                HStack(spacing: 6) {
                    Text(d.kindTitle)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                }
                .font(.app(13, weight: .semibold))
                .padding(.horizontal, 12).frame(height: 30)
                .background(Color.white.opacity(0.18), in: Capsule())
            }
            .buttonStyle(PressScaleStyle())
            Button { picker = FieldPicker(draftId: d.id, kind: .amount) } label: {
                HStack(alignment: .top, spacing: 3) {
                    Text("Rp").font(.app(17)).opacity(0.75).padding(.top, 9)
                    Text((d.amount ?? 0).formattedAsDigits())
                        .font(.app(52, weight: .ultraLight)).tracking(-1.5).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Spacer(minLength: 0)
                }
                .padding(.top, 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Nominal"))
            TextField("", text: titleBinding(d), prompt: Text("Nama transaksi").foregroundStyle(Color.white.opacity(0.6)))
                .font(.app(17, weight: .medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(d.kindColor, in: RoundedRectangle(cornerRadius: 20))
        .animation(.easeInOut(duration: 0.4), value: d.kind)
    }

    // MARK: Fields

    private enum Origin { case sentence, changed }

    private struct Field {
        let key: String
        let label: String
        let value: String?
        let icon: String
        let kind: DraftFieldSheet.Kind
        let origin: Origin?
    }

    private func fields(_ d: Draft, includeType: Bool) -> [Field] {
        let wallet = store.accounts.first { $0.id == d.accountId }
        let target = store.accounts.first { $0.id == d.counterpartyAccountId }
        let category = store.categories.first { $0.id == d.categoryId }
        func origin(_ key: String, present: Bool) -> Origin? {
            if changed.contains("\(d.id)-\(key)") { return .changed }
            return key != "date" && present && !d.fromMemory && !isManual(d) ? .sentence : nil
        }
        var result: [Field] = []
        if includeType { result.append(Field(key: "type", label: L("Tipe"), value: d.kindTitle, icon: d.kindIcon, kind: .type, origin: nil)) }
        if d.kind != .transfer {
            result.append(Field(key: "category", label: L("Kategori"), value: category?.name, icon: category?.icon ?? "tag",
                                kind: .category, origin: nil))
        }
        result.append(Field(key: "wallet", label: d.kind == .transfer ? L("Dari dompet") : L("Dompet"), value: wallet?.name, icon: "wallet.bifold",
                            kind: .wallet, origin: origin("wallet", present: wallet != nil)))
        if d.kind == .transfer {
            result.append(Field(key: "target", label: L("Ke dompet"), value: target?.name, icon: "arrow.right", kind: .target,
                                origin: origin("target", present: target != nil)))
        }
        result.append(Field(key: "date", label: L("Tanggal"), value: Self.dateLabel(d.date), icon: "calendar", kind: .date,
                            origin: origin("date", present: true)))
        return result
    }

    /// A draft filled in by hand ("Isi manual") has nothing read from the sentence.
    private func isManual(_ d: Draft) -> Bool { manualIds.contains(d.id) }
    @State private var manualIds: Set<UUID> = []

    private func fieldRow(_ d: Draft, _ f: Field) -> some View {
        let missing = f.value == nil
        return Button { picker = FieldPicker(draftId: d.id, kind: f.kind) } label: {
            HStack(spacing: 14) {
                Image(systemName: missing ? "plus.circle" : f.icon).font(.system(size: 18))
                    .foregroundStyle(missing ? Color.stWarn : Color.appTextSecondary).frame(width: 24)
                Text(f.label).font(.app(16)).foregroundStyle(missing ? Color.stWarn : Color.appTextSecondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(f.value ?? L("Pilih")).font(.app(16)).foregroundStyle(missing ? Color.stWarn : Color.appText)
                    if let origin = f.origin {
                        Label(origin == .changed ? L("Diganti") : L("Dari kalimatmu"),
                              systemImage: origin == .changed ? "pencil" : "sparkle")
                            .font(.app(11, weight: .medium))
                            .foregroundStyle(origin == .changed ? Color.stGreen : Color.appTextTertiary)
                    }
                }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.appTextTertiary)
            }
            .frame(minHeight: 52).padding(.vertical, 6)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.appSeparator).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func incompleteText(_ d: Draft) -> String {
        if d.needsInvestmentWallet && d.counterpartyAccountId == nil {
            return L("Belum ada dompet Investasi. Tambah dulu di Dompet, lalu lengkapi di Konfirmasi transaksi.")
        }
        let names = d.missing.map { m -> String in
            switch m {
            case .amount: L("nominal")
            case .account: d.kind == .transfer ? L("dompet asal") : L("dompet")
            case .counterparty: L("dompet tujuan")
            case .category: L("kategori")
            }
        }
        let head = names.count == 1 ? L("%@ belum terisi", names[0].prefix(1).uppercased() + names[0].dropFirst())
                                    : L("Belum terisi: %@", names.joined(separator: ", "))
        return head + ". " + L("Pilih sekarang, atau lengkapi nanti di Konfirmasi transaksi.")
    }

    // MARK: Several transactions

    private var multiBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(source == .photo ? L("%lld transaksi", drafts.count) : L("%lld transaksi dari kalimatmu", drafts.count))
                    .font(.app(20, weight: .semibold))
                if drafts.count > ready.count {
                    Text(L("%lld perlu dicek · ketuk untuk melengkapi", drafts.count - ready.count))
                        .font(.app(13)).foregroundStyle(Color.appTextSecondary)
                }
            }
            .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 10)
            // the sheet itself scrolls, so the list takes its full height
            VStack(spacing: 8) {
                ForEach(drafts) { d in card(d).transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .offset(x: -24)))) }
            }
            .padding(.horizontal, 16).padding(.bottom, 8)
            .animation(.settle(0.35), value: drafts.map(\.id))
            if let failure { failureBox(failure).padding(.horizontal, 24).padding(.top, 6) }
        }
    }

    private func card(_ d: Draft) -> some View {
        let missing = d.missing
        let isOpen = openId == d.id
        let category = store.categories.first { $0.id == d.categoryId }
        let wallet = store.accounts.first { $0.id == d.accountId }
        let summary = !missing.isEmpty ? L("Kurang %@", missingNames(d).joined(separator: ", "))
            : [category?.name ?? d.kindTitle, wallet?.name].compactMap { $0 }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: category?.icon ?? d.kindIcon).font(.system(size: 19)).foregroundStyle(Color.appTextSecondary).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.title.isEmpty ? d.kindTitle : d.title).font(.app(16, weight: .medium)).lineLimit(1)
                    Label(summary, systemImage: missing.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.app(13)).foregroundStyle(missing.isEmpty ? Color.stGreen : Color.stWarn).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(amountText(d)).font(.app(17)).monospacedDigit().foregroundStyle(d.kind == .income ? Color.stGreen : Color.appText)
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.appTextTertiary)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            }
            if let note = d.note, !isOpen {
                Label(note, systemImage: "eye").font(.app(13)).foregroundStyle(Color.stWarn).lineLimit(1).padding(.leading, 38)
            }
            if isOpen {
                // the amount big above the tiles (design 6, expanded row)
                HStack(alignment: .top, spacing: 6) {
                    Text("Rp").font(.app(15)).foregroundStyle(Color.appTextTertiary).padding(.top, 8)
                    Text(d.amount.map { $0.formattedAsDigits() } ?? "0")
                        .font(.app(44, weight: .light)).tracking(-1.2).monospacedDigit()
                        .foregroundStyle(d.amount == nil ? Color.appTextTertiary : Color.appText)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Spacer(minLength: 0)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(fields(d, includeType: true), id: \.key) { f in tile(d, label: f.label, value: f.value, icon: f.icon, kind: f.kind) }
                }
                .transition(.opacity.combined(with: .offset(y: 8)))
            }
            if isOpen {
                if let note = d.note {
                    Label(note, systemImage: "eye").font(.app(14)).foregroundStyle(Color.stWarn)
                }
                HStack(spacing: 10) {
                    Button { ignore(d) } label: {
                        Text("Abaikan").font(.app(15, weight: .medium)).foregroundStyle(Color.appText)
                            .padding(.horizontal, 20).frame(height: 44)
                            .overlay(Capsule().strokeBorder(Color(light: 0xD2D2D7, dark: 0x48484A), lineWidth: 1))
                    }
                    Button { saveCard(d) } label: {
                        Text(d.isComplete ? L("Simpan") : L("Lengkapi dulu")).font(.app(15, weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(d.isComplete ? Color.stGreen : Color.appTextTertiary, in: Capsule())
                    }
                    .disabled(!d.isComplete || saving)
                }
            }
        }
        .padding(.horizontal, isOpen ? 16 : 8).padding(.vertical, isOpen ? 16 : 10)
        .background(isOpen ? Color.appFill : Color.clear, in: RoundedRectangle(cornerRadius: 20))
        .contentShape(Rectangle())
        .onTapGesture { if !isOpen { withAnimation(.settle(0.3)) { openId = d.id } } }
    }

    private func tile(_ d: Draft, label: String, value: String?, icon: String, kind: DraftFieldSheet.Kind) -> some View {
        let missing = value == nil
        return Button { picker = FieldPicker(draftId: d.id, kind: kind) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.app(12)).foregroundStyle(missing ? Color.stWarn : Color.appTextSecondary)
                HStack(spacing: 6) {
                    Image(systemName: missing ? "plus.circle" : icon).font(.system(size: 14))
                    Text(value ?? L("Pilih")).font(.app(15, weight: .medium)).lineLimit(1)
                }
                .foregroundStyle(missing ? Color.stWarn : Color.appText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(missing ? Color.clear : Color.appBackground, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                if missing { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.stWarn, style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
            }
        }
        .buttonStyle(PressScaleStyle())
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

    private func amountText(_ d: Draft) -> String {
        guard let amount = d.amount else { return L("Isi nominal") }
        return (d.kind == .expense ? "−" : d.kind == .income ? "+" : "") + "Rp" + amount.formattedAsDigits()
    }

    // MARK: Unclear sentence

    private var unclearBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("“\(sentence)”").font(.app(26, weight: .light)).tracking(-0.4).lineSpacing(3)
                Text("Nominalnya tidak terbaca").font(.app(17, weight: .semibold))
                Text("Tulis nama dan jumlahnya dalam satu kalimat, mis. “sabun 18rb”.")
                    .font(.app(15)).lineSpacing(2).foregroundStyle(Color.appTextSecondary)
            }
        }
        .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 12)
    }

    // MARK: Footer

    private var footer: some View {
        let single = !isMulti
        let complete = single ? (drafts.first?.isComplete ?? false) : true
        let rest = drafts.count - ready.count
        let title: String
        var enabled = !saving
        let action: () -> Void
        if isMulti {
            enabled = !ready.isEmpty && !saving
            title = saving ? L("Menyimpan…") : ready.isEmpty ? L("Belum ada yang lengkap") : rest > 0 ? L("Simpan %lld, lengkapi %lld nanti", ready.count, rest) : L("Simpan %lld yang lengkap", ready.count)
            action = saveReady
        } else if !complete {
            title = L("Simpan draf")
            action = saveLater
        } else {
            title = saving ? L("Menyimpan…") : failure != nil ? L("Coba lagi") : L("Simpan")
            action = saveSingle
        }
        return VStack(spacing: 6) {
            HStack(spacing: 10) {
                Button { dismiss(); onRedo(sentence) } label: {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 20)).foregroundStyle(Color.appText)
                        .frame(width: 50, height: 50).background(Color.appFill, in: Circle())
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel(L("Ulang"))
                SmartSheetFooter(primary: title, ink: !isMulti && !complete, isBusy: saving, isEnabled: enabled, secondary: nil, onPrimary: action)
            }
            if isMulti && rest > 0 {
                Text(L("%lld yang belum lengkap masuk ke Konfirmasi transaksi", rest))
                    .font(.app(13)).foregroundStyle(Color.appTextSecondary).padding(.top, 4)
            }
            if isMulti || complete {
                Button(action: saveLater) {
                    Label(L("Simpan draf"), systemImage: "tray.and.arrow.down").font(.app(16, weight: .medium)).foregroundStyle(Color.appText)
                        .padding(.horizontal, 16).frame(height: 44)
                }
                .disabled(saving)
            }
        }
    }

    private func failureBox(_ failure: DraftQueueView.Failure) -> some View {
        Label {
            Text(failure.isOffline ? L("Gagal menyimpan.") : L("Gagal menyimpan:")).fontWeight(.semibold).foregroundStyle(Color.stDangerText)
                + Text(" " + (failure.isOffline ? L("Koneksi terputus. Coba lagi, atau simpan nanti di Konfirmasi transaksi.") : failure.message))
                .foregroundStyle(Color.appTextSecondary)
        } icon: { Image(systemName: failure.isOffline ? "wifi.slash" : "exclamationmark.triangle").foregroundStyle(Color.stDangerText) }
            .font(.app(13))
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.stDangerBg, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Editing

    private func edit(_ id: UUID, _ change: (inout Draft) -> Void, field: DraftFieldSheet.Kind) {
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        change(&drafts[index])
        failure = nil
        switch field {
        case .wallet: changed.insert("\(id)-wallet")
        case .target: changed.insert("\(id)-target")
        case .date: changed.insert("\(id)-date")
        default: break
        }
    }

    private func titleBinding(_ d: Draft) -> Binding<String> {
        Binding(get: { d.title },
                set: { value in if let index = drafts.firstIndex(where: { $0.id == d.id }) { drafts[index].title = value; failure = nil } })
    }

    /// "Isi manual": the same sheet becomes an empty form.
    private func fillManually() {
        var blank = Draft()
        blank.source = source
        manualIds.insert(blank.id)
        withAnimation(.settle(0.4)) {
            drafts = [blank]
            isUnclear = false
            detent = .large
        }
    }

    private func ignore(_ d: Draft) {
        withAnimation(.settle(0.35)) { drafts.removeAll { $0.id == d.id } }
        if drafts.isEmpty {
            dismiss()
            onSaved(L("Semua diabaikan"))
        }
    }

    // MARK: Saving

    /// What the notice calls the saved row; the transaction itself keeps an empty name empty.
    private func displayName(_ d: Draft) -> String {
        if let title = d.savedTitle { return title }
        return store.categories.first { $0.id == d.categoryId }?.name ?? d.kindTitle
    }

    private func saveSingle() {
        guard let d = drafts.first, d.isComplete, !saving else { return }
        if store.needsPeriodChoice(d) { periodChoice = d; return }
        saving = true
        failure = nil
        Task {
            do {
                try await store.saveImmediately(d, userId: userId)
                saving = false
                dismiss()
                onSaved("\(displayName(d)) \(amountText(d)) " + L("tersimpan"))
            } catch {
                saving = false
                failure = DraftQueueView.Failure(error)
            }
        }
    }

    /// Saves a single row straight from an expanded card ("Simpan" in design 6).
    private func saveCard(_ d: Draft) {
        guard d.isComplete, !saving else { return }
        if store.needsPeriodChoice(d) { periodChoice = d; return }
        saving = true
        failure = nil
        Task {
            do {
                try await store.saveImmediately(d, userId: userId)
                saving = false
                let title = displayName(d)
                withAnimation(.settle(0.3)) {
                    if openId == d.id { openId = nil }
                    drafts.removeAll { $0.id == d.id }
                }
                if drafts.isEmpty {
                    dismiss()
                    onSaved("\(title) \(amountText(d)) " + L("tersimpan"))
                }
            } catch {
                saving = false
                failure = DraftQueueView.Failure(error)
            }
        }
    }

    /// Saves the complete ones; the rest go to Konfirmasi transaksi.
    private func saveReady() {
        let items = ready
        guard !items.isEmpty, !saving else { return }
        saving = true
        failure = nil
        Task {
            var saved = 0
            for d in items {
                do {
                    try await store.saveImmediately(d, userId: userId)
                    saved += 1
                    withAnimation(.settle(0.3)) { drafts.removeAll { $0.id == d.id } }
                } catch {
                    failure = DraftQueueView.Failure(error)
                    break
                }
            }
            saving = false
            guard failure == nil else { return }
            let rest = drafts
            if !rest.isEmpty { onSaveLater(rest) }
            dismiss()
            onSaved(L("%lld transaksi tersimpan", saved) + (rest.isEmpty ? "" : " · " + L("%lld ke Konfirmasi", rest.count)))
        }
    }

    private func saveLater() {
        guard !saving else { return }
        onSaveLater(drafts)
        dismiss()
        onSaved(L("Masuk ke Konfirmasi transaksi"))
    }

    private static func dateLabel(_ date: Date) -> String {
        let cal = Calendar.current
        let day = DateFormatter.shortDay.string(from: date)
        if cal.isDateInToday(date) { return L("Hari ini") + ", " + day }
        if cal.isDateInYesterday(date) { return L("Kemarin") + ", " + day }
        return day
    }
}
