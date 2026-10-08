import SwiftUI

/// Ubah draf (design 1e): the Tambah transaksi pattern. A coloured header with the kind and the amount,
/// the fields as rows, and the keypad. Simpan keeps the changes on the draft (it is not saved as a transaction).
struct DraftEditView: View {
    @State var draft: Draft
    @ObservedObject var store: DraftStore
    @Environment(\.dismiss) private var dismiss
    @State private var amount: Int
    @State private var bump = false
    @State private var showsDelete = false
    @State private var showsDate = false
    @State private var showsNote = false

    init(draft: Draft, store: DraftStore) {
        _draft = State(initialValue: draft)
        self.store = store
        _amount = State(initialValue: Int(draft.amount ?? 0))
    }

    private var wallets: [Account] { store.accounts.filter(\.isActive) }
    private var categories: [Category] {
        store.categories.filter { $0.type == (draft.kind == .income ? .income : .expense) && !CategoryCatalog.isSystem($0) }
    }
    private func name(_ id: String?) -> String? { store.accounts.first { $0.id == id }?.name }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                header
                rows.padding(.top, 10)
                Spacer(minLength: 8)
                AmountPad(color: draft.kindColor, isEnabled: amount > 0, onPress: press, onSave: save)
                    .padding(.horizontal, 12).padding(.bottom, 4)
            }
        }
        .background(Color.appBackground)
        .presentationDetents([.large])
        .presentationBackground(Color.appBackground)
        .confirmDialog(isPresented: $showsDelete, icon: "trash", destructive: true, title: L("Hapus draf ini?"),
                       message: L("Draf hilang dan tidak ada yang tercatat sebagai transaksi."), confirmTitle: L("Hapus")) {
            store.discard(draft.id)
            dismiss()
        }
        .sheet(isPresented: $showsDate) {
            DatePicker("", selection: $draft.date, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.graphical).padding()
                .presentationDetents([.medium]).presentationBackground(Color.appBackground)
        }
        .sheet(isPresented: $showsNote) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("Catatan")).font(.app(17, weight: .semibold))
                TextField(L("Kopi"), text: $draft.title)
                    .padding(.horizontal, 14).frame(height: 48).background(Color.appFill, in: RoundedRectangle(cornerRadius: 12))
                Button(L("Selesai")) { showsNote = false }
                    .font(.app(16, weight: .semibold)).foregroundStyle(Color.appBackground)
                    .frame(maxWidth: .infinity).frame(height: 50).background(Color.appText, in: Capsule())
                Spacer()
            }
            .padding(24).presentationDetents([.height(240)]).presentationBackground(Color.appBackground)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                Button(L("Batal")) { dismiss() }.font(.app(17)).foregroundStyle(.white)
                Spacer()
                Button { showsDelete = true } label: {
                    Image(systemName: "trash").font(.system(size: 17)).foregroundStyle(.white)
                        .frame(width: 36, height: 36).background(.white.opacity(0.16), in: Circle())
                }
                .accessibilityLabel(L("Hapus draf"))
            }
            .overlay { Text(L("Ubah draf")).font(.app(17, weight: .semibold)).foregroundStyle(.white) }
            .frame(height: 44).padding(.horizontal, 20).padding(.top, 8)

            HStack(spacing: 18) {
                ForEach(Draft.Kind.allCases, id: \.self) { kind in
                    let on = draft.kind == kind
                    Button {
                        withAnimation(.easeInOut(duration: 0.26)) { draft.kind = kind }
                        draft.categoryId = nil
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: Self.icon(kind)).font(.system(size: 13, weight: .bold))
                            Text(Self.title(kind)).font(.app(on ? 19 : 14, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(.white).opacity(on ? 1 : 0.5)
                    }
                }
            }
            .padding(.top, 8)

            HStack(spacing: 6) {
                ForEach(Draft.Kind.allCases, id: \.self) { kind in
                    Capsule().fill(.white).frame(width: draft.kind == kind ? 18 : 6, height: 6).opacity(draft.kind == kind ? 1 : 0.5)
                }
            }
            .padding(.top, 10)

            HStack(alignment: .top, spacing: 4) {
                Text((draft.kind == .expense && amount > 0 ? "−" : "") + "Rp").font(.app(22)).opacity(0.75).padding(.top, 8)
                Text(Double(amount).formattedAsDigits()).font(.app(56, weight: .light)).tracking(-2).contentTransition(.numericText())
            }
            .monospacedDigit().foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.5)
            .scaleEffect(bump ? 1.04 : 1).animation(.easeOut(duration: 0.12), value: bump)
            .padding(.horizontal, 24).padding(.top, 16)

            Label(draft.sourceLabel, systemImage: draft.sourceIcon)
                .font(.app(13, weight: .medium)).foregroundStyle(.white)
                .padding(.leading, 10).padding(.trailing, 14).frame(height: 32)
                .background(.white.opacity(0.16), in: Capsule())
                .padding(.top, 14).padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .background(draft.kindColor.animation(.easeInOut(duration: 0.45)))
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 32, bottomTrailingRadius: 32))
        .ignoresSafeArea(edges: .top)
    }

    // MARK: Rows

    @ViewBuilder
    private var rows: some View {
        VStack(spacing: 0) {
            switch draft.kind {
            case .expense, .income:
                menuRow(L("Kategori"), value: store.categories.first { $0.id == draft.categoryId }?.name, memory: draft.fromMemory && draft.categoryId != nil,
                        options: categories.map { ($0.id, $0.name) }) { draft.categoryId = $0; draft.fromMemory = false }
                menuRow(L("Dompet"), value: name(draft.accountId), memory: false,
                        options: wallets.filter { $0.type != .investment }.map { ($0.id, $0.name) }) { draft.accountId = $0 }
            case .transfer:
                menuRow(L("Dari"), value: name(draft.accountId), memory: false,
                        options: wallets.filter { $0.type != .investment }.map { ($0.id, $0.name) }) { draft.accountId = $0 }
                menuRow(L("Ke"), value: name(draft.counterpartyAccountId), memory: false,
                        options: wallets.filter { $0.id != draft.accountId }.map { ($0.id, $0.name) }) { draft.counterpartyAccountId = $0 }
            case .cardPayment:
                menuRow(L("Dari"), value: name(draft.accountId) ?? L("Luar Saku"), memory: false,
                        options: wallets.filter { $0.type != .investment && !$0.isCreditCard }.map { ($0.id, $0.name) },
                        clear: { draft.accountId = nil }) { draft.accountId = $0 }
                menuRow(L("Kartu"), value: name(draft.counterpartyAccountId), memory: false,
                        options: wallets.filter(\.isCreditCard).map { ($0.id, $0.name) }) { draft.counterpartyAccountId = $0 }
            }
            plainRow(L("Tanggal"), DateFormatter.shortDay.string(from: draft.date), icon: "calendar") { showsDate = true }
            plainRow(L("Catatan"), draft.title.isEmpty ? L("Tambah catatan") : draft.title, icon: nil) { showsNote = true }
        }
    }

    private func menuRow(_ title: String, value: String?, memory: Bool, options: [(String, String)], clear: (() -> Void)? = nil,
                         select: @escaping (String) -> Void) -> some View {
        Menu {
            ForEach(options, id: \.0) { id, label in Button(label) { select(id) } }
            if let clear { Button(L("Luar Saku"), action: clear) }
        } label: {
            rowLabel(title, value ?? L("Pilih"), warn: value == nil, memory: memory, icon: nil)
        }
    }

    private func plainRow(_ title: String, _ value: String, icon: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) { rowLabel(title, value, warn: false, memory: false, icon: icon) }
    }

    private func rowLabel(_ title: String, _ value: String, warn: Bool, memory: Bool, icon: String?) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.app(15)).foregroundStyle(Color.appTextSecondary).frame(width: 76, alignment: .leading)
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 16)).foregroundStyle(Color.appTextSecondary) }
                Text(value).font(.app(16, weight: .medium)).foregroundStyle(warn ? Color.appWarning : Color.appText).lineLimit(1)
                if memory {
                    Label(L("Ingatan"), systemImage: "brain")
                        .font(.app(11, weight: .semibold)).foregroundStyle(Color(light: 0x0E5E41, dark: 0x5CD49A))
                        .padding(.horizontal, 8).frame(height: 22)
                        .background(Color(light: 0xE6F3EC, dark: 0x1E3A2C), in: Capsule())
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.appTextTertiary)
        }
        .padding(.leading, 24).padding(.trailing, 20).frame(height: 52)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.appSeparator).frame(height: 1) }
        .contentShape(Rectangle())
    }

    // MARK: Logic

    private static func title(_ kind: Draft.Kind) -> String {
        switch kind {
        case .expense: return L("Pengeluaran")
        case .income: return L("Pemasukan")
        case .transfer: return L("Transfer")
        case .cardPayment: return L("Bayar kartu")
        }
    }

    private static func icon(_ kind: Draft.Kind) -> String {
        switch kind {
        case .expense: return "arrow.up.right"
        case .income: return "arrow.down.left"
        case .transfer: return "arrow.left.arrow.right"
        case .cardPayment: return "creditcard"
        }
    }

    private func press(_ key: String) {
        guard let next = NumberPad.apply(key, to: amount) else { return }
        withAnimation(.easeOut(duration: 0.14)) { amount = next }
        draft.amount = Double(next)
        bump = true
        Task { try? await Task.sleep(for: .milliseconds(100)); bump = false }
    }

    private func save() {
        draft.amount = Double(amount)
        store.update(draft)
        dismiss()
    }
}
