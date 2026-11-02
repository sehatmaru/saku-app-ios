import SwiftUI

/// The dark sheet is itself 1C1C1E, so tiles and the search field need a lighter fill to show there.
private let pickerFill = Color(light: 0xF2F2F4, dark: 0x2C2C2E)

/// The sheet shell for picking a wallet or category (design "Pilih Dompet Kategori" 6): title,
/// a search field, then scrolling content. Opens half-height; pull up for the full list.
struct SelectionSheet<Content: View>: View {
    let title: String
    let searchPrompt: String
    @Binding var query: String
    let onDone: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Text(title).font(.app(22, weight: .bold)).tracking(-0.3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 10)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 16))
                TextField("", text: $query, prompt: Text(searchPrompt).foregroundStyle(Color.appTextTertiary))
                    .font(.app(16))
                    .foregroundStyle(Color.appText)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel(L("Hapus pencarian"))
                }
            }
            .foregroundStyle(Color.appTextSecondary)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(pickerFill, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 20)
            .padding(.top, 2)
            .padding(.bottom, 4)

            ScrollView {
                content
                    .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(Color.appText)
        .presentationDetents([.medium, .large])

        .background(Color.appBackground)
    }
}

/// A picked tile fills with its own colour, with a white tick, a coloured glow and a small lift, as on the onboarding wallet step.
private extension View {
    func pickedTile(_ isOn: Bool, color: Color, radius: CGFloat, base: Color = pickerFill) -> some View {
        background(isOn ? color : base, in: RoundedRectangle(cornerRadius: radius))
            .overlay(alignment: .topTrailing) {
                Circle().fill(.white)
                    .frame(width: 20, height: 20)
                    .overlay { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(color.isLight ? Color(hex: "1C1C1E") : color) }
                    .padding(8)
                    .opacity(isOn ? 1 : 0)
                    .scaleEffect(isOn ? 1 : 0.3)
                    .animation(.timingCurve(0.3, 1.5, 0.5, 1, duration: 0.32), value: isOn)
            }
            .shadow(color: isOn ? color.opacity(0.32) : .clear, radius: 9, y: 8)
            .offset(y: isOn ? -2 : 0)
            .animation(.timingCurve(0.3, 1.3, 0.5, 1, duration: 0.32), value: isOn)
    }
}

private func sectionTitle(_ text: String, top: CGFloat) -> some View {
    Text(text)
        .font(.app(13, weight: .semibold))
        .foregroundStyle(Color(light: 0x8E8E93, dark: 0x8E8E93))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, top)
}

private func emptyResult(_ text: String) -> some View {
    Text(text)
        .font(.app(15))
        .foregroundStyle(Color.appTextSecondary)
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
}

// MARK: - Wallets

/// Wallet sheet: the last three used as big tiles, then everything grouped Bank / E-wallet / Tunai /
/// Kartu kredit. The picked one gets a ring and a tick wherever it shows; the main wallet says "Utama".
struct WalletPickerSheet: View {
    let title: String
    let accounts: [Account]
    let selectedId: String?
    let mainId: String?
    /// Most recent first; only the first three show.
    let recentIds: [String]
    let onDone: () -> Void
    let onPick: (Account) -> Void
    /// Wallets shown but not pickable, with the reason shown where the balance would be.
    var disabled: [String: String] = [:]
    /// A line under the Kas or Investasi group, e.g. why a wallet is locked.
    var kasNote: String?
    var investmentNote: String?
    /// A card under the list that points to another action.
    var footer: Footer?

    struct Footer {
        let text: String
        let actionTitle: String
        let action: () -> Void
    }

    @State private var query = ""
    @AppStorage("isBalanceVisible") private var isBalanceVisible = true

    /// With an investment wallet in the list, bank, e-wallet and cash fold into "Kas" next to "Investasi".
    private var groups: [(title: String, items: [Account], note: String?)] {
        if accounts.contains(where: \.isInvestment) {
            return [(L("Kas"), accounts.filter { [.bank, .ewallet, .cash].contains($0.type) }, kasNote),
                    (L("Investasi"), accounts.filter(\.isInvestment), investmentNote),
                    (L("Kartu kredit"), accounts.filter(\.isCreditCard), nil)]
        }
        let all: [(Account.AccountType, String)] = [(.bank, L("Bank")), (.ewallet, L("E-wallet")), (.cash, L("Tunai")), (.credit, L("Kartu kredit"))]
        return all.map { type, title in (title, accounts.filter { $0.type == type }, nil) }
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var recent: [Account] { recentIds.prefix(3).compactMap { id in accounts.first { $0.id == id } } }
    private var results: [Account] { accounts.filter { $0.name.localizedCaseInsensitiveContains(trimmed) } }

    var body: some View {
        SelectionSheet(title: title, searchPrompt: L("Cari dompet"), query: $query, onDone: onDone) {
            if !trimmed.isEmpty {
                if results.isEmpty {
                    emptyResult(L("Tidak ada dompet “%@”", trimmed))
                } else {
                    smallGrid(results).padding(.top, 8)
                }
            } else {
                if !recent.isEmpty {
                    sectionTitle(L("Terakhir dipakai"), top: 12)
                    smallGrid(recent).padding(.top, 8)
                }
                ForEach(groups, id: \.title) { group in
                    if !group.items.isEmpty {
                        sectionTitle(group.title, top: 18)
                        smallGrid(group.items).padding(.top, 8)
                        if let note = group.note {
                            Text(note)
                                .font(.app(13))
                                .foregroundStyle(Color.appTextSecondary)
                                .lineSpacing(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 24)
                                .padding(.top, 8)
                        }
                    }
                }
                if let footer { footerCard(footer) }
            }
        }
    }

    private func footerCard(_ footer: Footer) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 18))
                .foregroundStyle(Color.appInvestment)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 8) {
                Text(footer.text).font(.app(14)).lineSpacing(2)
                Button(action: footer.action) {
                    HStack(spacing: 4) {
                        Text(footer.actionTitle).font(.app(14, weight: .semibold))
                        Image(systemName: "arrow.right").font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(Color.appPrimary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private func smallGrid(_ items: [Account]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(items) { smallTile($0) }
        }
        .padding(.horizontal, 20)
    }

    static func logoName(_ account: Account) -> String? {
        if account.isCreditCard, let network = account.networkId, network != "gpn" { return network }
        return account.brandLogo
    }

    private func balance(_ account: Account) -> String {
        if let reason = disabled[account.id] { return reason }
        guard isBalanceVisible else { return "Rp" + hiddenAmount }
        return account.isCreditCard
            ? L("Sisa Rp%@", (account.availableCredit ?? 0).formattedAsDigits())
            : "Rp" + account.balance.formattedAsDigits()
    }

    private func assetTag() -> some View {
        Text("ASET")
            .font(.app(9, weight: .heavy))
            .tracking(0.3)
            .foregroundStyle(Color.appInvestment)
            .padding(.horizontal, 5)
            .frame(height: 16)
            .background(Color.appInvestmentTint, in: Capsule())
    }

    private func smallTile(_ account: Account) -> some View {
        let isOn = account.id == selectedId
        let isDisabled = disabled[account.id] != nil
        let color = account.walletColor
        let ink: Color = isOn ? (color.isLight ? Color(hex: "1C1C1E") : .white) : Color.appText
        return Button { if !isDisabled { onPick(account) } } label: {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if isOn {
                        RoundedRectangle(cornerRadius: 4).fill(ink.opacity(0.35)).frame(width: 27, height: 18)
                    } else {
                        WalletSwatch(account: account, width: 27, height: 18)
                    }
                }
                .frame(height: 18, alignment: .leading)
                Spacer(minLength: 0)
                Text(account.name).font(.app(13, weight: .semibold)).lineLimit(1)
                Text(balance(account))
                    .font(.app(11.5))
                    .foregroundStyle(isOn ? ink.opacity(0.85) : Color.appTextSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 72)
            .pickedTile(isOn, color: color, radius: 12)
            .overlay(alignment: .topTrailing) {
                if account.isInvestment && !isOn { assetTag().padding(7).padding(.trailing, 0) }
            }
            .opacity(isDisabled ? 0.45 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(account.name + (account.id == mainId ? L(", utama") : ""))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var mainBadge: some View {
        Text("Utama")
            .font(.app(10, weight: .semibold))
            .foregroundStyle(Color.appPrimary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.appPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            .fixedSize()
    }
}

// MARK: - Categories

/// Category sheet: full-colour tiles in the category's own colour, "Sering dipakai" first, the rest
/// A–Z. The picked one is ringed and ticked wherever it shows.
struct CategoryPickerSheet: View {
    let title: String
    let categories: [Category]
    let selectedId: String?
    /// Most used first; only the first three show.
    let frequentIds: [String]
    let onDone: () -> Void
    let onPick: (Category) -> Void

    @State private var query = ""

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var frequent: [Category] { frequentIds.prefix(3).compactMap { id in categories.first { $0.id == id } } }
    private var rest: [Category] {
        let top = Set(frequent.map(\.id))
        return categories.filter { !top.contains($0.id) }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
    private var results: [Category] {
        categories.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        SelectionSheet(title: title, searchPrompt: L("Cari kategori"), query: $query, onDone: onDone) {
            if !trimmed.isEmpty {
                if results.isEmpty {
                    emptyResult(L("Tidak ada kategori “%@”", trimmed))
                } else {
                    grid(results).padding(.top, 8)
                }
            } else {
                if !frequent.isEmpty {
                    sectionTitle(L("Sering dipakai"), top: 14)
                    grid(frequent).padding(.top, 8)
                }
                sectionTitle(L("Semua kategori"), top: 14)
                grid(rest).padding(.top, 8)
            }
        }
    }

    private func grid(_ items: [Category]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(items) { tile($0) }
        }
        .padding(.horizontal, 20)
    }

    private func tile(_ category: Category) -> some View {
        let isOn = category.id == selectedId
        let color = category.color.map { Color(hex: $0) } ?? Color.appPrimary
        let ink: Color = isOn ? (color.isLight ? Color(hex: "1C1C1E") : .white) : Color.appText
        return Button { onPick(category) } label: {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: category.icon ?? "tag")
                    .font(.system(size: 22))
                    .foregroundStyle(isOn ? ink : color)
                Spacer(minLength: 0)
                Text(category.name)
                    .font(.app(13, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 84)
            .pickedTile(isOn, color: color, radius: 16)
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
