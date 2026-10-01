import SwiftUI

/// The sheet shell for picking a wallet or category (design "Pilih Dompet Kategori" 6): title and
/// Selesai, a search field, then scrolling content. Opens half-height; pull up for the full list.
struct SelectionSheet<Content: View>: View {
    let title: String
    let searchPrompt: String
    @Binding var query: String
    let onDone: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.app(17, weight: .semibold))
                Spacer()
                Button("Selesai", action: onDone)
                    .font(.app(17, weight: .semibold))
                    .foregroundStyle(Color.appPrimary)
            }
            .frame(height: 48)
            .padding(.horizontal, 24)
            .padding(.top, 14)

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
            .background(Color.appFill, in: RoundedRectangle(cornerRadius: 10))
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
        .presentationDetents([.height(452), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(Color.appBackground)
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

    @State private var query = ""
    @AppStorage("isBalanceVisible") private var isBalanceVisible = true

    private static let groups: [(Account.AccountType, String)] = [
        (.bank, "Bank"), (.ewallet, "E-wallet"), (.cash, "Tunai"), (.credit, "Kartu kredit"),
    ]

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
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach(recent) { bigTile($0) }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
                ForEach(Self.groups, id: \.0) { type, label in
                    let items = accounts.filter { $0.type == type }
                    if !items.isEmpty {
                        sectionTitle(L(label), top: 18)
                        smallGrid(items).padding(.top, 8)
                    }
                }
            }
        }
    }

    private func smallGrid(_ items: [Account]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(items) { smallTile($0) }
        }
        .padding(.horizontal, 20)
    }

    private func logo(_ account: Account, width: CGFloat, height: CGFloat) -> some View {
        Group {
            if let name = Self.logoName(account) {
                Image(name).resizable().scaledToFit().frame(maxWidth: width, maxHeight: height)
            } else {
                Image(systemName: "banknote.fill").font(.system(size: height + 2)).foregroundStyle(Color.appPrimary)
            }
        }
    }

    static func logoName(_ account: Account) -> String? {
        if account.isCreditCard, let network = account.networkId, network != "gpn" { return network }
        return account.brandLogo
    }

    private func balance(_ account: Account) -> String {
        guard isBalanceVisible else { return "Rp" + hiddenAmount }
        return account.isCreditCard
            ? L("Sisa Rp%@", (account.availableCredit ?? 0).formattedAsDigits())
            : "Rp" + account.balance.formattedAsDigits()
    }

    private func check(_ isOn: Bool, size: CGFloat) -> some View {
        Image(systemName: "checkmark")
            .font(.system(size: size * 0.55, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.appPrimary, in: Circle())
            .scaleEffect(isOn ? 1 : 0.001)
            .animation(.spring(duration: 0.38, bounce: 0.5), value: isOn)
    }

    private func bigTile(_ account: Account) -> some View {
        let isOn = account.id == selectedId
        return Button { onPick(account) } label: {
            VStack(alignment: .leading, spacing: 0) {
                logo(account, width: 52, height: 20).frame(height: 22, alignment: .leading)
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    Text(account.name).font(.app(14, weight: .semibold)).lineLimit(1)
                    if account.id == mainId { mainBadge }
                }
                Text(balance(account))
                    .font(.app(12))
                    .foregroundStyle(Color.appTextSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .padding(.top, 1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 92)
            .background(isOn ? Color.appBackground : Color.appFill, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.appPrimary, lineWidth: isOn ? 2 : 0) }
            .overlay(alignment: .topTrailing) { check(isOn, size: 20).padding(8) }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(account.name + (account.id == mainId ? L(", utama") : ""))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func smallTile(_ account: Account) -> some View {
        let isOn = account.id == selectedId
        return Button { onPick(account) } label: {
            VStack(alignment: .leading, spacing: 0) {
                logo(account, width: 44, height: 16).frame(height: 18, alignment: .leading)
                Spacer(minLength: 0)
                Text(account.name).font(.app(13, weight: .semibold)).lineLimit(1)
                Text(balance(account))
                    .font(.app(11.5))
                    .foregroundStyle(Color.appTextSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 72)
            .background(isOn ? Color.appBackground : Color.appFill, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.appPrimary, lineWidth: isOn ? 2 : 0) }
            .overlay(alignment: .topTrailing) { check(isOn, size: 18).padding(7) }
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
        return Button { onPick(category) } label: {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: category.icon ?? "tag")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.appBody)
                Spacer(minLength: 0)
                Text(category.name)
                    .font(.app(13, weight: .semibold))
                    .foregroundStyle(Color.appText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 84)
            .background(isOn ? Color.appBackground : Color.appFill, in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Color.appPrimary, lineWidth: isOn ? 2 : 0) }
            .overlay(alignment: .topTrailing) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.appPrimary, in: Circle())
                    .scaleEffect(isOn ? 1 : 0.001)
                    .animation(.spring(duration: 0.38, bounce: 0.5), value: isOn)
                    .padding(9)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
