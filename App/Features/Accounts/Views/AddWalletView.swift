import SwiftUI

/// What the add-wallet flow hands back to be saved.
struct NewWallet {
    var name: String
    var type: Account.AccountType
    /// Saldo for cash, bank and e-wallet; the current bill (debt) for a card.
    var balance: Double
    var icon: String?
    /// Hex without #; nil keeps the brand colour.
    var color: String?
    var creditLimit: Double?
    var dueDate: String?
    var statementDay: Int?
    var cardNetwork: String?
    var isDefault: Bool
}

/// Tambah dompet (design 2a): the card is the form. Four type cards are stacked; the tapped one
/// rises to the top while the rest drop away, then every choice lands on that card: logo,
/// colour, a name typed straight onto it, and the amount from the same number pad as Tambah
/// Transaksi. Cards take extra steps for limit, current bill, cut-off and due day.
struct AddWalletView: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (NewWallet) async -> Bool

    init(onSave: @escaping (NewWallet) async -> Bool) {
        self.onSave = onSave
    }

    private enum Step: Int {
        case type, provider, balance, limit, bill, statement, due, done
    }

    // Wallet types, in stack order: key, label, colour, description.
    private static let types: [(Account.AccountType, String, String, String)] = [
        (.bank, "Bank", "0066AE", "Rekening tabungan atau giro"),
        (.ewallet, "E-wallet", "00AA44", "GoPay, OVO, DANA, dan lainnya"),
        (.cash, "Tunai", "616161", "Uang fisik di dompet atau celengan"),
        (.credit, "Kartu kredit", "1A1F71", "Lacak limit, tagihan, dan jatuh tempo"),
    ]
    static let swatches = ["616161", "16875A", "0066AE", "472B91", "C2410C", "9D174D"]
    /// Card issuers and the card colour each one gets.
    static let issuers: [(id: String, color: String)] = [
        ("bca", "1A1F71"), ("mandiri", "0B2545"), ("bni", "C2410C"), ("bri", "1F3A93"),
    ]
    static let networks: [(id: String, label: String)] = [
        ("visa", "Visa"), ("mastercard", "Mastercard"), ("jcb", "JCB"), ("amex", "Amex"), ("gpn", "GPN"),
    ]
    private static let cashNames = ["Dompet tunai", "Celengan", "Uang darurat", "Amplop belanja"]

    @State private var step: Step = .type
    @State private var type: Account.AccountType?
    /// Index into the provider list; -1 is "Lainnya".
    @State private var provider: Int?
    @State private var name = ""
    @State private var color: String?
    @State private var network: String?
    @State private var balance = 0
    @State private var limit = 0
    @State private var bill = 0
    @State private var statementDay: Int?
    @State private var dueDay: Int?
    @State private var isDefault = false
    @State private var isSaving = false
    @State private var saveFailed = false
    /// Brief pulses: the amount grows a touch on each key, the logo pops on each pick.
    @State private var bump = false
    @State private var pop = false
    @FocusState private var nameFocused: Bool

    private var isCredit: Bool { type == .credit }
    private var isCash: Bool { type == .cash }
    private var onCard: Bool { step != .type }
    private var isDone: Bool { step == .done }

    private var sequence: [Step] {
        switch type {
        case .credit: [.type, .provider, .limit, .bill, .statement, .due]
        case nil: [.type]
        default: [.type, .provider, .balance]
        }
    }

    private var stepIndex: Int { isDone ? sequence.count : sequence.firstIndex(of: step) ?? 0 }

    private var providers: [WalletIcon] {
        switch type {
        case .bank: WalletIcon.icons(for: .bank)
        case .ewallet: WalletIcon.icons(for: .ewallet)
        case .credit: Self.issuers.compactMap { issuer in WalletIcon.allIcons.first { $0.id == issuer.id } }
        default: []
        }
    }

    private var chosenProvider: WalletIcon? {
        guard let provider, provider >= 0, provider < providers.count else { return nil }
        return providers[provider]
    }

    private var typeColor: String { Self.types.first { $0.0 == type }?.2 ?? "616161" }

    /// Card colour now: the issuer's for cards, the brand's for banks and e-wallets, else the pick.
    private var cardColor: Color {
        if let chosenProvider {
            if isCredit, let issuer = Self.issuers.first(where: { $0.id == chosenProvider.id }) { return Color(hex: issuer.color) }
            return chosenProvider.color
        }
        return Color(hex: color ?? typeColor)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private var isValid: Bool {
        switch step {
        case .provider:
            if isCash { return !trimmedName.isEmpty }
            let picked = chosenProvider != nil || (provider == -1 && !trimmedName.isEmpty)
            return picked && (!isCredit || network != nil)
        case .limit: return limit > 0
        case .statement: return statementDay != nil
        case .due: return dueDay != nil
        default: return true
        }
    }

    /// The amount the card shows for this step.
    private var cardAmount: Int {
        switch step {
        case .limit, .provider where isCredit: limit
        default: isCredit ? max(limit - bill, 0) : balance
        }
    }

    private var cardLabel: String {
        if step == .limit || (isCredit && step == .provider) { return "Limit kredit" }
        return isCredit ? "Sisa limit" : "Saldo"
    }

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            let bottom = max(geo.safeAreaInsets.bottom, 12)
            ZStack(alignment: .top) {
                Color.appBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                    progress
                        .padding(.top, 4)
                    cards
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                    Spacer(minLength: 0)
                }

                panels(bottom: bottom)
                    .padding(.top, 44 + 3 + 4 + 16 + 216 + 28)
            }
        }
        .foregroundStyle(Color.appText)
        .onChange(of: step) { _, _ in nameFocused = false }
        .alert("Gagal menyimpan dompet", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Periksa koneksi lalu coba lagi. Nama dompet juga tidak boleh sama dengan dompet lain.")
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        ZStack {
            HStack {
                ZStack(alignment: .leading) {
                    Button("Batal") { dismiss() }
                        .font(.app(17))
                        .foregroundStyle(Color.appPrimary)
                        .opacity(onCard ? 0 : 1)
                        .allowsHitTesting(!onCard)
                    Button(action: back) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Color.appPrimary)
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("Kembali")
                    .opacity(onCard && !isDone ? 1 : 0)
                    .offset(x: onCard && !isDone ? 0 : -8)
                    .allowsHitTesting(onCard && !isDone)
                }
                .animation(.easeInOut(duration: 0.26), value: step)
                Spacer()
                Text(sequence.count > 1 ? "\(max(stepIndex, 1))/\(sequence.count - 1)" : "")
                    .font(.app(15))
                    .foregroundStyle(Color.appTextSecondary)
                    .monospacedDigit()
                    .opacity(onCard && !isDone ? 1 : 0)
            }
            .padding(.horizontal, 20)

            ZStack {
                ForEach([Step.type, .provider, .balance, .limit, .bill, .statement, .due, .done], id: \.self) { s in
                    Text(title(for: s))
                        .font(.app(17, weight: .semibold))
                        .lineLimit(1)
                        .opacity(s == step ? 1 : 0)
                        .offset(x: s == step ? 0 : s.rawValue < step.rawValue ? -24 : 24)
                }
            }
            .padding(.horizontal, 60)
            .animation(.settle(0.42), value: step)
        }
        .frame(height: 44)
    }

    private func title(for s: Step) -> String {
        switch s {
        case .type: "Tambah dompet"
        case .provider: isCash ? "Nama & warna" : isCredit ? "Bank & jenis kartu" : type == .bank ? "Pilih bank" : "Pilih e-wallet"
        case .balance: "Saldo awal"
        case .limit: "Limit kredit"
        case .bill: "Tagihan saat ini"
        case .statement: "Cetak tagihan"
        case .due: "Jatuh tempo"
        case .done: "Selesai"
        }
    }

    private var progress: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(sequence.count - 1, 2), id: \.self) { i in
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.appDivider)
                        Capsule().fill(Color.appPrimary)
                            .frame(width: i < stepIndex ? geo.size.width : 0)
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(.horizontal, 24)
        .opacity(onCard && !isDone ? 1 : 0)
        .animation(.settle(0.48), value: stepIndex)
        .animation(.easeInOut(duration: 0.3), value: onCard)
    }

    // MARK: Cards

    /// The four type cards: fanned 118pt apart to choose, then the chosen one alone at the top.
    private var cards: some View {
        ZStack(alignment: .top) {
            ForEach(Array(Self.types.enumerated()), id: \.offset) { i, entry in
                let (kind, label, hex, desc) = entry
                let selected = kind == type
                let chosenIndex = Self.types.firstIndex { $0.0 == type } ?? 0
                let offset: CGFloat = !onCard ? CGFloat(i) * 118 : selected ? (isDone ? 128 : 0) : 760 - CGFloat(i) * 20
                let delay = !onCard ? Double(i) * 0.045 : selected ? 0 : Double(abs(i - chosenIndex)) * 0.04

                ZStack {
                    CardSurface(color: selected && onCard ? cardColor : Color(hex: hex), symbol: kind.cardSymbol,
                                symbolTilted: selected && onCard)
                    typeFace(kind: kind, label: label, desc: desc)
                        .opacity(selected && onCard ? 0 : 1)
                        .offset(y: selected && onCard ? -10 : 0)
                    if selected {
                        formFace
                            .opacity(onCard ? 1 : 0)
                            .offset(y: onCard ? 0 : 10)
                            .animation(.settle(0.48).delay(0.16), value: onCard)
                            .allowsHitTesting(onCard && !isDone)
                    }
                }
                .frame(height: 216)
                .foregroundStyle(.white)
                .scaleEffect(!onCard ? 1 : selected ? (isDone ? 0.94 : 1) : 0.96, anchor: .top)
                .offset(y: offset)
                .opacity(!onCard || selected ? 1 : 0)
                .zIndex(selected && onCard ? 10 : Double(i))
                .animation(.settle(0.64).delay(delay), value: step)
                .animation(.easeInOut(duration: 0.48), value: cardColor)
                .onTapGesture { if !onCard { choose(kind) } }
                .accessibilityAddTraits(onCard ? [] : .isButton)
            }
        }
        .frame(height: 216, alignment: .top)
    }

    private func typeFace(kind: Account.AccountType, label: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 13)
                .fill(.white.opacity(0.18))
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: kind.cardSymbol).font(.system(size: 20)))
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.app(18, weight: .semibold)).tracking(-0.2)
                Text(desc).font(.app(13)).foregroundStyle(.white.opacity(0.8))
            }
            .padding(.top, 2)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .opacity(0.7)
                .padding(.top, 14)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    /// The chosen card filling in: logo, the name typed on it, then the amount and card details.
    private var formFace: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                CardLogoBox(logo: chosenProvider?.id, symbol: (type ?? .bank).cardSymbol, color: cardColor)
                    .scaleEffect(pop ? 0.6 : 1)
                    .animation(pop ? .easeOut(duration: 0.08) : .spring(duration: 0.46, bounce: 0.55), value: pop)
                TextField("", text: $name, prompt: Text("Ketik nama dompet").foregroundStyle(.white.opacity(0.6)))
                    .font(.app(17, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(.white)
                    .tint(.white)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onChange(of: name) { _, value in if value.count > 28 { name = String(value.prefix(28)) } }
                    .padding(.trailing, isDone ? 34 : 0)
            }
            .overlay(alignment: .trailing) {
                Circle()
                    .fill(.white)
                    .frame(width: 28, height: 28)
                    .overlay(Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(cardColor))
                    .scaleEffect(isDone ? 1 : 0)
                    .animation(.spring(duration: 0.52, bounce: 0.6).delay(0.38), value: isDone)
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                if isCredit && limit > 0 && [.bill, .statement, .due, .done].contains(step) {
                    CardUsageBar(usedText: "Rp" + Self.digits(bill), share: Double(bill) / Double(limit))
                        .transition(.opacity)
                }
                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cardLabel).font(.app(12)).foregroundStyle(.white.opacity(0.8))
                        Text("Rp" + Self.digits(cardAmount))
                            .font(.app(32))
                            .tracking(-0.8)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .opacity(cardAmount > 0 ? 1 : 0.55)
                            .scaleEffect(bump ? 1.04 : 1, anchor: .bottomLeading)
                            .animation(.easeOut(duration: 0.14), value: bump)
                            .contentTransition(.numericText())
                    }
                    Spacer(minLength: 0)
                    if isCredit {
                        VStack(alignment: .trailing, spacing: 2) {
                            CardNetworkBadge(network: network ?? "visa")
                                .opacity(network == nil ? 0 : 1)
                                .scaleEffect(network == nil ? 0.8 : 1, anchor: .trailing)
                                .offset(y: network == nil ? -6 : 0)
                                .animation(.spring(duration: 0.46, bounce: 0.5), value: network)
                                .padding(.bottom, 6)
                            Text("Jatuh tempo").font(.app(12)).foregroundStyle(.white.opacity(0.8))
                            Text(dueDay.map { "Tgl \($0)" } ?? "—")
                                .font(.app(15, weight: .semibold))
                                .monospacedDigit()
                        }
                        .padding(.bottom, 3)
                    }
                }
            }
            .animation(.settle(0.4), value: step)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    // MARK: Panels

    /// Everything under the card for the current step; each fades and slides up in place.
    private func panels(bottom: CGFloat) -> some View {
        ZStack(alignment: .top) {
            layer(step == .provider && !isCash) { providerPanel }
            layer(step == .provider && isCash) { cashPanel }
            layer([.balance, .limit, .bill].contains(step)) { numberPanel(bottom: bottom) }
            layer(step == .statement) { dayPanel(caption: "Tanggal cetak tagihan tiap bulan",
                                                note: "Belanja setelah tanggal ini masuk ke tagihan bulan berikutnya.",
                                                selection: $statementDay) }
            layer(step == .due) { dayPanel(caption: "Tanggal jatuh tempo tiap bulan",
                                          note: "Tagihan dicatat sebagai utang dan tidak mengurangi total saldo.",
                                          selection: $dueDay) }
            doneTexts
                .padding(.top, 174)
                .opacity(isDone ? 1 : 0)
                .offset(y: isDone ? 0 : 24)
                .animation(.settle(0.52).delay(isDone ? 0.3 : 0), value: isDone)

            bottomButtons(bottom: bottom)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func layer<Content: View>(_ on: Bool, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(on ? 1 : 0)
            .offset(y: on ? 0 : 24)
            .allowsHitTesting(on)
            .animation(.settle(0.46), value: on)
    }

    private var providerPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 4), spacing: 18) {
                ForEach(Array(providers.enumerated()), id: \.element.id) { j, icon in
                    providerCell(name: icon.name, selected: provider == j, ring: icon.color, index: j) {
                        Image(icon.id).resizable().scaledToFit().frame(width: 42, height: 24)
                    } tap: { pickProvider(j) }
                }
                otherCell(index: providers.count)
            }
            .padding(.horizontal, 16)

            if isCredit {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Jenis kartu").font(.app(13)).foregroundStyle(Color.appTextSecondary)
                    FlowChips(spacing: 8) {
                        ForEach(Self.networks, id: \.id) { net in
                            networkChip(net.id, label: net.label)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 26)
                .appear(step == .provider, delay: 0.16 + Double(providers.count) * 0.045 + 0.06)
            }

            if provider == -1 {
                swatchRow(caption: "Warna kartu · ketik nama langsung di kartu")
                    .padding(.horizontal, 24)
                    .padding(.top, 22)
                    .transition(.opacity.combined(with: .offset(y: 10)))
            }
        }
        .animation(.settle(0.42), value: provider)
    }

    private func providerCell<Logo: View>(name: String, selected: Bool, ring: Color, index: Int,
                                          @ViewBuilder logo: () -> Logo, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            VStack(spacing: 8) {
                Circle()
                    .fill(.white)
                    .frame(width: 62, height: 62)
                    .overlay(logo())
                    .overlay(Circle().strokeBorder(Color(light: 0xE5E5EA, dark: 0x3A3A3C), lineWidth: selected ? 0 : 1))
                    .background(Circle().stroke(ring, lineWidth: selected ? 2 : 0).padding(-3))
                    .scaleEffect(selected ? 1.06 : 1)
                    .animation(.spring(duration: 0.42, bounce: 0.5), value: selected)
                Text(name)
                    .font(.app(13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(Color.appText)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .appear(step == .provider, delay: 0.12 + Double(index) * 0.045)
    }

    private func otherCell(index: Int) -> some View {
        let on = provider == -1
        return Button { pickOther() } label: {
            VStack(spacing: 8) {
                Circle()
                    .strokeBorder(on ? Color.appPrimary : Color.appBorder, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: 62, height: 62)
                    .overlay(Image(systemName: "plus").font(.system(size: 20)).foregroundStyle(on ? Color.appPrimary : Color.appTextTertiary))
                Text("Lainnya")
                    .font(.app(13, weight: on ? .semibold : .regular))
                    .foregroundStyle(Color.appText)
            }
        }
        .buttonStyle(.plain)
        .appear(step == .provider, delay: 0.12 + Double(index) * 0.045)
    }

    private func networkChip(_ id: String, label: String) -> some View {
        let on = network == id
        return Button {
            network = id
            if let chosenProvider { name = "\(chosenProvider.name) \(label)" }
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: "F7F7F8"))
                    .frame(width: 44, height: 30)
                    .overlay {
                        if id == "gpn" {
                            Text("GPN").font(.app(12, weight: .heavy)).foregroundStyle(Color(hex: "C8102E"))
                        } else {
                            Image(id).resizable().scaledToFit().frame(width: 34, height: 20)
                        }
                    }
                Text(label).font(.app(14, weight: on ? .semibold : .medium))
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .frame(height: 44)
            .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(on ? Color.appPrimary : Color(light: 0xE5E5EA, dark: 0x3A3A3C), lineWidth: on ? 2 : 1))
            .scaleEffect(on ? 1.04 : 1)
            .animation(.spring(duration: 0.38, bounce: 0.5), value: on)
        }
        .buttonStyle(.plain)
    }

    private var cashPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Untuk apa uang tunai ini?").font(.app(13)).foregroundStyle(Color.appTextSecondary)
            FlowChips(spacing: 8) {
                ForEach(Array(Self.cashNames.enumerated()), id: \.offset) { j, label in
                    let on = name == label
                    Button { name = label } label: {
                        Text(label)
                            .font(.app(15, weight: .medium))
                            .foregroundStyle(on ? .white : Color.appText)
                            .padding(.horizontal, 16)
                            .frame(height: 38)
                            .background(on ? Color.appPrimary : Color.appBackground, in: Capsule())
                            .overlay(Capsule().strokeBorder(on ? Color.appPrimary : Color(light: 0xE5E5EA, dark: 0x3A3A3C)))
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.22), value: on)
                    .appear(step == .provider && isCash, delay: 0.12 + Double(j) * 0.045)
                }
            }
            swatchRow(caption: "Warna kartu").padding(.top, 14)
        }
        .padding(.horizontal, 24)
    }

    private func swatchRow(caption: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(caption).font(.app(13)).foregroundStyle(Color.appTextSecondary)
            HStack(spacing: 14) {
                ForEach(Self.swatches, id: \.self) { hex in
                    let on = (color ?? typeColor) == hex
                    Button { color = hex } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 36, height: 36)
                            .background(Circle().stroke(Color(hex: hex), lineWidth: on ? 2 : 0).padding(-4))
                            .scaleEffect(on ? 1.08 : 1)
                            .animation(.spring(duration: 0.38, bounce: 0.5), value: on)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Warna \(hex)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    private func numberPanel(bottom: CGFloat) -> some View {
        let quick: [Int] = step == .balance ? [100_000, 500_000, 1_000_000, 5_000_000]
            : step == .limit ? [5_000_000, 10_000_000, 20_000_000, 50_000_000] : []
        return VStack(alignment: .leading, spacing: 14) {
            if !quick.isEmpty {
                HStack(spacing: 8) {
                    ForEach(quick, id: \.self) { value in
                        Button { setAmount(value) } label: {
                            Text(value.formattedShort)
                                .font(.app(14, weight: .medium))
                                .monospacedDigit()
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background(Color.appFill, in: Capsule())
                        }
                        .buttonStyle(PressScaleStyle())
                    }
                }
            }
            if step == .balance {
                Toggle(isOn: $isDefault) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Jadikan dompet utama").font(.app(16))
                        Text("Dipilih otomatis saat mencatat transaksi")
                            .font(.app(13))
                            .foregroundStyle(Color.appTextSecondary)
                    }
                }
                .tint(Color.appPrimary)
                .padding(.top, 2)
            }
            if step == .limit || step == .bill {
                Text(step == .limit ? "Batas total yang diberikan bank untuk kartu ini."
                     : bill > limit ? "Tagihan melebihi limit kredit." : "Isi 0 jika belum ada tagihan bulan ini.")
                    .font(.app(14))
                    .foregroundStyle(step == .bill && bill > limit ? Color.appError : Color.appTextSecondary)
                    .lineSpacing(3)
            }
            Spacer(minLength: 0)
            GeometryReader { geo in
                let side = (geo.size.width - 6) / 4
                HStack(spacing: 6) {
                    NumberPadKeys(onPress: press)
                        .frame(width: geo.size.width - side - 6)
                    Button(action: next) {
                        VStack(spacing: 6) {
                            if isSaving {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: step == .balance ? "checkmark" : "arrow.right")
                                    .font(.system(size: 24, weight: .bold))
                            }
                            Text(step == .balance ? "Simpan" : "Lanjut").font(.app(14, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(isValid ? Color.appPrimary : Color(light: 0xC7C7CC, dark: 0x48484A), in: RoundedRectangle(cornerRadius: 14))
                        .animation(.easeInOut(duration: 0.3), value: isValid)
                    }
                    .buttonStyle(PressScaleStyle())
                    .frame(width: side)
                }
            }
            .frame(height: 52 * 4 + 6 * 3)
            .padding(.horizontal, -12)
            .padding(.bottom, bottom)
        }
        .padding(.horizontal, 24)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func dayPanel(caption: String, note: String, selection: Binding<Int?>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(caption).font(.app(13)).foregroundStyle(Color.appTextSecondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(1...31, id: \.self) { day in
                    let on = selection.wrappedValue == day
                    Button { selection.wrappedValue = day } label: {
                        Text("\(day)")
                            .font(.app(16, weight: on ? .semibold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(on ? .white : Color.appText)
                            .frame(width: 38, height: 38)
                            .background(on ? Color.appPrimary : .clear, in: Circle())
                            .scaleEffect(on ? 1.06 : 1)
                            .animation(.spring(duration: 0.38, bounce: 0.5), value: on)
                            .frame(height: 42)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 10)
            Text(note)
                .font(.app(13))
                .foregroundStyle(Color.appTextSecondary)
                .lineSpacing(3)
                .padding(.top, 10)
        }
        .padding(.horizontal, 24)
    }

    private var doneTexts: some View {
        VStack(spacing: 6) {
            Text("Dompet ditambahkan").font(.app(22, weight: .semibold)).tracking(-0.3)
            Text((trimmedName.isEmpty ? "Dompet baru" : trimmedName)
                 + (isCredit ? " dengan limit Rp\(Self.digits(limit)) siap dipakai."
                    : " dengan saldo Rp\(Self.digits(balance)) sudah masuk ke total saldo."))
                .font(.app(15))
                .foregroundStyle(Color.appTextSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }

    /// Lanjut on the provider step, Simpan dompet on the last card step, the two finish buttons.
    private func bottomButtons(bottom: CGFloat) -> some View {
        VStack {
            Spacer()
            ZStack(alignment: .bottom) {
                primaryButton("Lanjut", icon: "arrow.right", trailingIcon: true, enabled: isValid, action: next)
                    .layerShown([.provider, .statement].contains(step))
                primaryButton("Simpan dompet", icon: "checkmark", trailingIcon: false, enabled: isValid, action: next)
                    .layerShown(step == .due)
                VStack(spacing: 10) {
                    primaryButton("Lihat dompet", icon: nil, trailingIcon: false, enabled: true) { dismiss() }
                    Button(action: again) {
                        Label("Tambah dompet lain", systemImage: "plus")
                            .font(.app(17, weight: .semibold))
                            .foregroundStyle(Color.appText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.appFill, in: Capsule())
                    }
                    .buttonStyle(PressScaleStyle())
                }
                .opacity(isDone ? 1 : 0)
                .offset(y: isDone ? 0 : 24)
                .allowsHitTesting(isDone)
                .animation(.settle(0.52).delay(isDone ? 0.42 : 0), value: isDone)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, bottom)
        }
    }

    private func primaryButton(_ title: String, icon: String?, trailingIcon: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isSaving && title == "Simpan dompet" {
                    ProgressView().tint(.white)
                } else if let icon, !trailingIcon {
                    Image(systemName: icon).font(.system(size: 15, weight: .bold))
                }
                Text(title).font(.app(17, weight: .semibold))
                if let icon, trailingIcon {
                    Image(systemName: icon).font(.system(size: 15, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(enabled ? Color.appPrimary : Color(light: 0xC7C7CC, dark: 0x48484A), in: Capsule())
            .animation(.easeInOut(duration: 0.26), value: enabled)
        }
        .buttonStyle(PressScaleStyle())
    }

    // MARK: Actions

    private func choose(_ kind: Account.AccountType) {
        type = kind
        provider = kind == .cash ? -1 : nil
        name = kind == .cash ? "Dompet tunai" : ""
        color = kind == .cash ? "616161" : nil
        network = nil
        balance = 0; limit = 0; bill = 0
        statementDay = nil; dueDay = nil; isDefault = false
        step = .provider
    }

    private func pickProvider(_ j: Int) {
        provider = j
        let brand = providers[j]
        if isCredit {
            name = network.flatMap { net in Self.networks.first { $0.id == net }?.label }.map { "\(brand.name) \($0)" }
                ?? "Kartu Kredit \(brand.name)"
        } else {
            name = brand.name
        }
        pulsePop()
    }

    private func pickOther() {
        provider = -1
        name = ""
        if color == nil || color == "616161" { color = "16875A" }
        pulsePop()
        nameFocused = true
    }

    private func press(_ key: String) {
        guard let value = NumberPad.apply(key, to: currentAmount) else { return }
        setAmount(value)
    }

    private var currentAmount: Int {
        switch step {
        case .limit: limit
        case .bill: bill
        default: balance
        }
    }

    private func setAmount(_ value: Int) {
        switch step {
        case .limit: limit = value
        case .bill: bill = value
        default: balance = value
        }
        pulseBump()
    }

    /// The amount's grow-on-keypress.
    private func pulseBump() {
        bump = true
        Task { try? await Task.sleep(for: .seconds(0.11)); bump = false }
    }

    /// The logo's pop when a provider is picked.
    private func pulsePop() {
        pop = true
        Task { try? await Task.sleep(for: .seconds(0.09)); pop = false }
    }

    private func back() {
        guard stepIndex > 0, !isDone else { return }
        step = sequence[stepIndex - 1]
    }

    private func next() {
        guard isValid, !isSaving else { return }
        let i = stepIndex + 1
        if i < sequence.count {
            step = sequence[i]
        } else {
            save()
        }
    }

    private func save() {
        guard let type else { return }
        isSaving = true
        let wallet = NewWallet(
            name: trimmedName.isEmpty ? "Dompet baru" : trimmedName,
            type: type,
            balance: Double(isCredit ? bill : balance),
            icon: isCash ? "cash" : chosenProvider?.id,
            // Brand colours come with the logo; cards and "Lainnya" keep the colour on the card.
            color: isCredit ? (chosenProvider.flatMap { p in Self.issuers.first { $0.id == p.id }?.color } ?? color)
                : chosenProvider == nil ? (color ?? typeColor) : nil,
            creditLimit: isCredit ? Double(limit) : nil,
            dueDate: isCredit ? dueDay.map(String.init) : nil,
            statementDay: isCredit ? statementDay : nil,
            cardNetwork: isCredit ? network : nil,
            isDefault: !isCredit && isDefault
        )
        Task {
            let ok = await onSave(wallet)
            isSaving = false
            if ok {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                step = .done
            } else {
                saveFailed = true
            }
        }
    }

    private func again() {
        type = nil
        provider = nil
        name = ""
        step = .type
    }

    static func digits(_ value: Int) -> String {
        Double(value).formattedAsDigits()
    }
}

private extension Int {
    /// "100rb", "1 jt", "50 jt" for the quick amount chips.
    var formattedShort: String {
        self >= 1_000_000 ? "\(self / 1_000_000) jt" : "\(self / 1000)rb"
    }
}

private extension View {
    /// Fades and lifts in with a stagger while `shown`.
    func appear(_ shown: Bool, delay: Double) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .animation(.settle(0.46).delay(shown ? delay : 0), value: shown)
    }

    func layerShown(_ on: Bool) -> some View {
        opacity(on ? 1 : 0)
            .offset(y: on ? 0 : 24)
            .allowsHitTesting(on)
            .animation(.settle(0.46), value: on)
    }
}

/// Chips that wrap onto new lines.
private struct FlowChips: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
