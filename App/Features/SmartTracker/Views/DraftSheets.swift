import SwiftUI

extension Draft {
    /// Fixing a draft the parser could not read: the user's words give way to what they fill in.
    mutating func clearUnreadable() {
        guard isUnreadable else { return }
        isUnreadable = false
        title = ""
    }
}

/// The picker sheets of one draft field, the same ones Tambah transaksi uses (tipe, kategori, dompet, tanggal,
/// nominal). Shared by Konfirmasi transaksi and the Catat cepat result sheet.
struct DraftFieldSheet: View {
    enum Kind { case type, category, wallet, target, date, amount }

    let draft: Draft
    let kind: Kind
    let accounts: [Account]
    let categories: [Category]
    /// Applies a change to the draft the sheet was opened for.
    let edit: ((inout Draft) -> Void) -> Void
    /// A category or wallet pick teaches Ingatan.
    var learn: () -> Void = {}
    let close: () -> Void

    var body: some View {
        switch kind {
        case .type:
            DraftTypeSheet(selected: draft.kind, onDone: close) { picked in
                edit { d in
                    guard d.kind != picked else { return }
                    d.kind = picked
                    d.categoryId = nil
                    d.counterpartyAccountId = nil
                    d.needsInvestmentWallet = false
                }
                close()
            }
        case .category:
            let type: CategoryType = draft.kind == .income ? .income : .expense
            CategoryPickerSheet(title: L("Kategori"), categories: categories.filter { $0.type == type && !CategoryCatalog.isSystem($0) },
                                selectedId: draft.categoryId, frequentIds: [], onDone: close) { category in
                edit { $0.categoryId = category.id; $0.fromMemory = false }
                learn()
                close()
            }
        case .wallet:
            walletSheet(accounts.filter { $0.isActive && !$0.isInvestment }, selected: draft.accountId,
                        title: draft.kind == .transfer ? L("Dari dompet") : L("Dompet")) { account in
                edit { d in
                    d.accountId = account.id
                    d.fromMemory = false
                    if d.counterpartyAccountId == account.id { d.counterpartyAccountId = nil }
                }
                learn()
            }
        case .target:
            let source = accounts.first { $0.id == draft.accountId }
            walletSheet(WalletRules.transferTargets(from: source, in: accounts), selected: draft.counterpartyAccountId,
                        title: L("Ke dompet")) { account in
                edit { $0.counterpartyAccountId = account.id; $0.needsInvestmentWallet = false }
            }
        case .date:
            PickerSheet(title: L("Tanggal"), onDone: close) {
                DayPicker(selected: draft.date, color: .stGreen) { day in
                    edit { $0.date = Self.keepingTime(of: $0.date, on: day) }
                    close()
                }
            }
        case .amount:
            DraftAmountSheet(amount: Int(draft.amount ?? 0)) { value in
                edit { d in
                    d.clearUnreadable()
                    d.amount = value > 0 ? Double(value) : nil
                }
            } onDone: { close() }
        }
    }

    private func walletSheet(_ list: [Account], selected: String?, title: String, onPick: @escaping (Account) -> Void) -> some View {
        WalletPickerSheet(title: title, accounts: list, selectedId: selected,
                          mainId: accounts.first(where: \.isDefault)?.id, recentIds: [],
                          onDone: close, onPick: { account in onPick(account); close() })
    }

    /// Moves `date` to `day` but keeps its time.
    private static func keepingTime(of date: Date, on day: Date) -> Date {
        let calendar = Calendar.current
        let time = calendar.dateComponents([.hour, .minute, .second], from: date)
        return calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: day) ?? day
    }
}

/// Pengeluaran, Pemasukan or Transfer, in the style of the wallet and category sheets.
struct DraftTypeSheet: View {
    let selected: Draft.Kind
    let onDone: () -> Void
    let onPick: (Draft.Kind) -> Void

    private let kinds: [(kind: Draft.Kind, title: String, detail: String, icon: String, color: Color)] = [
        (.expense, "Pengeluaran", "Uang keluar dari dompet", "arrow.up.right", .stExpense),
        (.income, "Pemasukan", "Uang masuk ke dompet", "arrow.down.left", .stGreen),
        (.transfer, "Transfer", "Pindah uang antar dompet", "arrow.left.arrow.right", .stTransfer)]

    var body: some View {
        PickerSheet(title: L("Tipe transaksi"), onDone: onDone) {
            VStack(spacing: 0) {
                ForEach(kinds, id: \.kind) { item in
                    let isOn = item.kind == selected
                    Button { onPick(item.kind) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: item.icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(item.color)
                                .frame(width: 44, height: 44).background(item.color.opacity(0.12), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L(item.title)).font(.app(16, weight: .medium))
                                Text(L(item.detail)).font(.app(13)).foregroundStyle(Color.appTextSecondary)
                            }
                            Spacer()
                            if isOn { Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundStyle(Color.appPrimary) }
                        }
                        .padding(.horizontal, 24).frame(height: 68)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(.top, 8)
        }
    }
}

/// Nominal: big amount and the number pad, like the budget sheet. The first key replaces the shown amount.
struct DraftAmountSheet: View {
    @State private var amount: Int
    @State private var isFresh = true
    /// The sheet is as tall as its content, so there is no empty space under the keypad.
    @State private var height: CGFloat = 420
    let onChange: (Int) -> Void
    let onDone: () -> Void

    init(amount: Int, onChange: @escaping (Int) -> Void, onDone: @escaping () -> Void) {
        _amount = State(initialValue: amount)
        self.onChange = onChange
        self.onDone = onDone
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Nominal").font(.app(17, weight: .semibold))
                Spacer()
                Button("Selesai", action: onDone).font(.app(17, weight: .semibold)).foregroundStyle(Color.appPrimary)
            }
            .frame(height: 48).padding(.horizontal, 24).padding(.top, 14)
            HStack(alignment: .top, spacing: 4) {
                Text("Rp").font(.app(20)).foregroundStyle(Color.appTextSecondary).padding(.top, 7)
                Text(Double(amount).formattedAsDigits())
                    .font(.app(48, weight: .light)).tracking(-1.8)
                    .foregroundStyle(amount > 0 ? Color.appText : Color(light: 0xC7C7CC, dark: 0x48484A))
                    .lineLimit(1).minimumScaleFactor(0.6).contentTransition(.numericText())
            }
            .monospacedDigit()
            .frame(maxWidth: .infinity).padding(.top, 8).padding(.bottom, 16)
            AmountPad(color: .stGreen, isEnabled: amount > 0, onPress: press, onSave: onDone, title: "Terapkan")
                .padding(.horizontal, 12).padding(.bottom, 8)
        }
        .foregroundStyle(Color.appText)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height + 34)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(Color.appBackground)
    }

    private func press(_ key: String) {
        guard let next = NumberPad.apply(key, to: isFresh ? 0 : amount) else { return }
        isFresh = false
        withAnimation(.snappy(duration: 0.2)) { amount = next }
        onChange(next)
    }
}
