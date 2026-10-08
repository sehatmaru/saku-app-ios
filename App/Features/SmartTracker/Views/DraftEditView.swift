import SwiftUI

/// Edits every field of a draft before it is saved.
struct DraftEditView: View {
    @State var draft: Draft
    @ObservedObject var store: DraftStore
    @Environment(\.dismiss) private var dismiss
    @State private var amountText: String

    init(draft: Draft, store: DraftStore) {
        _draft = State(initialValue: draft)
        self.store = store
        _amountText = State(initialValue: draft.amount.map { String(Int($0)).formattedWithThousandSeparator } ?? "")
    }

    private var wallets: [Account] { store.accounts.filter(\.isActive) }
    private var spendingWallets: [Account] { wallets.filter { $0.type != .investment } }
    private var categories: [Category] {
        store.categories.filter { $0.type == (draft.kind == .income ? .income : .expense) && !CategoryCatalog.isSystem($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(L("Batal")) { dismiss() }.foregroundStyle(Color.appTextSecondary)
                Spacer()
                Text(L("Ubah draf")).font(.app(17, weight: .semibold))
                Spacer()
                Button(L("Selesai")) { store.update(draft); dismiss() }
                    .font(.app(17, weight: .semibold))
                    .foregroundStyle(Color.appPrimary)
            }
            .font(.app(17))
            .padding(.horizontal, 20)
            .frame(height: 52)

            ScrollView {
                VStack(spacing: 0) {
                    Picker("", selection: $draft.kind) {
                        Text(L("Keluar")).tag(Draft.Kind.expense)
                        Text(L("Masuk")).tag(Draft.Kind.income)
                        Text(L("Transfer")).tag(Draft.Kind.transfer)
                        Text(L("Bayar kartu")).tag(Draft.Kind.cardPayment)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                    .onChange(of: draft.kind) { _, _ in draft.categoryId = nil }

                    field(L("Nominal")) {
                        HStack(spacing: 6) {
                            Text("Rp").foregroundStyle(Color.appTextSecondary)
                            TextField("0", text: $amountText)
                                .keyboardType(.numberPad)
                                .monospacedDigit()
                                .onChange(of: amountText) { _, text in
                                    let digits = text.filter(\.isNumber)
                                    let formatted = digits.formattedWithThousandSeparator
                                    if formatted != text { amountText = formatted }
                                    draft.amount = Double(digits)
                                }
                        }
                    }
                    field(L("Catatan")) { TextField(L("Kopi"), text: $draft.title) }
                    menuField(draft.kind == .income ? L("Masuk ke") : L("Dari dompet"),
                              value: store.accounts.first { $0.id == draft.accountId }?.name,
                              options: (draft.kind == .transfer || draft.kind == .cardPayment ? spendingWallets.filter { !$0.isCreditCard || draft.kind == .transfer } : wallets.filter { $0.type != .investment }).map { ($0.id, $0.name) },
                              select: { draft.accountId = $0 }, clear: draft.kind == .cardPayment ? { draft.accountId = nil } : nil)
                    if draft.kind == .transfer || draft.kind == .cardPayment {
                        menuField(draft.kind == .cardPayment ? L("Kartu") : L("Ke dompet"),
                                  value: store.accounts.first { $0.id == draft.counterpartyAccountId }?.name,
                                  options: (draft.kind == .cardPayment ? wallets.filter(\.isCreditCard) : wallets.filter { $0.id != draft.accountId }).map { ($0.id, $0.name) },
                                  select: { draft.counterpartyAccountId = $0 }, clear: nil)
                    } else {
                        menuField(L("Kategori"), value: store.categories.first { $0.id == draft.categoryId }?.name,
                                  options: categories.map { ($0.id, $0.name) }, select: { draft.categoryId = $0 }, clear: nil)
                    }
                    field(L("Tanggal")) { DatePicker("", selection: $draft.date, in: ...Date(), displayedComponents: .date).labelsHidden() }

                    if draft.kind == .cardPayment && draft.accountId == nil {
                        Text(L("Tanpa dompet sumber, ini dicatat sebagai tagihan kartu yang dibayar dari luar Saku."))
                            .font(.app(13)).foregroundStyle(Color.appTextSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.top, 10)
                    }
                    if let note = draft.duplicateNote {
                        Label(note, systemImage: "doc.on.doc")
                            .font(.app(13)).foregroundStyle(Color.appWarning)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.top, 10)
                    }
                }
                .padding(.top, 8)
            }
        }
        .background(Color.appBackground)
        .presentationDetents([.large])
        .presentationBackground(Color.appBackground)
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).foregroundStyle(Color.appTextSecondary)
            Spacer()
            content().multilineTextAlignment(.trailing)
        }
        .font(.app(16))
        .padding(.horizontal, 24)
        .frame(minHeight: 54)
        .rowSeparator()
    }

    private func menuField(_ title: String, value: String?, options: [(String, String)], select: @escaping (String) -> Void,
                           clear: (() -> Void)?) -> some View {
        field(title) {
            Menu {
                ForEach(options, id: \.0) { id, name in Button(name) { select(id) } }
                if let clear { Button(L("Tanpa dompet"), role: .destructive, action: clear) }
            } label: {
                HStack(spacing: 4) {
                    Text(value ?? L("Pilih")).foregroundStyle(value == nil ? Color.appWarning : Color.appText)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 11)).foregroundStyle(Color.appTextTertiary)
                }
            }
        }
    }
}
