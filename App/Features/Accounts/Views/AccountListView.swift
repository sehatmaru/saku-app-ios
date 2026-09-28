import SwiftUI

/// Dompet: one card stack per wallet type (design 6c). Tap any card to open its detail like
/// design 5a (the card lifts to the top, every other card drops into a pile at the bottom);
/// tap a group title to fan its stack out or close it.
struct AccountListView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel: AccountListViewModel

    init(viewModel: AccountListViewModel = AccountListViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    @AppStorage("isBalanceVisible") private var isBalanceVisibleStorage = true
    @State private var isBalanceVisible = true
    @State private var showAddWallet = false
    @State private var accountTransactions: [String: [Transaction]] = [:]
    @State private var categories: [Category] = []
    @State private var cachedUserId: String?
    @State private var openGroups: Set<Account.AccountType> = []
    @State private var path = NavigationPath()
    /// The detail overlay is on screen (also while cards fly back into their stacks).
    @State private var isOverlayOn = false
    /// Card lifted to the top; nil while the overlay opens or closes.
    @State private var selectedID: String?
    /// Last opened card, keeps the detail content filled while it fades out.
    @State private var lastSelectedID: String?
    @State private var cardTops = CardTops()
    @State private var transferFrom: Account?

    /// Card positions kept outside view state so scrolling doesn't re-render the screen.
    private final class CardTops {
        var values: [String: CGFloat] = [:]
    }

    private static let space = "dompet"
    // Detail layout from design 5a, in points.
    private let detailCardTop: CGFloat = 58
    /// How much of the bottom pile peeks above the tab bar.
    private let pileVisible: CGFloat = 40
    private let pileStep: CGFloat = 8
    private let cardAnimation = Animation.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.54)

    private let cardHeight: CGFloat = 216
    /// Visible strip of a card covered by the next one in a closed stack.
    private let stripHeight: CGFloat = 56

    private struct WalletGroup: Identifiable {
        let type: Account.AccountType
        let title: String
        let accounts: [Account]
        var id: Account.AccountType { type }
    }

    private var groups: [WalletGroup] {
        let active = viewModel.accounts.filter(\.isActive)
        let titled: [(Account.AccountType, String)] = [(.bank, "Bank"), (.ewallet, "E-Wallet"), (.cash, "Cash"), (.credit, "Kartu kredit")]
        return titled.compactMap { type, title in
            let accounts = active.filter { $0.type == type }.sorted { $0.isDefault && !$1.isDefault }
            return accounts.isEmpty ? nil : WalletGroup(type: type, title: title, accounts: accounts)
        }
    }

    private var archivedAccounts: [Account] {
        viewModel.accounts.filter { !$0.isActive }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    if let error = viewModel.errorMessage, !viewModel.hasLoadedOnce {
                        errorStateView(message: error)
                            .padding(24)
                    } else if !viewModel.hasLoadedOnce {
                        skeletonContent
                    } else {
                        if let error = viewModel.errorMessage {
                            ErrorBanner(message: error).padding(.horizontal, 24).padding(.top, 16)
                        }
                        summary
                        if groups.isEmpty {
                            emptyState.padding(.top, 48)
                        }
                        ForEach(groups) { group in
                            groupSection(group)
                        }
                        footerRows
                    }
                }
                .padding(.bottom, 24)
                .animation(.easeInOut(duration: 0.3), value: viewModel.hasLoadedOnce)
            }
            .tracksTabBarScroll()
            .scrollDisabled(isOverlayOn)

            if isOverlayOn {
                detailOverlay
            }
            }
            .coordinateSpace(.named(Self.space))
            .background(Color.appBackground)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Account.self) { account in
                walletDetail(account)
            }
            .navigationDestination(for: String.self) { _ in
                ArchivedWalletsView(accounts: archivedAccounts) { walletDetail($0) }
            }
            .refreshable {
                guard let userId = authViewModel.currentUser?.id else { return }
                await viewModel.loadAccounts(userId: userId, forceRefresh: true)
                await syncAccountTransactions(userId: userId, forceRefresh: true)
                await syncCategories(userId: userId)
            }
            .onAppear { isBalanceVisible = isBalanceVisibleStorage }
            .onChange(of: isBalanceVisibleStorage) { _, newValue in isBalanceVisible = newValue }
            .task {
                guard let userId = authViewModel.currentUser?.id else { return }
                await viewModel.loadAccounts(userId: userId)
                await syncAccountTransactions(userId: userId)
                await syncCategories(userId: userId)
            }
            .onReceive(NotificationCenter.default.publisher(for: .dataDidChange)) { _ in
                guard let userId = authViewModel.currentUser?.id else { return }
                Task {
                    await viewModel.loadAccounts(userId: userId, forceRefresh: true)
                    await syncAccountTransactions(userId: userId, forceRefresh: true)
                    await syncCategories(userId: userId)
                }
            }
            .fullScreenCover(item: $transferFrom) { account in
                if let userId = authViewModel.currentUser?.id {
                    AddTransactionView(
                        categories: categories,
                        accounts: viewModel.accounts,
                        userId: userId,
                        onSave: {},
                        initialType: .transfer,
                        initialAccount: account
                    )
                }
            }
            .sheet(isPresented: $showAddWallet) {
                if let userId = authViewModel.currentUser?.id {
                    AddWalletView { name, type, balance, icon, creditLimit, dueDate in
                        let success = await viewModel.addAccount(name: name, type: type, openingBalance: balance, icon: icon, userId: userId, creditLimit: creditLimit, dueDate: dueDate)
                        if success {
                            await syncAccountTransactions(userId: userId)
                        }
                        return success
                    }
                    .presentationDetents([.medium, .large])
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        ScreenHeader(title: "Dompet") {
            Button {
                withAnimation(.smooth) { isBalanceVisible.toggle() }
                isBalanceVisibleStorage = isBalanceVisible
            } label: {
                Image(systemName: isBalanceVisible ? "eye" : "eye.slash")
            }
            .accessibilityLabel(isBalanceVisible ? "Sembunyikan saldo" : "Tampilkan saldo")
            Button {
                showAddWallet = true
            } label: {
                Image(systemName: "plus")
                    .foregroundStyle(Color.appPrimary)
            }
            .accessibilityLabel("Tambah dompet")
        }
    }

    private func errorStateView(message: String) -> some View {
        ErrorStateView(message: message) {
            guard let userId = authViewModel.currentUser?.id else { return }
            Task {
                await viewModel.loadAccounts(userId: userId, forceRefresh: true)
                await syncAccountTransactions(userId: userId)
            }
        }
    }

    private var skeletonContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            RoundedRectangle(cornerRadius: 4).fill(Color.appFill).frame(width: 160, height: 14)
            RoundedRectangle(cornerRadius: 4).fill(Color.appFill).frame(width: 240, height: 48)
            RoundedRectangle(cornerRadius: 16).fill(Color.appFill).frame(height: cardHeight).padding(.top, 40)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .shimmer()
    }

    // MARK: Summary

    private var summary: some View {
        let activeCount = viewModel.accounts.filter(\.isActive).count
        let hasCredit = viewModel.accounts.contains { $0.isActive && $0.isCreditCard }
        return VStack(alignment: .leading, spacing: 0) {
            Text("Total saldo · \(activeCount) akun aktif")
                .font(.app(15))
                .foregroundStyle(Color.appTextSecondary)
            HeroAmount(value: viewModel.totalBalance, isVisible: isBalanceVisible)
                .padding(.top, 8)
            if hasCredit {
                HStack {
                    Text("Utang kartu kredit")
                        .foregroundStyle(Color.appTextSecondary)
                    Spacer()
                    Text(masked(viewModel.totalCreditDebt))
                        .fontWeight(.medium)
                        .foregroundStyle(Color.appText)
                }
                .font(.app(15))
                .monospacedDigit()
                .padding(.top, 14)
                .overlay(alignment: .top) { Rectangle().fill(Color.appDivider).frame(height: 1) }
                .padding(.top, 18)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("Belum ada dompet")
                .font(.app(16))
                .foregroundStyle(Color.appTextSecondary)
            Button("Tambah dompet") { showAddWallet = true }
                .font(.app(16, weight: .medium))
                .foregroundStyle(Color.appPrimary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Stacks

    private func groupSection(_ group: WalletGroup) -> some View {
        let isOpen = openGroups.contains(group.type)
        let total = group.accounts.reduce(0) { $0 + $1.balance }
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                setGroup(group.type, open: !isOpen)
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(group.title)
                            .font(.app(20, weight: .semibold))
                            .tracking(-0.2)
                            .foregroundStyle(Color.appText)
                        Text("\(group.accounts.count)")
                            .font(.app(13))
                            .foregroundStyle(Color.appTextTertiary)
                    }
                    Spacer()
                    Text((group.type == .credit ? "Utang " : "") + masked(total))
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                        .monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(group.accounts.count < 2)
            .accessibilityHint(group.accounts.count < 2 ? "" : isOpen ? "Tutup tumpukan" : "Buka tumpukan")
            .padding(.bottom, 12)

            VStack(spacing: 0) {
                ForEach(Array(group.accounts.enumerated()), id: \.element.id) { index, account in
                    WalletCard(
                        account: account,
                        showsStripAmount: !isOpen && index != group.accounts.count - 1,
                        isBalanceVisible: isBalanceVisible
                    )
                    .frame(height: cardHeight)
                    .opacity(isOverlayOn ? 0 : 1)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.space)).minY } action: { [cardTops] top in
                        cardTops.values[account.id] = top
                    }
                    .padding(.top, index == 0 ? 0 : isOpen ? 12 : stripHeight - cardHeight)
                    .zIndex(Double(index))
                    .onTapGesture { openDetail(account) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Buka dompet")
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 26)
    }

    private func setGroup(_ type: Account.AccountType, open: Bool) {
        withAnimation(.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.46)) {
            if open { openGroups.insert(type) } else { openGroups.remove(type) }
        }
    }

    // MARK: Wallet detail

    /// All active cards in page order; the overlay animates every one of them.
    private var allCards: [Account] { groups.flatMap(\.accounts) }

    private func openDetail(_ account: Account) {
        guard !isOverlayOn else { return }
        lastSelectedID = account.id
        selectedID = nil
        isOverlayOn = true // the overlay's onAppear lifts the card
    }

    private func select(_ id: String) {
        lastSelectedID = id
        selectedID = selectedID == id ? nil : id
        if selectedID == nil { closeDetail() }
    }

    private func closeDetail() {
        selectedID = nil
        let settle = 0.54 + Double(allCards.count) * 0.03
        DispatchQueue.main.asyncAfter(deadline: .now() + settle) {
            if selectedID == nil { isOverlayOn = false }
        }
    }

    /// Whether a card shows its amount on the top strip in its stack.
    private func showsStrip(_ account: Account) -> Bool {
        guard let group = groups.first(where: { $0.type == account.type }) else { return false }
        return !openGroups.contains(group.type) && group.accounts.last?.id != account.id
    }

    private func cardLayout(_ account: Account, index: Int, cards: [Account], pileTop: CGFloat) -> (y: CGFloat, scale: CGFloat, z: Double, delay: Double) {
        guard let selected = selectedID else {
            // Back to the card's spot in its stack.
            let y = cardTops.values[account.id] ?? pileTop + 200
            return (y, 1, Double(index), Double(cards.count - 1 - index) * 0.03)
        }
        if account.id == selected { return (detailCardTop, 1, 100, 0) }
        let k = Double(cards.filter { $0.id != selected }.firstIndex { $0.id == account.id } ?? 0)
        return (pileTop + CGFloat(k) * pileStep, 0.9 + CGFloat(k) * 0.02, 10 + k, 0.04 + k * 0.03)
    }

    /// Design 5a: the page fades to white, the tapped card lifts under the header, the others
    /// drop into a pile at the bottom (tap one to switch), and the detail fades in under the card.
    private var detailOverlay: some View {
        let shown = selectedID != nil
        let cards = allCards
        return GeometryReader { geo in
            let pileTop = geo.size.height - geo.safeAreaInsets.bottom - pileVisible
            ZStack(alignment: .top) {
                Color.appBackground
                    .ignoresSafeArea()
                    .opacity(shown ? 1 : 0)
                    .animation(.easeOut(duration: 0.26), value: shown)

                ScreenHeader(title: "Dompet") {
                    Button("Selesai", action: closeDetail)
                        .font(.app(17, weight: .semibold))
                        .foregroundStyle(Color.appPrimary)
                }
                .opacity(shown ? 1 : 0)
                .animation(.easeOut(duration: 0.26), value: shown)

                if let account = cards.first(where: { $0.id == (selectedID ?? lastSelectedID) }) {
                    detailContent(account, isOpen: shown)
                        .padding(.horizontal, 24)
                        .padding(.top, detailCardTop + cardHeight + 20)
                        .opacity(shown ? 1 : 0)
                        .offset(y: shown ? 0 : 18)
                        .animation(.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.46).delay(shown ? 0.2 : 0), value: selectedID)
                        .allowsHitTesting(shown)
                }

                ForEach(Array(cards.enumerated()), id: \.element.id) { index, account in
                    let layout = cardLayout(account, index: index, cards: cards, pileTop: pileTop)
                    WalletCard(
                        account: account,
                        showsStripAmount: !shown && showsStrip(account),
                        isBalanceVisible: isBalanceVisible
                    )
                    .frame(height: cardHeight)
                    .scaleEffect(layout.scale, anchor: .top)
                    .padding(.horizontal, 24)
                    .offset(y: layout.y)
                    .zIndex(layout.z)
                    .animation(cardAnimation.delay(layout.delay), value: selectedID)
                    .onTapGesture { if shown { select(account.id) } }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(selectedID == account.id ? "Tutup detail" : "Buka dompet")
                }
            }
        }
        // Span to the screen bottom so `safeAreaInsets.bottom` reports the tab bar height.
        .ignoresSafeArea(.container, edges: .bottom)
        .onAppear { selectedID = lastSelectedID }
    }

    private func detailContent(_ account: Account, isOpen: Bool) -> some View {
        let recent = Array((accountTransactions[account.id] ?? []).prefix(3))
        return VStack(alignment: .leading, spacing: 0) {
            if account.isCreditCard, let limit = account.creditLimit {
                VStack(alignment: .leading, spacing: 6) {
                    SegmentBar(value: account.creditUtilization ?? 0, delay: 0.35, isActive: isOpen)
                    HStack {
                        Text("Terpakai \(masked(account.balance)) / \(isBalanceVisible ? "Rp" + limit.abbreviatedRupiah() : "Rp" + hiddenAmount)")
                        Spacer()
                        if let day = account.dueDay {
                            Text("Jatuh tempo \(day) \(Self.nextDueMonth(day: day))")
                        }
                    }
                    .font(.app(12))
                    .foregroundStyle(Color.appTextSecondary)
                    .monospacedDigit()
                }
                .padding(.bottom, 16)
            }

            HStack(spacing: 0) {
                detailAction("Transfer", icon: "arrow.left.arrow.right") { transferFrom = account }
                detailAction("Sesuaikan", icon: "slider.horizontal.3") { path.append(account) }
                detailAction("Riwayat", icon: "clock.arrow.circlepath") { path.append(account) }
                detailAction("Ubah", icon: "pencil") { path.append(account) }
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Transaksi terakhir")
                    .font(.app(17, weight: .semibold))
                    .foregroundStyle(Color.appText)
                Spacer()
                Button("Semua") { path.append(account) }
                    .font(.app(15))
                    .foregroundStyle(Color.appPrimary)
            }
            .padding(.top, 22)

            if recent.isEmpty {
                Text("Belum ada transaksi")
                    .font(.app(15))
                    .foregroundStyle(Color.appTextSecondary)
                    .padding(.top, 12)
            } else {
                ForEach(recent) { transaction in
                    TransactionRowView(
                        transaction: transaction,
                        categories: categories,
                        accounts: viewModel.accounts,
                        showBalance: isBalanceVisible,
                        showDate: false
                    )
                    .rowSeparator()
                }
            }
        }
    }

    private func detailAction(_ title: String, icon: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Color.appText)
                    .frame(width: 44, height: 44)
                    .background(Color.appFill, in: Circle())
                Text(title)
                    .font(.app(12))
                    .foregroundStyle(Color.appBody)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(RowPressStyle())
    }

    /// Short month of the next occurrence of `day`, e.g. "Okt".
    private static func nextDueMonth(day: Int) -> String {
        let calendar = Calendar.current
        let now = Date()
        let date = calendar.component(.day, from: now) <= day ? now : (calendar.date(byAdding: .month, value: 1, to: now) ?? now)
        let f = DateFormatter()
        f.dateFormat = "MMM"
        f.locale = Locale(identifier: "id_ID")
        return f.string(from: date)
    }

    // MARK: Footer

    private var footerRows: some View {
        let subscribed = viewModel.accounts.first { $0.isActive && ($0.subscriptionsTotal ?? 0) > 0 }
        return VStack(spacing: 0) {
            if let subscribed, viewModel.totalSubscriptions > 0 {
                Button { path.append(subscribed) } label: {
                    HStack(spacing: 14) {
                        rowIcon("repeat")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tagihan berulang")
                                .font(.app(16))
                                .foregroundStyle(Color.appText)
                            if !viewModel.subscriptionNames.isEmpty {
                                Text(viewModel.subscriptionNames.joined(separator: ", "))
                                    .font(.app(13))
                                    .foregroundStyle(Color.appTextSecondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                        Text(masked(viewModel.totalSubscriptions) + "/bln")
                            .font(.app(15))
                            .foregroundStyle(Color.appTextSecondary)
                            .monospacedDigit()
                        chevron
                    }
                    .padding(.vertical, 14)
                    .overlay(alignment: .top) { Rectangle().fill(Color.appDivider).frame(height: 1) }
                    .rowSeparator()
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
            }

            if !archivedAccounts.isEmpty {
                Button { path.append("archived") } label: {
                    HStack(spacing: 14) {
                        rowIcon("archivebox")
                        Text("Diarsipkan")
                            .font(.app(16))
                            .foregroundStyle(Color.appTextSecondary)
                        Spacer()
                        Text("\(archivedAccounts.count)")
                            .font(.app(15))
                            .foregroundStyle(Color.appTextSecondary)
                        chevron
                    }
                    .padding(.vertical, 14)
                    .overlay(alignment: .top) {
                        if subscribed == nil || viewModel.totalSubscriptions <= 0 {
                            Rectangle().fill(Color.appDivider).frame(height: 1)
                        }
                    }
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.appDivider).frame(height: 1) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
    }

    private func rowIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 19))
            .foregroundStyle(Color.appTextSecondary)
            .frame(width: 24)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.appTextTertiary)
    }

    private func masked(_ amount: Double) -> String {
        isBalanceVisible ? amount.formattedAsCurrency() : "Rp" + hiddenAmount
    }

    private func walletDetail(_ account: Account) -> some View {
        WalletDetailView(
            account: account,
            transactions: accountTransactions[account.id] ?? [],
            categories: categories,
            onSave: { id, name, type, icon, isArchived, newBalance, oldBalance, creditLimit, dueDate in
                return await viewModel.rebalanceAccount(id: id, name: name, type: type, icon: icon, isArchived: isArchived, newBalance: newBalance, oldBalance: oldBalance, userId: authViewModel.currentUser?.id ?? "", creditLimit: creditLimit, dueDate: dueDate)
            },
            onDelete: { id in return await viewModel.removeAccount(id: id) },
            onToggleArchive: { id, _ in return await viewModel.toggleAccountArchive(id: id) },
            onSetDefault: account.isActive
                ? { id in await viewModel.setDefaultAccount(id: id, userId: authViewModel.currentUser?.id ?? "") }
                : nil
        )
    }

    // MARK: Data

    private func syncAccountTransactions(userId: String, forceRefresh: Bool = false) async {
        if forceRefresh {
            AppDataCache.shared.setAccountTransactions([:], for: userId)
        } else if let cached = AppDataCache.shared.accountTransactions(for: userId) {
            accountTransactions = cached
            cachedUserId = userId
            return
        }

        if !forceRefresh, cachedUserId == userId, !accountTransactions.isEmpty { return }

        do {
            let userTransactions = try await SupabaseRepository.shared.fetchTransactions(userId: userId)
            let grouped = groupTransactionsByAccount(userTransactions)
            accountTransactions = grouped
            cachedUserId = userId
            AppDataCache.shared.setAccountTransactions(grouped, for: userId)
        } catch is CancellationError {
            // Keep existing detail transactions if task was cancelled.
        } catch {
            print("❌ syncAccountTransactions failed: \(error)")
        }
    }

    private func syncCategories(userId: String) async {
        categories = (try? await SupabaseRepository.shared.fetchCategories()) ?? []
    }

    private func groupTransactionsByAccount(_ transactions: [Transaction]) -> [String: [Transaction]] {
        var grouped: [String: [Transaction]] = [:]
        for transaction in transactions {
            grouped[transaction.accountId, default: []].append(transaction)
            if let counterpartyAccountId = transaction.counterpartyAccountId {
                grouped[counterpartyAccountId, default: []].append(transaction)
            }
        }
        for key in grouped.keys {
            grouped[key] = grouped[key]?.sorted { $0.date > $1.date }
        }
        return grouped
    }
}

// MARK: - Card

extension Account {
    var walletColor: Color {
        WalletIcon.resolve(icon)?.color ?? .appPrimary
    }

    var walletShortName: String {
        WalletIcon.resolve(icon)?.shortName ?? String(name.prefix(4)).uppercased()
    }

    var typeLabel: String {
        switch type {
        case .cash: "Cash"
        case .bank: isDefault ? "Bank · Utama" : "Bank"
        case .ewallet: "E-Wallet"
        case .credit: "Kartu kredit"
        }
    }
}

/// Full-size brand-colored wallet card.
struct WalletCard: View {
    let account: Account
    var showsStripAmount: Bool
    var isBalanceVisible: Bool

    private var amountText: String {
        let value = account.isCreditCard ? (account.availableCredit ?? 0) : account.balance
        return isBalanceVisible ? value.formattedAsCurrency() : "Rp" + hiddenAmount
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(account.walletColor)
            .overlay(alignment: .topTrailing) {
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .strokeBorder(.white.opacity(0.1))
                        .frame(width: 220, height: 220)
                        .offset(x: 50, y: -70)
                    Circle()
                        .fill(.white.opacity(0.06))
                        .frame(width: 150, height: 150)
                        .offset(x: 20, y: -40)
                }
            }
            .overlay(alignment: .top) {
                HStack(alignment: .firstTextBaseline) {
                    Text(account.walletShortName)
                        .font(.app(15, weight: .heavy))
                        .tracking(0.6)
                    Text(account.name)
                        .font(.app(13))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                    Spacer()
                    Text(amountText)
                        .font(.app(15, weight: .semibold))
                        .monospacedDigit()
                        .opacity(showsStripAmount ? 1 : 0)
                        .animation(.easeInOut(duration: 0.22), value: showsStripAmount)
                }
                .frame(height: 56)
                .padding(.horizontal, 18)
            }
            .overlay(alignment: .bottom) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.isCreditCard ? "Sisa limit" : "Saldo")
                            .font(.app(12))
                            .foregroundStyle(.white.opacity(0.82))
                        Text(amountText)
                            .font(.app(24, weight: .semibold))
                            .tracking(-0.4)
                            .monospacedDigit()
                    }
                    Spacer()
                    Text(account.typeLabel)
                        .font(.app(12))
                        .foregroundStyle(.white.opacity(0.82))
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
            }
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.14), radius: 6, y: -3)
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .combine)
    }
}

/// 46×30 mini card used in plain lists (design 3d).
struct MiniWalletCard: View {
    let account: Account

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(account.walletColor)
            .overlay(alignment: .topTrailing) {
                Circle().fill(.white.opacity(0.14)).frame(width: 30, height: 30).offset(x: 10, y: -12)
            }
            .overlay(alignment: .bottomLeading) {
                Text(account.walletShortName)
                    .font(.app(8, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(.white)
                    .padding(.leading, 6)
                    .padding(.bottom, 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .frame(width: 46, height: 30)
    }
}

// MARK: - Archived

struct ArchivedWalletsView<Destination: View>: View {
    let accounts: [Account]
    @ViewBuilder let destination: (Account) -> Destination
    @AppStorage("isBalanceVisible") private var isBalanceVisible = true

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(accounts) { account in
                    NavigationLink(destination: destination(account)) {
                        HStack(spacing: 14) {
                            MiniWalletCard(account: account)
                            Text(account.name)
                                .font(.app(16, weight: .medium))
                                .foregroundStyle(Color.appText)
                            Spacer()
                            Text(isBalanceVisible ? account.balance.formattedAsCurrency() : "Rp" + hiddenAmount)
                                .font(.app(16))
                                .monospacedDigit()
                                .foregroundStyle(Color.appTextSecondary)
                        }
                        .padding(.vertical, 12)
                        .rowSeparator()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                }
            }
            .padding(.horizontal, 24)
        }
        .background(Color.appBackground)
        .navigationTitle("Diarsipkan")
        .navigationBarTitleDisplayMode(.inline)
    }
}
