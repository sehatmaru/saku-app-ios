import SwiftUI

/// Ubah draf: the same form as Tambah transaksi (swipeable type panel, rows, wallet / category / date sheets,
/// keypad), but it edits the draft; Simpan keeps the changes on it and the transaction is saved from Perlu dicek.
/// A bill paid on a credit card is shown under Transfer, with the card as the destination.
struct DraftEditView: View {
    @State var draft: Draft
    @ObservedObject var store: DraftStore
    @Environment(\.dismiss) private var dismiss

    @State private var typeIndex: Int
    @State private var dragX: CGFloat = 0
    @State private var amount: Int
    @State private var isBumped = false
    @State private var sheet: PickerKind?
    @State private var showsDelete = false
    @FocusState private var noteFocused: Bool
    @State private var isCompact = false

    enum PickerKind: String, Identifiable {
        case category, account, target, date
        var id: String { rawValue }
    }

    private static let types = TransactionStyle.entryTypes

    init(draft: Draft, store: DraftStore) {
        _draft = State(initialValue: draft)
        self.store = store
        _amount = State(initialValue: Int(draft.amount ?? 0))
        let type: Transaction.TransactionType = draft.kind == .income ? .income : (draft.kind == .expense ? .expense : .transfer)
        _typeIndex = State(initialValue: Self.types.firstIndex { $0.type == type } ?? 0)
    }

    private var style: TransactionStyle { Self.types[typeIndex] }
    /// The panel colour, with the dark-mode values of the design.
    private var panelColor: Color {
        switch style.type {
        case .expense: return .stExpense
        case .income: return .stGreen
        default: return .stTransfer
        }
    }
    private var isTransfer: Bool { style.type == .transfer }
    private var isCard: Bool { draft.kind == .cardPayment }
    private var activeAccounts: [Account] { store.accounts.filter(\.isActive).sorted { $0.isDefault && !$1.isDefault } }
    private var account: Account? { store.accounts.first { $0.id == draft.accountId } }
    private var target: Account? { store.accounts.first { $0.id == draft.counterpartyAccountId } }
    private var category: Category? { store.categories.first { $0.id == draft.categoryId } }
    private var typeCategories: [Category] {
        store.categories.filter { $0.type == (style.type == .income ? .income : .expense) && !CategoryCatalog.isSystem($0) }
    }
    private var rowHeight: CGFloat { isCompact ? 46 : 48 }
    private var calendar: Calendar { .current }

    var body: some View {
        VStack(spacing: 0) {
            panel
            rows.padding(.top, isCompact ? 4 : 10)
            Spacer(minLength: isCompact ? 4 : 12)
            if !noteFocused {
                AmountPad(color: panelColor, isEnabled: amount > 0, onPress: press, onSave: save, keyHeight: isCompact ? 46 : 52,
                          title: amount > 0 ? "Simpan" : "Isi jumlah")
                    .animation(.easeInOut(duration: 0.4), value: typeIndex)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
        }
        .onGeometryChange(for: Bool.self, of: { $0.size.height < 720 }) { isCompact = $0 }
        .background(Color.appBackground)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $sheet) { pickerSheet($0) }
        .confirmDialog(isPresented: $showsDelete, icon: "trash", destructive: true, title: L("Hapus draf ini?"),
                       message: L("Draf hilang dan tidak ada yang tercatat sebagai transaksi."), confirmTitle: L("Hapus")) {
            store.discard(draft.id)
            dismiss()
        }
    }

    // MARK: Panel

    private var panel: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack {
                    Button(L("Batal")) { dismiss() }.font(.app(17))
                    Spacer()
                    Button { showsDelete = true } label: {
                        Image(systemName: "trash").font(.system(size: 16)).frame(width: 34, height: 34)
                            .background(.white.opacity(0.16), in: Circle())
                    }
                    .accessibilityLabel(L("Hapus draf"))
                }
                typeDots
            }
            .frame(height: isCompact ? 40 : 44)
            .padding(.horizontal, 20)

            VStack(spacing: 0) {
                typeCarousel.padding(.top, 4)
                amountText.padding(.top, isCompact ? 4 : 12)
                Label(draft.sourceLabel, systemImage: draft.sourceIcon)
                    .font(.app(13, weight: .medium))
                    .padding(.leading, 10).padding(.trailing, 14).frame(height: 32)
                    .background(.white.opacity(0.16), in: Capsule())
                    .padding(.top, isCompact ? 8 : 16)
            }
        }
        .padding(.bottom, isCompact ? 12 : 18)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: 32, bottomTrailingRadius: 32)
                .fill(panelColor)
                .animation(.easeInOut(duration: 0.45), value: typeIndex)
                .ignoresSafeArea(edges: .top)
        }
        .contentShape(Rectangle())
        .gesture(typeSwipe)
    }

    private var typeCarousel: some View {
        GeometryReader { geo in
            let itemWidth: CGFloat = 180
            HStack(spacing: 0) {
                ForEach(Self.types.indices, id: \.self) { i in
                    let isCurrent = i == typeIndex
                    HStack(spacing: 8) {
                        Image(systemName: Self.types[i].icon).font(.system(size: 17, weight: .bold))
                        Text(isCard && i == 2 ? L("Bayar kartu") : Self.types[i].label)
                    }
                    .font(.app(22, weight: .bold))
                    .frame(width: itemWidth, height: 44)
                    .opacity(isCurrent ? 1 : 0.45)
                    .scaleEffect(isCurrent ? 1 : 0.8)
                    .animation(.settle(0.38), value: typeIndex)
                    .contentShape(Rectangle())
                    .onTapGesture { setType(i) }
                    .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
                }
            }
            .offset(x: (geo.size.width - itemWidth) / 2 - CGFloat(typeIndex) * itemWidth + dragX)
        }
        .frame(height: isCompact ? 38 : 44)
        .clipped()
    }

    /// Swiping anywhere on the coloured panel switches type, as in Tambah transaksi.
    private var typeSwipe: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                var dx = value.translation.width
                if (typeIndex == 0 && dx > 0) || (typeIndex == Self.types.count - 1 && dx < 0) { dx *= 0.3 }
                dragX = dx
            }
            .onEnded { _ in
                let dx = dragX
                let next = dx < -40 ? typeIndex + 1 : dx > 40 ? typeIndex - 1 : typeIndex
                withAnimation(.settle(0.46)) { dragX = 0 }
                setType(min(max(next, 0), Self.types.count - 1))
            }
    }

    private var typeDots: some View {
        HStack(spacing: 6) {
            ForEach(Self.types.indices, id: \.self) { i in
                Capsule().fill(.white).frame(width: i == typeIndex ? 18 : 6, height: 6).opacity(i == typeIndex ? 1 : 0.5)
            }
        }
        .animation(.settle(0.3), value: typeIndex)
        .accessibilityHidden(true)
    }

    private var amountText: some View {
        HStack(alignment: .top, spacing: 4) {
            Text((amount > 0 ? style.sign : "") + "Rp").font(.app(22)).opacity(0.75).padding(.top, 8)
            Text(amount > 0 ? Double(amount).formattedAsDigits() : "0")
                .font(.app(isCompact ? 44 : 56, weight: .light)).tracking(-2).lineLimit(1).minimumScaleFactor(0.5)
                .contentTransition(.numericText())
        }
        .monospacedDigit()
        .padding(.horizontal, 24)
        .opacity(amount > 0 ? 1 : 0.55)
        .scaleEffect(isBumped ? 1.04 : 1)
        .animation(.easeOut(duration: 0.12), value: isBumped)
    }

    // MARK: Rows

    private var rows: some View {
        VStack(spacing: 0) {
            if isTransfer {
                row(.account, label: isCard ? L("Dari") : L("Dari"), value: account?.name ?? (isCard ? L("Luar Saku") : L("Pilih")),
                    swatch: walletColor(account), isAsset: account?.isInvestment == true)
                row(.target, label: isCard ? L("Kartu") : L("Ke"), value: target?.name ?? L("Pilih"), swatch: walletColor(target),
                    isAsset: target?.isInvestment == true)
            } else {
                row(.category, label: L("Kategori"), value: category?.name ?? L("Belum dipilih"), icon: category?.icon,
                    iconColor: panelColor, isPlaceholder: category == nil, memory: draft.fromMemory && category != nil)
                row(.account, label: L("Dompet"), value: account?.name ?? L("Pilih"), swatch: walletColor(account))
            }
            row(.date, label: L("Tanggal"), value: dateValue, icon: "calendar", iconColor: .appTextSecondary)

            HStack(spacing: 12) {
                Text("Catatan").font(.app(15)).foregroundStyle(Color.appTextSecondary).frame(width: 76, alignment: .leading)
                TextField("Opsional", text: $draft.title)
                    .font(.app(16, weight: .medium)).foregroundStyle(Color.appText)
                    .submitLabel(.done).focused($noteFocused).onSubmit { noteFocused = false }
            }
            .frame(height: rowHeight).padding(.leading, 24).padding(.trailing, 20)
        }
    }

    private func row(_ kind: PickerKind, label: String, value: String, swatch: Color? = nil, icon: String? = nil,
                     iconColor: Color = .appTextSecondary, isPlaceholder: Bool = false, isAsset: Bool = false,
                     memory: Bool = false) -> some View {
        Button { sheet = kind } label: {
            DetailRow(label: label, value: value, swatch: swatch, icon: icon, iconColor: iconColor, sub: memory ? L("Dari ingatan Saku") : nil,
                      showsChevron: true, isAsset: isAsset, height: rowHeight, isPlaceholder: isPlaceholder)
        }
        .buttonStyle(.plain)
    }

    private var dateValue: String {
        let name = TransactionDates.dayName(draft.date)
        return calendar.isDateInToday(draft.date) || calendar.isDateInYesterday(draft.date)
            ? name + " · " + TransactionDates.dayMonth.string(from: draft.date) : name
    }

    // MARK: Sheets

    @ViewBuilder
    private func pickerSheet(_ kind: PickerKind) -> some View {
        switch kind {
        case .category:
            CategoryPickerSheet(title: L("Kategori"), categories: typeCategories, selectedId: draft.categoryId,
                                frequentIds: [], onDone: { sheet = nil }) { picked in
                draft.categoryId = picked.id
                draft.fromMemory = false
                sheet = nil
            }
        case .account:
            let list = isTransfer ? (isCard ? activeAccounts.filter { !$0.isCreditCard && !$0.isInvestment } : activeAccounts)
                                  : WalletRules.spendingSources(activeAccounts)
            WalletPickerSheet(title: isTransfer ? L("Dari dompet") : L("Dompet"), accounts: list, selectedId: draft.accountId,
                              mainId: activeAccounts.first(where: \.isDefault)?.id, recentIds: [], onDone: { sheet = nil },
                              onPick: { picked in
                draft.accountId = picked.id
                if draft.counterpartyAccountId == picked.id { draft.counterpartyAccountId = nil }
                sheet = nil
            }, footer: isCard ? .init(text: L("Tanpa dompet sumber, ini dicatat sebagai tagihan kartu yang dibayar dari luar Saku."),
                                      actionTitle: L("Dibayar dari luar Saku")) { draft.accountId = nil; sheet = nil } : nil)
        case .target:
            let list = isCard ? activeAccounts.filter(\.isCreditCard) : WalletRules.transferTargets(from: account, in: activeAccounts)
            WalletPickerSheet(title: isCard ? L("Kartu") : L("Ke dompet"), accounts: list, selectedId: draft.counterpartyAccountId,
                              mainId: activeAccounts.first(where: \.isDefault)?.id, recentIds: [], onDone: { sheet = nil },
                              onPick: { picked in draft.counterpartyAccountId = picked.id; sheet = nil })
        case .date:
            PickerSheet(title: L("Tanggal"), onDone: { sheet = nil }) {
                DayPicker(selected: draft.date, color: panelColor) { day in
                    draft.date = keepingTime(of: draft.date, on: day)
                    sheet = nil
                }
            }
        }
    }

    private func keepingTime(of date: Date, on day: Date) -> Date {
        let time = calendar.dateComponents([.hour, .minute, .second], from: date)
        return calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: day) ?? day
    }

    // MARK: Logic

    private func setType(_ index: Int) {
        guard index != typeIndex, Self.types.indices.contains(index) else { return }
        withAnimation(.settle(0.46)) { typeIndex = index }
        switch Self.types[index].type {
        case .expense: draft.kind = .expense; draft.categoryId = nil; draft.counterpartyAccountId = nil
        case .income: draft.kind = .income; draft.categoryId = nil; draft.counterpartyAccountId = nil
        default:
            draft.kind = .transfer
            draft.categoryId = nil
            if draft.counterpartyAccountId == nil || draft.counterpartyAccountId == draft.accountId {
                draft.counterpartyAccountId = WalletRules.transferTargets(from: account, in: activeAccounts).first { $0.id != draft.accountId }?.id
            }
        }
        draft.fromMemory = false
    }

    private func press(_ key: String) {
        guard let next = NumberPad.apply(key, to: amount) else { return }
        withAnimation(.easeOut(duration: 0.14)) { amount = next }
        draft.amount = Double(next)
        isBumped = true
        Task { try? await Task.sleep(for: .milliseconds(120)); isBumped = false }
    }

    private func save() {
        draft.amount = Double(amount)
        store.update(draft)
        store.learnCorrection(from: draft)
        dismiss()
    }
}
