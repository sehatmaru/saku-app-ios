import SwiftUI

/// What the user changed on the Ubah dompet page.
struct WalletEdit {
    var name: String
    var icon: String?          // provider id, e.g. "bca" (same ids WalletIcon uses)
    var color: String?         // hex without #, cash wallets (and fallback)
    var cardNetwork: String?   // visa/mastercard/jcb/amex/gpn, credit only
    var balance: Double        // saldo; for a credit card this is the DEBT ("Tagihan saat ini")
    var creditLimit: Double?
    var dueDay: Int?
    var statementDay: Int?     // cut-off, credit only
    var isDefault: Bool
}

/// Ubah dompet (design "Edit Dompet" 1a–1c): the same card-as-form as Tambah dompet, every change
/// shows on the card straight away. The type is locked; saldo is adjusted, not overwritten. Simpan
/// lights up once something changed; Arsipkan and Hapus always ask first.
struct EditWalletView: View {
    @Environment(\.dismiss) private var dismiss

    private let account: Account
    private let transactionCount: Int
    private let onSave: (WalletEdit) async -> Bool
    private let onArchive: () async -> Bool
    private let onUnarchive: () async -> Bool
    private let onDelete: () async -> Bool

    init(account: Account, transactionCount: Int,
         onSave: @escaping (WalletEdit) async -> Bool,
         onArchive: @escaping () async -> Bool,
         onUnarchive: @escaping () async -> Bool,
         onDelete: @escaping () async -> Bool) {
        self.account = account
        self.transactionCount = transactionCount
        self.onSave = onSave
        self.onArchive = onArchive
        self.onUnarchive = onUnarchive
        self.onDelete = onDelete
        let draft = Draft(account)
        _orig = State(initialValue: draft)
        _cur = State(initialValue: draft)
        _isArchived = State(initialValue: account.isArchived)
    }

    /// The editable values; Simpan is live while `cur` differs from `orig`.
    private struct Draft: Equatable {
        var name: String
        var icon: String?
        var color: String?
        var network: String?
        /// Saldo, or the current bill for a card.
        var balance: Int
        var limit: Int
        var dueDay: Int?
        var statementDay: Int?
        var isDefault: Bool

        init(_ a: Account) {
            name = a.name
            icon = a.icon
            color = a.color
            network = a.networkId
            balance = Int(a.balance.rounded())
            limit = Int((a.creditLimit ?? 0).rounded())
            dueDay = a.dueDay
            statementDay = a.statementDay
            isDefault = a.isDefault
        }
    }

    private enum Field { case balance, limit }

    private enum Sheet: Identifiable {
        case provider, network, due, statement, amount(Field), archive, delete
        var id: String { "\(self)" }
    }

    private enum End { case archived, deleted }

    @State private var orig: Draft
    @State private var cur: Draft
    @State private var isArchived: Bool
    @State private var sheet: Sheet?
    @State private var isSaving = false
    @State private var isBusy = false
    /// Save feedback: check badge + card pop, then the toast.
    @State private var saved = false
    @State private var toast = false
    @State private var toastText = "Perubahan disimpan"
    @State private var pop = false
    // Number pad
    @State private var buf = 0
    @State private var fresh = true
    @State private var bump = false
    // End screen after archive/delete
    @State private var end: End = .archived
    @State private var endShown = false
    @State private var failMessage: String?
    @FocusState private var nameFocused: Bool

    private static let faint = Color(light: 0xC7C7CC, dark: 0x48484A)

    private var isCredit: Bool { account.type == .credit }
    private var isCash: Bool { account.type == .cash }
    private var trimmedName: String { cur.name.trimmingCharacters(in: .whitespaces) }
    private var isDirty: Bool { cur != orig }
    private var canSave: Bool { isDirty && !trimmedName.isEmpty && !isSaving }

    /// The account as it would look saved, so the card pieces from the Dompet page resolve colour and logos.
    private var preview: Account {
        Account(id: account.id, name: cur.name, type: account.type, icon: cur.icon, isArchived: isArchived,
                isDefault: cur.isDefault, openingBalance: Double(cur.balance), currentBalance: Double(cur.balance),
                creditLimit: isCredit ? Double(cur.limit) : nil, dueDate: cur.dueDay.map(String.init),
                statementDay: cur.statementDay, color: cur.color, cardNetwork: cur.network)
    }

    private var providers: [WalletIcon] {
        switch account.type {
        case .bank: WalletIcon.icons(for: .bank)
        case .ewallet: WalletIcon.icons(for: .ewallet)
        case .credit: AddWalletView.issuers.compactMap { issuer in WalletIcon.allIcons.first { $0.id == issuer.id } }
        case .cash: []
        }
    }

    /// The bank or e-wallet the wallet belongs to, if it's one we know.
    private var currentProvider: WalletIcon? {
        WalletIcon.allIcons.first { $0.id == cur.icon && ($0.category == .bank || $0.category == .ewallet) }
    }

    private func networkLabel(_ id: String?) -> String? {
        AddWalletView.networks.first { $0.id == id }?.label
    }

    private var typeLabel: String {
        switch account.type {
        case .bank: "Bank"
        case .ewallet: "E-wallet"
        case .cash: "Tunai"
        case .credit: "Kartu kredit"
        }
    }

    private var providerLabel: String { isCredit ? "Bank penerbit" : account.type == .bank ? "Bank" : "E-wallet" }

    private static func rp(_ value: Int) -> String { Double(value).formattedAsCurrency() }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                card
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                formRows
                    .overlay(alignment: .top) { Rectangle().fill(Color.appSeparator).frame(height: 1) }
                    .padding(.top, 24)
                actionRows
                    .overlay(alignment: .top) { Rectangle().fill(Color.appSeparator).frame(height: 1) }
                    .padding(.top, 28)
                Text("\(transactionCount) transaksi")
                    .font(.app(13))
                    .foregroundStyle(Color.appTextTertiary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                    .padding(.bottom, 60)
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Color.appBackground.ignoresSafeArea())
        .foregroundStyle(Color.appText)
        .toast(toastText, isShown: $toast)
        .overlay { endScreen }
        .navigationBarTitleDisplayMode(.inline)
        // ponytail: hiding the back button drops the swipe-back gesture; Batal is the way out.
        .navigationBarBackButtonHidden(true)
        .toolbar(endShown ? .hidden : .visible, for: .navigationBar)
        .toolbar { toolbar }
        .sheet(item: $sheet) { sheetView($0) }
        .onChange(of: sheet?.id) { _, _ in nameFocused = false }
        .alert(failMessage ?? "", isPresented: Binding(get: { failMessage != nil }, set: { if !$0 { failMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Periksa koneksi lalu coba lagi.")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Batal") {
                if isDirty {
                    nameFocused = false
                    withAnimation(.settle(0.42)) { cur = orig }
                } else {
                    dismiss()
                }
            }
            .font(.app(17))
            .foregroundStyle(Color.appPrimary)
        }
        ToolbarItem(placement: .principal) {
            Text("Ubah dompet").font(.app(17, weight: .semibold))
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: save) {
                if isSaving {
                    ProgressView()
                } else {
                    Text("Simpan")
                        .font(.app(17, weight: .semibold))
                        .foregroundStyle(canSave ? Color.appPrimary : Self.faint)
                        .animation(.easeInOut(duration: 0.22), value: canSave)
                }
            }
            .disabled(!canSave)
        }
    }

    // MARK: Card

    private var card: some View {
        let a = preview
        return ZStack {
            CardSurface(color: a.walletColor, symbol: a.typeSymbol, symbolTilted: true)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    CardLogoBox(logo: a.brandLogo, symbol: a.typeSymbol, color: a.walletColor)
                        .scaleEffect(pop ? 0.6 : 1)
                        .animation(pop ? .easeOut(duration: 0.08) : .spring(duration: 0.46, bounce: 0.55), value: pop)
                    TextField("", text: $cur.name, prompt: Text("Nama dompet").foregroundStyle(.white.opacity(0.6)))
                        .font(.app(17, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(.white)
                        .tint(.white)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onChange(of: cur.name) { _, value in if value.count > 28 { cur.name = String(value.prefix(28)) } }
                        .padding(.trailing, saved ? 34 : 0)
                    Image(systemName: "pencil")
                        .font(.system(size: 16))
                        .opacity(saved ? 0 : 0.7)
                        .animation(.easeInOut(duration: 0.2), value: saved)
                        .accessibilityHidden(true)
                }
                .overlay(alignment: .trailing) {
                    Circle()
                        .fill(.white)
                        .frame(width: 28, height: 28)
                        .overlay(Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(a.walletColor))
                        .scaleEffect(saved ? 1 : 0)
                        .animation(.spring(duration: 0.52, bounce: 0.6), value: saved)
                        .offset(x: 4)
                        .accessibilityHidden(true)
                }

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    if isCredit, cur.limit > 0 {
                        CardUsageBar(usedText: Self.rp(cur.balance), share: Double(cur.balance) / Double(cur.limit))
                            .animation(.settle(0.6), value: cur.balance)
                            .transition(.opacity)
                    }
                    HStack(alignment: .bottom, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isCredit ? "Sisa limit" : "Saldo").font(.app(12)).foregroundStyle(.white.opacity(0.8))
                            Text(Self.rp(isCredit ? max(cur.limit - cur.balance, 0) : cur.balance))
                                .font(.app(32))
                                .tracking(-0.8)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .contentTransition(.numericText())
                        }
                        Spacer(minLength: 0)
                        if isCredit {
                            VStack(alignment: .trailing, spacing: 2) {
                                if let network = cur.network {
                                    CardNetworkBadge(network: network)
                                        .padding(.bottom, 6)
                                        .transition(.scale(scale: 0.8, anchor: .trailing).combined(with: .opacity))
                                }
                                Text("Jatuh tempo").font(.app(12)).foregroundStyle(.white.opacity(0.8))
                                Text(cur.dueDay.map { "Tgl \($0)" } ?? "—")
                                    .font(.app(15, weight: .semibold))
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                            }
                            .padding(.bottom, 3)
                            .animation(.spring(duration: 0.46, bounce: 0.5), value: cur.network)
                        } else {
                            HStack(spacing: 5) {
                                Image(systemName: "star.fill").font(.system(size: 11))
                                Text("Utama").font(.app(12))
                            }
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.bottom, 5)
                            .opacity(cur.isDefault ? 1 : 0)
                            .animation(.easeInOut(duration: 0.26), value: cur.isDefault)
                            .accessibilityHidden(!cur.isDefault)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .frame(height: 216)
        .foregroundStyle(.white)
        .scaleEffect(saved ? 1.02 : 1)
        .animation(.spring(duration: 0.42, bounce: 0.5), value: saved)
        .animation(.easeInOut(duration: 0.48), value: a.walletColor)
    }

    // MARK: Rows

    private var formRows: some View {
        VStack(spacing: 0) {
            rowContent("Tipe") {
                HStack(spacing: 8) {
                    Image(systemName: account.type.cardSymbol)
                        .font(.system(size: 17))
                        .foregroundStyle(Color.appTextSecondary)
                    Text(typeLabel).font(.app(16, weight: .medium))
                }
            } trailing: {
                Image(systemName: "lock")
                    .font(.system(size: 14))
                    .foregroundStyle(Self.faint)
                    .accessibilityLabel("Terkunci")
            }

            if !isCash {
                tapRow(providerLabel, open: .provider) {
                    HStack(spacing: 10) {
                        logoChip {
                            if let logo = currentProvider?.id {
                                Image(logo).resizable().scaledToFit().frame(width: 24, height: 14)
                            } else {
                                Image(systemName: account.type.cardSymbol).font(.system(size: 11)).foregroundStyle(Color.appTextSecondary)
                            }
                        }
                        Text(currentProvider?.name ?? "Lainnya").font(.app(16, weight: .medium))
                    }
                } trailing: { chevron }
            }

            if isCredit {
                tapRow("Jenis kartu", open: .network) {
                    HStack(spacing: 10) {
                        logoChip { networkLogo(cur.network, width: 24, height: 14, gpnSize: 9) }
                        Text(networkLabel(cur.network) ?? "Pilih").font(.app(16, weight: .medium))
                    }
                } trailing: { chevron }
            }

            if isCash {
                rowContent("Warna", height: 60) {
                    HStack(spacing: 10) {
                        ForEach(AddWalletView.swatches, id: \.self) { hex in
                            let on = cur.color == hex
                            Button { withAnimation(.easeInOut(duration: 0.3)) { cur.color = hex } } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 28, height: 28)
                                    .background(Circle().stroke(Color(hex: hex), lineWidth: on ? 2 : 0).padding(-4))
                                    .scaleEffect(on ? 1.08 : 1)
                                    .animation(.spring(duration: 0.38, bounce: 0.5), value: on)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Warna \(hex)")
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                } trailing: { EmptyView() }
            }

            if isCredit {
                amountRow("Limit kredit", value: cur.limit, action: "Ubah", field: .limit)
                amountRow("Tagihan saat ini", value: cur.balance, action: "Sesuaikan", field: .balance)
                tapRow("Jatuh tempo", open: .due) {
                    Text(cur.dueDay.map { "Tanggal \($0)" } ?? "—").font(.app(16, weight: .medium)).monospacedDigit()
                } trailing: { chevron }
                tapRow("Cetak tagihan", open: .statement) {
                    Text(cur.statementDay.map { "Tanggal \($0)" } ?? "—").font(.app(16, weight: .medium)).monospacedDigit()
                } trailing: { chevron }
            } else {
                amountRow("Saldo saat ini", value: cur.balance, action: "Sesuaikan", field: .balance)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dompet utama").font(.app(16))
                        Text("Dipilih otomatis saat mencatat transaksi").font(.app(13)).foregroundStyle(Color.appTextSecondary)
                    }
                    Spacer(minLength: 0)
                    Toggle("Dompet utama", isOn: $cur.isDefault)
                        .labelsHidden()
                        .tint(Color.appPrimary)
                }
                .padding(.horizontal, 24)
                .frame(height: 64)
                .rowSeparator()
            }
        }
    }

    private var actionRows: some View {
        VStack(spacing: 0) {
            Button {
                if isArchived { Task { await unarchive(fromEnd: false) } } else { sheet = .archive }
            } label: {
                actionLabel(isArchived ? "Pulihkan dompet" : "Arsipkan dompet",
                            icon: isArchived ? "arrow.uturn.backward" : "archivebox", tint: Color.appText)
            }
            .buttonStyle(RowHighlightStyle())
            .disabled(isBusy)

            Button { sheet = .delete } label: {
                actionLabel("Hapus dompet", icon: "trash", tint: Color.appError)
            }
            .buttonStyle(RowHighlightStyle(tint: Color.appError.opacity(0.06)))
        }
    }

    private func actionLabel(_ title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 19)).frame(width: 24)
            Text(title).font(.app(16))
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 24)
        .frame(height: 52)
        .contentShape(Rectangle())
        .rowSeparator()
    }

    private func rowContent<V: View, T: View>(_ label: String, height: CGFloat = 52,
                                              @ViewBuilder value: () -> V, @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.app(15))
                .foregroundStyle(Color.appTextSecondary)
                .lineLimit(1)
                .frame(width: 124, alignment: .leading)
            value().frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(.leading, 24)
        .padding(.trailing, 20)
        .frame(height: height)
        .contentShape(Rectangle())
        .rowSeparator()
    }

    private func tapRow<V: View, T: View>(_ label: String, open: Sheet,
                                          @ViewBuilder value: () -> V, @ViewBuilder trailing: () -> T) -> some View {
        Button { sheet = open } label: {
            rowContent(label, value: value, trailing: trailing)
        }
        .buttonStyle(RowHighlightStyle())
    }

    private func amountRow(_ label: String, value: Int, action: String, field: Field) -> some View {
        Button { openNumpad(field) } label: {
            rowContent(label) {
                Text(Self.rp(value))
                    .font(.app(16, weight: .medium))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            } trailing: {
                Text(action).font(.app(15)).foregroundStyle(Color.appPrimary)
            }
        }
        .buttonStyle(RowHighlightStyle())
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Self.faint)
    }

    /// 32×22 outlined box holding a small logo.
    private func logoChip<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(.white)
            .frame(width: 32, height: 22)
            .overlay(content())
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color(light: 0xE5E5EA, dark: 0x3A3A3C)))
    }

    @ViewBuilder
    private func networkLogo(_ id: String?, width: CGFloat, height: CGFloat, gpnSize: CGFloat) -> some View {
        if id == "gpn" {
            Text("GPN").font(.app(gpnSize, weight: .heavy)).tracking(0.5).foregroundStyle(Color(hex: "C8102E"))
        } else if let id {
            Image(id).resizable().scaledToFit().frame(width: width, height: height)
        }
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetView(_ s: Sheet) -> some View {
        switch s {
        case .provider:
            SheetFrame(title: isCredit ? "Bank penerbit" : account.type == .bank ? "Pilih bank" : "Pilih e-wallet",
                       closeTitle: "Selesai", onClose: closeSheet) { providerGrid }
        case .network:
            SheetFrame(title: "Jenis kartu", closeTitle: "Selesai", onClose: closeSheet) { networkList }
        case .due:
            SheetFrame(title: "Jatuh tempo", closeTitle: "Selesai", onClose: closeSheet) {
                dayGrid(\.dueDay, note: "Tagihan dicatat sebagai utang dan tidak mengurangi total saldo.")
            }
        case .statement:
            SheetFrame(title: "Tanggal cetak tagihan", closeTitle: "Selesai", onClose: closeSheet) {
                dayGrid(\.statementDay, note: "Belanja setelah tanggal ini masuk ke tagihan bulan berikutnya.")
            }
        case .amount(let field):
            SheetFrame(title: field == .limit ? "Limit kredit" : isCredit ? "Sesuaikan tagihan" : "Sesuaikan saldo",
                       closeTitle: "Batal", onClose: closeSheet) { numpad(field) }
        case .archive:
            SheetFrame(title: "Arsipkan \(orig.name)?", closeTitle: "Batal", onClose: closeSheet) {
                confirm(text: "Dompet disembunyikan dari daftar dan total saldo. Riwayat transaksi tetap tersimpan dan bisa dipulihkan kapan saja.",
                        button: "Arsipkan", icon: "archivebox", destructive: false) { await archive() }
            }
        case .delete:
            if transactionCount > 0 {
                SheetFrame(title: "\(orig.name) tidak bisa dihapus", closeTitle: "Batal", onClose: closeSheet) {
                    confirm(text: "Dompet ini punya \(transactionCount) transaksi, jadi tidak bisa dihapus. "
                            + (isArchived ? "Dompet ini sudah diarsipkan, riwayatnya tetap tersimpan."
                               : "Arsipkan saja: dompet disembunyikan dari daftar dan total saldo, riwayatnya tetap tersimpan."),
                            button: isArchived ? nil : "Arsipkan saja", icon: "archivebox", destructive: false) { await archive() }
                }
            } else {
                SheetFrame(title: "Hapus \(orig.name)?", closeTitle: "Batal", onClose: closeSheet) {
                    confirm(text: "Dompet ini akan dihapus permanen. Tindakan ini tidak bisa dibatalkan.",
                            button: "Hapus permanen", icon: "trash", destructive: true) { await delete() }
                }
            }
        }
    }

    private var providerGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 4), spacing: 18) {
            ForEach(providers) { p in
                let on = cur.icon == p.id
                let ring = isCredit ? AddWalletView.issuers.first { $0.id == p.id }.map { Color(hex: $0.color) } ?? p.color : p.color
                Button { pickProvider(p) } label: {
                    VStack(spacing: 8) {
                        Circle()
                            .fill(.white)
                            .frame(width: 62, height: 62)
                            .overlay(Image(p.id).resizable().scaledToFit().frame(width: 42, height: 24))
                            .overlay(Circle().strokeBorder(Color(light: 0xE5E5EA, dark: 0x3A3A3C), lineWidth: on ? 0 : 1))
                            .background(Circle().stroke(ring, lineWidth: on ? 2 : 0).padding(-3))
                            .scaleEffect(on ? 1.06 : 1)
                            .animation(.spring(duration: 0.42, bounce: 0.5), value: on)
                        Text(p.name)
                            .font(.app(13, weight: on ? .semibold : .regular))
                            .foregroundStyle(Color.appText)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var networkList: some View {
        VStack(spacing: 0) {
            ForEach(AddWalletView.networks, id: \.id) { net in
                let on = cur.network == net.id
                Button { pickNetwork(net.id) } label: {
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(light: 0xF7F7F8, dark: 0x2C2C2E))
                            .frame(width: 48, height: 32)
                            .overlay(networkLogo(net.id, width: 36, height: 20, gpnSize: 12))
                        Text(net.label).font(.app(16, weight: on ? .semibold : .regular))
                        Spacer(minLength: 0)
                        Image(systemName: "checkmark")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color.appPrimary)
                            .opacity(on ? 1 : 0)
                            .scaleEffect(on ? 1 : 0.4)
                            .animation(.spring(duration: 0.38, bounce: 0.6), value: on)
                    }
                    .padding(.horizontal, 24)
                    .frame(height: 56)
                    .contentShape(Rectangle())
                    .rowSeparator()
                }
                .buttonStyle(RowHighlightStyle())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.bottom, 4)
    }

    private func dayGrid(_ key: WritableKeyPath<Draft, Int?>, note: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(1...31, id: \.self) { day in
                    let on = cur[keyPath: key] == day
                    Button {
                        withAnimation(.settle(0.4)) { cur[keyPath: key] = day }
                        closeSoon()
                    } label: {
                        Text("\(day)")
                            .font(.app(16, weight: on ? .semibold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(on ? .white : Color.appText)
                            .frame(width: 38, height: 38)
                            .background(on ? Color.appPrimary : .clear, in: Circle())
                            .scaleEffect(on ? 1.06 : 1)
                            .animation(.spring(duration: 0.38, bounce: 0.5), value: on)
                            .frame(height: 44)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Tanggal \(day)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Text(note)
                .font(.app(13))
                .foregroundStyle(Color.appTextSecondary)
                .lineSpacing(3)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    private func numpad(_ field: Field) -> some View {
        let prev = field == .limit ? cur.limit : cur.balance
        let delta = buf - prev
        let isSaldo = field == .balance && !isCredit
        let chipBg = isSaldo ? (delta > 0 ? Color.appPrimary.opacity(0.12) : Color.appError.opacity(0.12)) : Color.appFill
        let chipFg = isSaldo ? (delta > 0 ? Color.appPrimary : Color.appError) : Color.appBody
        return VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack(alignment: .top, spacing: 4) {
                    Text("Rp").font(.app(20)).foregroundStyle(Color.appTextSecondary).padding(.top, 7)
                    Text(Double(buf).formattedAsDigits())
                        .font(.app(48, weight: .light))
                        .tracking(-1.8)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .opacity(fresh ? 0.4 : 1)
                        .animation(.easeInOut(duration: 0.2), value: fresh)
                        .contentTransition(.numericText())
                }
                .monospacedDigit()
                .scaleEffect(bump ? 1.04 : 1)
                .animation(.easeOut(duration: 0.14), value: bump)

                HStack(spacing: 8) {
                    Text("Sebelumnya \(Self.rp(prev))")
                    Text((delta > 0 ? "+" : delta < 0 ? "−" : "") + Self.rp(abs(delta)))
                        .font(.app(13, weight: .semibold))
                        .foregroundStyle(chipFg)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(chipBg, in: Capsule())
                        .opacity(delta != 0 ? 1 : 0)
                        .scaleEffect(delta != 0 ? 1 : 0.6)
                        .animation(.spring(duration: 0.38, bounce: 0.5), value: delta != 0)
                        .animation(.easeInOut(duration: 0.22), value: delta > 0)
                }
                .font(.app(13))
                .foregroundStyle(Color.appTextSecondary)
                .monospacedDigit()

                Text(field == .limit ? "Limit baru berlaku untuk perhitungan sisa limit."
                     : "Selisihnya dicatat sebagai transaksi Penyesuaian saldo.")
                    .font(.app(13))
                    .foregroundStyle(Color.appTextTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 18)

            GeometryReader { geo in
                let side = (geo.size.width - 6) / 4
                HStack(spacing: 6) {
                    NumberPadKeys(onPress: press)
                        .frame(width: geo.size.width - side - 6)
                    Button { apply(field) } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "checkmark").font(.system(size: 24, weight: .bold))
                            Text("Terapkan").font(.app(14, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(PressScaleStyle())
                    .frame(width: side)
                }
            }
            .frame(height: 52 * 4 + 6 * 3)
            .padding(.horizontal, 12)
        }
    }

    /// Sheet copy plus one full-width capsule; `button` nil shows the explanation only.
    private func confirm(text: String, button: String?, icon: String, destructive: Bool,
                         action: @escaping () async -> Void) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(text)
                .font(.app(15))
                .foregroundStyle(Color.appBody)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            if let button {
                Button { Task { await action() } } label: {
                    HStack(spacing: 8) {
                        if isBusy {
                            ProgressView().tint(destructive ? .white : Color.appBackground)
                        } else {
                            Image(systemName: icon).font(.system(size: 16, weight: .bold))
                        }
                        Text(button).font(.app(17, weight: .semibold))
                    }
                    .foregroundStyle(destructive ? .white : Color.appBackground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(destructive ? Color.appError : Color.appText, in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
                .disabled(isBusy)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    // MARK: End screen

    private var endScreen: some View {
        let deleted = end == .deleted
        return VStack(spacing: 8) {
            Circle()
                .fill(deleted ? Color.appError.opacity(0.12) : Color.appFill)
                .frame(width: 72, height: 72)
                .overlay(Image(systemName: deleted ? "trash" : "archivebox").font(.system(size: 30)))
                .foregroundStyle(deleted ? Color.appError : Color.appText)
                .scaleEffect(endShown ? 1 : 0.4)
                .animation(.spring(duration: 0.56, bounce: 0.5).delay(endShown ? 0.12 : 0), value: endShown)
            Text(orig.name + (deleted ? " dihapus" : " diarsipkan"))
                .font(.app(20, weight: .semibold))
                .tracking(-0.2)
                .padding(.top, 10)
            Text(deleted ? "Dompet sudah dihapus." : "Kamu bisa memulihkannya dari Dompet › Diarsipkan.")
                .font(.app(15))
                .foregroundStyle(Color.appTextSecondary)
                .lineSpacing(3)
            Button {
                if deleted { dismiss() } else { Task { await unarchive(fromEnd: true) } }
            } label: {
                HStack(spacing: 8) {
                    if isBusy {
                        ProgressView()
                    } else {
                        Image(systemName: deleted ? "chevron.left" : "arrow.counterclockwise").font(.system(size: 15, weight: .bold))
                    }
                    Text(deleted ? "Kembali" : "Urungkan").font(.app(16, weight: .semibold))
                }
                .foregroundStyle(Color.appText)
                .padding(.horizontal, 24)
                .frame(height: 48)
                .background(Color.appFill, in: Capsule())
            }
            .buttonStyle(PressScaleStyle())
            .disabled(isBusy)
            .padding(.top, 18)
            if !deleted {
                // Not in the design: without it the only way off this screen would be Urungkan.
                Button("Kembali ke Dompet") { dismiss() }
                    .font(.app(15))
                    .foregroundStyle(Color.appPrimary)
                    .padding(.top, 8)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground.ignoresSafeArea())
        .opacity(endShown ? 1 : 0)
        .animation(.easeOut(duration: 0.32), value: endShown)
        .allowsHitTesting(endShown)
    }

    // MARK: Actions

    private func closeSheet() { sheet = nil }

    /// Closes a picker just after the pick lands, so the ring/check spring shows first.
    private func closeSoon() {
        Task { try? await Task.sleep(for: .seconds(0.26)); sheet = nil }
    }

    private func pickProvider(_ p: WalletIcon) {
        let net = networkLabel(cur.network)
        withAnimation(.settle(0.42)) {
            // Rename only while the name is still the old provider's default.
            if let old = currentProvider {
                let defaults = [old.name, "Kartu Kredit \(old.name)"] + (net.map { ["\(old.name) \($0)"] } ?? [])
                if defaults.contains(cur.name) {
                    cur.name = isCredit ? net.map { "\(p.name) \($0)" } ?? "Kartu Kredit \(p.name)" : p.name
                }
            }
            cur.icon = p.id
            // Brand colour comes with the logo; cards take the issuer's colour (as in Tambah dompet).
            cur.color = isCredit ? AddWalletView.issuers.first { $0.id == p.id }?.color : nil
        }
        pop = true
        Task { try? await Task.sleep(for: .seconds(0.09)); pop = false }
        closeSoon()
    }

    private func pickNetwork(_ id: String) {
        withAnimation(.settle(0.42)) {
            if let p = currentProvider, let label = networkLabel(id) {
                let defaults = ["Kartu Kredit \(p.name)"] + (networkLabel(cur.network).map { ["\(p.name) \($0)"] } ?? [])
                if defaults.contains(cur.name) { cur.name = "\(p.name) \(label)" }
            }
            cur.network = id
        }
        closeSoon()
    }

    private func openNumpad(_ field: Field) {
        buf = field == .limit ? cur.limit : cur.balance
        fresh = true
        sheet = .amount(field)
    }

    /// The first key replaces the old amount; after that keys append.
    private func press(_ key: String) {
        if fresh && key == "del" {
            buf = 0
        } else if let next = NumberPad.apply(key, to: fresh ? 0 : buf) {
            withAnimation(.settle(0.2)) { buf = next }
        }
        fresh = false
        bump = true
        Task { try? await Task.sleep(for: .seconds(0.11)); bump = false }
    }

    private func apply(_ field: Field) {
        withAnimation(.settle(0.42)) {
            if field == .limit { cur.limit = buf } else { cur.balance = buf }
        }
        sheet = nil
    }

    private func save() {
        guard canSave else { return }
        nameFocused = false
        isSaving = true
        let edit = WalletEdit(
            name: trimmedName,
            icon: cur.icon,
            color: cur.color,
            cardNetwork: isCredit ? cur.network : nil,
            balance: Double(cur.balance),
            creditLimit: isCredit ? Double(cur.limit) : nil,
            dueDay: isCredit ? cur.dueDay : nil,
            statementDay: isCredit ? cur.statementDay : nil,
            isDefault: cur.isDefault
        )
        Task {
            let ok = await onSave(edit)
            isSaving = false
            guard ok else { failMessage = "Gagal menyimpan perubahan"; return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            cur.name = trimmedName
            orig = cur
            toastText = "Perubahan disimpan"
            saved = true
            toast = true
            try? await Task.sleep(for: .seconds(1.4))
            saved = false
        }
    }

    private func archive() async {
        isBusy = true
        let ok = await onArchive()
        isBusy = false
        guard ok else { failMessage = "Gagal mengarsipkan dompet"; return }
        isArchived = true
        await showEnd(.archived)
    }

    private func delete() async {
        isBusy = true
        let ok = await onDelete()
        isBusy = false
        guard ok else { failMessage = "Gagal menghapus dompet"; return }
        await showEnd(.deleted)
    }

    private func showEnd(_ kind: End) async {
        sheet = nil
        nameFocused = false
        end = kind
        try? await Task.sleep(for: .seconds(0.28))
        endShown = true
    }

    private func unarchive(fromEnd: Bool) async {
        isBusy = true
        let ok = await onUnarchive()
        isBusy = false
        guard ok else { failMessage = "Gagal memulihkan dompet"; return }
        isArchived = false
        if fromEnd {
            endShown = false
        } else {
            toastText = "Dompet dipulihkan"
            toast = true
        }
    }
}

/// Bottom sheet sized to its content: grabber, title on the left, Selesai/Batal on the right.
private struct SheetFrame<Content: View>: View {
    let title: String
    let closeTitle: String
    let onClose: () -> Void
    @ViewBuilder var content: Content
    @State private var height: CGFloat = 320

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(title).font(.app(17, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
                Button(closeTitle, action: onClose)
                    .font(.app(17))
                    .foregroundStyle(Color.appPrimary)
            }
            .frame(height: 48)
            .padding(.horizontal, 24)
            .padding(.top, 14)
            content
        }
        .padding(.bottom, 12)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
        .foregroundStyle(Color.appText)
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(Color.appBackground)
    }
}

/// Full-width row that greys in while pressed (the design's :active fill).
private struct RowHighlightStyle: ButtonStyle {
    var tint = Color(light: 0xF7F7F8, dark: 0x1C1C1E)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? tint : .clear)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
