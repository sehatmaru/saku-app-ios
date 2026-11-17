import SwiftUI

/// Dompet: one card stack per wallet type (design 6c). Tap any card to open its detail like
/// design 5a (the card lifts to the top, every other card drops into a pile at the bottom);
/// tap a group title to fan its stack out or close it.
struct AccountListView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel: AccountListViewModel

    /// Opens the add-wallet sheet as soon as the page appears.
    private let startsAdding: Bool
    /// Lifts this card to its detail as soon as the wallets have loaded (from the overdue bill on Beranda).
    private let opensCardId: String?
    @State private var didOpenCard = false
    /// Beranda's navigation path: Dompet is pushed onto it and pushes its own pages there too,
    /// so the system back button and edge swipe work like everywhere else.
    @Binding private var path: NavigationPath

    init(viewModel: AccountListViewModel = AccountListViewModel(), startsAdding: Bool = false, opensCardId: String? = nil,
         path: Binding<NavigationPath>) {
        self.opensCardId = opensCardId
        _viewModel = StateObject(wrappedValue: viewModel)
        self.startsAdding = startsAdding
        _path = path
    }
    @AppStorage("isBalanceVisible") private var isBalanceVisibleStorage = true
    @State private var isBalanceVisible = true
    @State private var showAddWallet = false
    @ObservedObject private var plus = PlusStore.shared
    @State private var accountTransactions: [String: [Transaction]] = [:]
    @State private var categories: [Category] = []
    @State private var cachedUserId: String?
    @State private var openGroups: Set<Account.AccountType> = []
    /// The detail overlay is on screen (also while cards fly back into their stacks).
    @State private var isOverlayOn = false
    /// Card lifted to the top; nil while the overlay opens or closes.
    @State private var selectedID: String?
    @State private var deleting: Account?
    /// Scroll offset of the open card's detail; the card moves with it.
    @State private var detailScrollY: CGFloat = 0
    @State private var detailScrollPosition = ScrollPosition(edge: .top)
    /// Last opened card, keeps the detail content filled while it fades out.
    @State private var lastSelectedID: String?
    @State private var cardTops = CardTops()
    @State private var transferFrom: Account?
    /// Perbarui nilai for an investment wallet.
    @State private var updatingValue: Account?
    /// "Mau diingatkan?", once, after the first investment wallet is made.
    @State private var reminderOffer: Account?
    @ObservedObject private var notificationRouter = NotificationRouter.shared
    /// Setor ke aset / Tarik dari aset, started from an investment wallet.
    @State private var assetTransfer: AssetTransferRoute?

    struct AssetTransferRoute: Identifiable {
        let account: Account
        let mode: AddTransactionView.AssetMode
        var id: String { account.id + (mode == .deposit ? "-in" : "-out") }
    }
    @State private var payCard: Account?
    /// Catat tagihan: a bill that was already paid, opened from the overdue block.
    @State private var recordCard: Account?
    /// Shown as the main wallet at once while the change is saved.
    @State private var pendingDefaultID: String?
    @State private var archiving: Account?
    /// K36: the wallet being moved to a shared Workspace, asking which one.
    @State private var moving: Account?
    @ObservedObject private var workspaceStore = WorkspaceStore.shared
    @State private var makingMain: Account?
    @State private var reminding: Account?
    /// Rolls the hero's numbers in; replayed when the page opens and when a card closes.
    @State private var odometerOn = false

    /// Card positions kept outside view state so scrolling doesn't re-render the screen.
    private final class CardTops {
        var values: [String: CGFloat] = [:]
    }

    private static let space = "dompet"
    // Detail layout from design 5a, in points.
    private let detailCardTop: CGFloat = 8
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
        let titled: [(Account.AccountType, String)] = [(.bank, L("Bank")), (.ewallet, L("E-Wallet")), (.cash, L("Cash")), (.credit, L("Kartu kredit")), (.investment, L("Investasi"))]
        return titled.compactMap { type, title in
            let accounts = active.filter { $0.type == type }.sorted { $0.isDefault && !$1.isDefault }
            return accounts.isEmpty ? nil : WalletGroup(type: type, title: title, accounts: accounts)
        }
    }

    private var archivedAccounts: [Account] {
        viewModel.accounts.filter { !$0.isActive }
    }

    var body: some View {
        Group {
            ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let error = viewModel.errorMessage, !viewModel.hasLoadedOnce {
                        errorStateView(message: error)
                            .padding(24)
                    } else if !viewModel.hasLoadedOnce {
                        skeletonContent
                    } else {
                        if let error = viewModel.errorMessage {
                            ErrorBanner(message: error).padding(.horizontal, 24).padding(.top, 16)
                        }
                        if groups.isEmpty {
                            emptyState.padding(.top, 120)
                        } else {
                            hero
                                .opacity(selectedID == nil ? 1 : 0)
                                .offset(y: selectedID == nil ? 0 : -12)
                                .animation(.settle(0.46), value: selectedID)
                        }
                        ForEach(groups) { group in
                            groupSection(group)
                        }
                    }
                }
                .padding(.bottom, 88) // clears the floating +
                .animation(.easeInOut(duration: 0.3), value: viewModel.hasLoadedOnce)
            }
            .scrollDisabled(isOverlayOn)

            if isOverlayOn {
                detailOverlay
            }
            }
            .coordinateSpace(.named(Self.space))
            .background(Color.appBackground)
            .scrollIndicators(.hidden)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(selectedID != nil)
            // The edge swipe closes the open card (back to the list) instead of leaving the page.
            .background { BackSwipeOff(isOff: selectedID != nil && path.count <= 1) }
            .simultaneousGesture(
                DragGesture(minimumDistance: 20).onEnded { value in
                    guard selectedID != nil, value.startLocation.x < 40, value.translation.width > 70,
                          abs(value.translation.height) < 80 else { return }
                    closeDetail()
                }
            )
            // The card pile sits at the bottom while a card's detail is open.
            .hidesDetailAddButton(isOverlayOn)
            .toolbar { toolbarItems }
            .detailPage(addLabel: L("Tambah dompet")) { showAddWallet = true }
            .navigationDestination(for: Account.self) { account in
                walletDetail(account).detailPage()
            }
            .navigationDestination(for: WalletHistoryRoute.self) { route in
                if route.account.isCreditCard {
                    CardHistoryView(account: route.account,
                                    statement: viewModel.statement(for: route.account, transactions: accountTransactions[route.account.id] ?? []),
                                    transactions: accountTransactions[route.account.id] ?? [], categories: categories,
                                    accounts: viewModel.accounts, isBalanceVisible: isBalanceVisible)
                        .detailPage()
                } else if route.account.isInvestment {
                    InvestmentHistoryView(account: route.account, transactions: accountTransactions[route.account.id] ?? [],
                                          accounts: viewModel.accounts, isBalanceVisible: isBalanceVisible)
                        .detailPage()
                } else {
                WalletHistoryView(account: route.account, transactions: accountTransactions[route.account.id] ?? [],
                                  categories: categories, accounts: viewModel.accounts, isBalanceVisible: isBalanceVisible)
                    .detailPage()
                }
            }
            .navigationDestination(for: WalletSubscriptionsRoute.self) { route in
                WalletSubscriptionsView(account: route.account,
                                        subscriptions: viewModel.subscriptions.filter { $0.accountId == route.account.id },
                                        categories: categories)
                    .detailPage()
            }
            .navigationDestination(for: String.self) { route in
                ArchivedWalletsView(accounts: archivedAccounts) { account in
                    await viewModel.toggleAccountArchive(id: account.id)
                }
                .detailPage()
            }
            .refreshable {
                guard let userId = authViewModel.currentUser?.id else { return }
                await viewModel.loadAccounts(userId: userId, forceRefresh: true)
                await syncAccountTransactions(userId: userId, forceRefresh: true)
                await syncCategories(userId: userId)
            }
            .onAppear {
                isBalanceVisible = isBalanceVisibleStorage
                if startsAdding { showAddWallet = true }
            }
            .onChange(of: isBalanceVisibleStorage) { _, newValue in isBalanceVisible = newValue }
            // The open wallet was deleted or archived (e.g. from Ubah): close its overlay instead of
            // leaving a blank page on top of the list.
            .onChange(of: allCards.map(\.id)) { _, ids in
                guard let open = selectedID ?? (isOverlayOn ? lastSelectedID : nil), !ids.contains(open) else { return }
                selectedID = nil
                lastSelectedID = nil
                isOverlayOn = false
                playOdometer(after: 0.3)
            }
            .task {
                guard let userId = authViewModel.currentUser?.id else { return }
                await viewModel.loadAccounts(userId: userId)
                await syncAccountTransactions(userId: userId)
                await syncCategories(userId: userId)
            }
            .onReceive(NotificationCenter.default.publisher(for: .dataDidChange)) { _ in reload() }
            .sheet(item: $deleting) { account in
                DeleteWalletSheet(account: account, transactionCount: accountTransactions[account.id]?.count ?? 0,
                                  onDelete: { deleting = nil; remove(account) },
                                  onArchiveInstead: { deleting = nil; archive(account) })
            }
            .sheet(item: $archiving) { account in
                ArchiveWalletSheet(name: account.name) {
                    archiving = nil
                    archive(account)
                }
            }
            .confirmationDialog(L("Pindahkan ke Workspace"), isPresented: Binding(get: { moving != nil }, set: { if !$0 { moving = nil } }),
                                titleVisibility: .visible, presenting: moving) { account in
                ForEach(moveTargets) { target in
                    Button(target.displayName) { move(account, to: target) }
                }
                Button(L("Batal"), role: .cancel) {}
            } message: { account in
                Text(L("%@ pindah dengan saldo terakhir, tanpa riwayat. Dompet lama diarsipkan. Pindah ini satu arah.", account.name))
            }
            .sheet(item: $makingMain) { account in
                MakeMainWalletSheet(name: account.name, previous: viewModel.accounts.first(where: \.isDefault)?.name) {
                    makingMain = nil
                    makeDefault(account)
                }
            }
            .sheet(item: $reminding) { account in
                InvestmentReminderSheet(account: account, transactions: accountTransactions[account.id] ?? [], offer: false)
            }
                .fullScreenCover(item: $payCard) { card in
                if let statement = viewModel.statement(for: card, transactions: accountTransactions[card.id] ?? []) {
                    PayCardBillSheet(card: card, statement: statement, wallets: viewModel.accounts,
                                     onPaid: { _, _, _ in ToastCenter.shared.show(L("Pembayaran tercatat")) })
                }
            }
            .fullScreenCover(item: $recordCard) { card in
                if let statement = viewModel.statement(for: card, transactions: accountTransactions[card.id] ?? []) {
                    PayCardBillSheet(card: card, statement: statement, wallets: viewModel.accounts, mode: .record,
                                     onPaid: { amount, _, isFull in
                        ToastCenter.shared.show(isFull ? L("%@ lunas · pembayaran tercatat", card.name) : L("Pembayaran %@ tercatat", amount.formattedAsCurrency()))
                    })
                }
            }
            .fullScreenCover(item: $updatingValue) { account in
                UpdateValueView(account: account,
                                capital: InvestmentSummary(account: account, transactions: accountTransactions[account.id] ?? []).capital) { value, date, note in
                    let ok = await viewModel.updateInvestmentValue(account: account, newValue: value, date: date, note: note)
                    if ok, let userId = authViewModel.currentUser?.id {
                        await syncAccountTransactions(userId: userId, forceRefresh: true)
                        // the next reminder counts from this update
                        if ReminderSync.ownsReminders { await ReminderSync.run(userId: userId) } else {
                            await NotificationManager.shared.resyncInvestmentReminders(accounts: viewModel.accounts, transactions: accountTransactions.values.flatMap { $0 })
                        }
                    }
                    return ok
                }
            }
            .sheet(item: $reminderOffer) { account in
                InvestmentReminderSheet(account: account, transactions: accountTransactions[account.id] ?? [], offer: true)
            }
            .onChange(of: notificationRouter.pendingInvestmentId) { _, _ in openReminderTarget() }
            .onChange(of: viewModel.accounts.count) { _, _ in openReminderTarget(); openRequestedCard() }
            .onAppear { openReminderTarget(); openRequestedCard() }
            .fullScreenCover(item: $assetTransfer) { route in
                if let userId = authViewModel.currentUser?.id {
                    AddTransactionView(categories: categories, accounts: viewModel.accounts, userId: userId, onSave: {},
                                       initialType: .transfer, locksType: true, initialAccount: route.account, initialAssetMode: route.mode)
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
                        locksType: true,
                        initialAccount: account
                    )
                }
            }
            .fullScreenCover(isPresented: $showAddWallet) {
                if let userId = authViewModel.currentUser?.id {
                    AddWalletView(isLimited: { FreeLimits.isWalletLimited($0, in: viewModel.accounts, isPlus: plus.isPlus) },
                                  nameTaken: { name, type in viewModel.accounts.contains { $0.name == name && $0.type == type && $0.isActive } }) { wallet in
                        let firstInvestment = wallet.type == .investment && !viewModel.accounts.contains(where: \.isInvestment)
                        let success = await viewModel.addAccount(
                            name: wallet.name, type: wallet.type, openingBalance: wallet.balance, icon: wallet.icon,
                            userId: userId, creditLimit: wallet.creditLimit, dueDate: wallet.dueDate,
                            statementDay: wallet.statementDay, color: wallet.color, cardNetwork: wallet.cardNetwork,
                            openingUnbilledUntil: wallet.openingUnbilledUntil,
                            makeDefault: wallet.isDefault)
                        if success {
                            await syncAccountTransactions(userId: userId)
                            if firstInvestment, !InvestmentReminderStore().wasOffered, let created = viewModel.accounts.last(where: \.isInvestment) {
                                // after the Tambah dompet screen has closed
                                Task { try? await Task.sleep(for: .milliseconds(700)); reminderOffer = created }
                            }
                        }
                        return success
                    }
                }
            }
        }
    }

    // MARK: Header

    /// Archive and balance; while a card's detail is open, only the back chevron.
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        if selectedID != nil {
            // Back on the left; Tutup and Edit are pinned at the bottom.
            ToolbarItem(placement: .topBarLeading) {
                Button(action: closeDetail) { Image(systemName: "chevron.left") }
                    .tint(Color.appText)
                    .accessibilityLabel("Kembali")
            }
        } else {
            ToolbarItemGroup(placement: .topBarTrailing) {
                // 13c: the actions wait until the wallets are in.
                Group {
                    Button { path.append("archived") } label: {
                        Image(systemName: "archivebox")
                    }
                    .tint(Color.appText)
                    .accessibilityLabel("Diarsipkan")
                    if !viewModel.hasLoadedOnce || !groups.isEmpty {
                        Button {
                            withAnimation(.smooth) { isBalanceVisible.toggle() }
                            isBalanceVisibleStorage = isBalanceVisible
                        } label: {
                            Image(systemName: isBalanceVisible ? "eye" : "eye.slash")
                        }
                        .tint(Color.appText)
                        .accessibilityLabel(isBalanceVisible ? L("Sembunyikan saldo") : L("Tampilkan saldo"))
                    }
                }
                .disabled(!viewModel.hasLoadedOnce)
            }
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

    /// 13c: each group is a title, two peeking card edges and a card.
    private var skeletonContent: some View {
        VStack(spacing: 30) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(spacing: 0) {
                    HStack {
                        SkeletonBlock(width: 96, height: 18, radius: 6)
                        Spacer()
                        SkeletonBlock(width: 70, height: 13)
                    }
                    .frame(height: 36)
                    UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12)
                        .fill(Color.appFill.opacity(0.6))
                        .frame(height: 10)
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                    UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12)
                        .fill(Color.appFill)
                        .frame(height: 10)
                        .padding(.horizontal, 6)
                    SkeletonBlock(height: 150, radius: 16)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .accessibilityLabel("Memuat")
    }

    /// 13d: three dashed cards with a + on the front one.
    private var emptyState: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.appTextTertiary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .frame(height: 96)
                    .padding(.horizontal, 24)
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.appBackground)
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.appTextTertiary.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                    .frame(height: 100)
                    .padding(.horizontal, 12)
                    .padding(.top, 16)
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.appFill)
                    .frame(height: 100)
                    .overlay(Image(systemName: "plus").font(.system(size: 26)).foregroundStyle(Color.appTextTertiary))
                    .padding(.top, 32)
            }
            .frame(width: 176, height: 132)
            .accessibilityHidden(true)

            Text("Belum ada dompet")
                .font(.app(20, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(Color.appText)
                .padding(.top, 28)
            Text("Tambahkan rekening bank, e-wallet, kartu kredit, atau uang tunai.")
                .font(.app(15))
                .foregroundStyle(Color.appTextSecondary)
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            EmptyStateButton(title: L("Tambah dompet")) { showAddWallet = true }
                .padding(.top, 24)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity)
    }

    // MARK: Hero

    private var activeCards: [Account] { groups.first { $0.type == .credit }?.accounts ?? [] }

    /// Total saldo rolling in, plus one box summing every credit card (design 3a, v14).
    private var hero: some View {
        let hasAssets = viewModel.accounts.contains { $0.isActive && $0.isInvestment }
        // With an investment wallet the big number is Total kekayaan; without one nothing changes.
        let total = hasAssets ? viewModel.totalBalance + viewModel.assetsTotal : viewModel.totalBalance
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(hasAssets ? "Total kekayaan" : "Total saldo").font(.app(15)).foregroundStyle(Color.appTextSecondary)
                Spacer()
            }
            HStack(alignment: .top, spacing: 4) {
                Text(total < 0 && isBalanceVisible ? "−Rp" : "Rp")
                    .font(.app(22))
                    .foregroundStyle(Color.appTextSecondary)
                    .padding(.top, 8)
                if isBalanceVisible {
                    OdometerText(text: total.formattedAsDigits(), digitHeight: 52,
                                 font: .app(52, weight: .ultraLight), isOn: odometerOn)
                        .tracking(-2.2)
                } else {
                    Text(hiddenAmount).font(.app(52, weight: .ultraLight)).frame(height: 52)
                }
            }
            .foregroundStyle(Color.appText)
            .padding(.top, 4)

            if hasAssets, viewModel.totalBalance + viewModel.assetsTotal > 0 {
                compositionBar(cash: max(viewModel.totalBalance, 0), assets: max(viewModel.assetsTotal, 0))
                    .padding(.top, 14)
            }

        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .onAppear { playOdometer(after: 0.3) }
    }

    /// "+4%" with a trend arrow, or the rupiah gain/loss when there is no capital to take a percentage of.
    /// "Modal disetor" and "Terakhir diperbarui", shown on the open investment card.
    private func investmentFacts(for account: Account) -> [(String, String)] {
        guard account.isInvestment else { return [] }
        let summary = InvestmentSummary(account: account, transactions: accountTransactions[account.id] ?? [])
        return [(L("Modal disetor"), InvestmentUI.money(summary.capital, visible: isBalanceVisible)),
                (L("Terakhir diperbarui"),
                 summary.lastUpdated.map { InvestmentUI.shortDate($0) + " · " + InvestmentUI.daysAgo($0) } ?? "—")]
    }

    private func investmentPill(for account: Account) -> (symbol: String, text: String)? {
        guard account.isInvestment else { return nil }
        let summary = InvestmentSummary(account: account, transactions: accountTransactions[account.id] ?? [])
        let symbol = summary.gain > 0 ? "chart.line.uptrend.xyaxis" : summary.gain < 0 ? "chart.line.downtrend.xyaxis" : "minus"
        let sign = summary.gain > 0 ? "+" : summary.gain < 0 ? "−" : ""
        let text = isBalanceVisible
            ? (summary.percent.map { sign + Int(abs(($0 * 1000).rounded() / 10)).formatted() + "%" } ?? sign + abs(summary.gain).formattedAsCurrency())
            : "••••"
        return (symbol, text)
    }

    /// Cash against investments, in the same thin segmented style as the Investasi group's bar.
    private func compositionBar(cash: Double, assets: Double) -> some View {
        let sum = cash + assets
        let cashShare = sum > 0 ? cash / sum : 0
        let cashPct = Int((cashShare * 100).rounded()), assetPct = 100 - cashPct
        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    if isBalanceVisible {
                        if cash > 0 {
                            RoundedRectangle(cornerRadius: 2).fill(Color.appTextTertiary)
                                .frame(width: max(2, (geo.size.width - 2) * cashShare))
                        }
                        if assets > 0 { RoundedRectangle(cornerRadius: 2).fill(Color.appInvestment) }
                    } else {
                        RoundedRectangle(cornerRadius: 2).fill(Color.appDivider)
                    }
                }
            }
            .frame(height: 8)
            Text(isBalanceVisible ? L("Kas %lld%% · Investasi %lld%%", cashPct, assetPct) : L("Kas ••%% · Investasi ••%%"))
                .font(.app(13)).foregroundStyle(Color.appTextSecondary).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    /// Under the Kartu kredit title, like the Investasi bar: how much of the combined limit is used.
    private var creditUsage: some View {
        let debt = activeCards.reduce(0) { $0 + max($1.balance, 0) }
        let limit = activeCards.reduce(0) { $0 + ($1.creditLimit ?? 0) }
        let left = masked(max(limit - debt, 0))
        // each card's share of the combined limit, biggest first
        let used = activeCards.map { (card: $0, share: limit > 0 ? min(max($0.balance, 0) / limit, 1) : 0) }
            .sorted { $0.share > $1.share }
        func pct(_ f: Double) -> String { isBalanceVisible ? "\(Int((f * 100).rounded()))%" : "••%" }
        let text: String
        if used.count == 1 {
            text = isBalanceVisible
                ? L("%lld%% dari limit %@ · Sisa %@", Int(((used.first?.share ?? 0) * 100).rounded()), masked(limit), left)
                : L("••%% dari limit %@ · Sisa %@", masked(limit), left)
        } else {
            let shown = used.count > 3 ? Array(used.prefix(2)) : used
            var parts = shown.map { "\($0.card.name) \(pct($0.share))" }
            if used.count > 3 { parts.append(L("lainnya") + " " + pct(used.dropFirst(2).reduce(0) { $0 + $1.share })) }
            text = (parts + [L("Sisa %@", left)]).joined(separator: " · ")
        }
        return VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.appDivider)
                    HStack(spacing: 2) {
                        if isBalanceVisible {
                            ForEach(Array(used.enumerated()), id: \.element.card.id) { _, item in
                                Rectangle().fill(item.card.walletColor)
                                    .frame(width: max(2, geo.size.width * (odometerOn ? item.share : 0)))
                            }
                        }
                    }
                    .clipShape(Capsule())
                    .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 1.1).delay(0.5), value: odometerOn)
                }
            }
            .frame(height: 8)
            Text(text)
                .font(.app(13)).foregroundStyle(Color.appTextSecondary).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.8)
                .padding(.top, 8)
        }
        .accessibilityElement(children: .combine)
    }

    /// The bill still owed, or for a card with nothing owed, the next cycle's due day.
    private func dueDate(of card: Account) -> Date? {
        guard let statement = viewModel.statement(for: card, transactions: accountTransactions[card.id] ?? []) else { return nil }
        return statement.remaining >= 1 ? statement.dueDate : CreditStatement.billing(forPurchaseOn: Date(), card: card).due
    }

    /// Resets the odometer at once, then rolls it in after `delay`.
    private func playOdometer(after delay: Double) {
        var reset = SwiftUI.Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { odometerOn = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { odometerOn = true }
    }

    private static var dayMonth: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        f.locale = AppLanguage.locale
        return f
    }

    private static var monthName: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        f.locale = AppLanguage.locale
        return f
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
                    Text(group.type == .credit ? L("Utang %@", masked(total))
                         : group.type == .investment ? L("Total aset %@", masked(total)) : masked(total))
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                        .monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .allowsHitTesting(group.accounts.count >= 2)
            .accessibilityHint(group.accounts.count < 2 ? "" : isOpen ? L("Tutup tumpukan") : L("Buka tumpukan"))
            .padding(.bottom, group.type == .credit || (group.type == .investment && InvestmentAllocation(accounts: group.accounts) != nil) ? 4 : 12)

            if group.type == .credit {
                creditUsage.padding(.bottom, 14)
            }

            if group.type == .investment, let allocation = InvestmentAllocation(accounts: group.accounts) {
                InvestmentAllocationView(allocation: allocation, isBalanceVisible: isBalanceVisible,
                                         colors: Dictionary(uniqueKeysWithValues: group.accounts.map { ($0.id, $0.walletColor) }))
                    .padding(.bottom, 14)
            }

            VStack(spacing: 0) {
                ForEach(Array(group.accounts.enumerated()), id: \.element.id) { index, account in
                    WalletCard(
                        account: account,
                        showsStripAmount: !isOpen && index != group.accounts.count - 1,
                        isBalanceVisible: isBalanceVisible,
                        isMain: account.id == mainWalletID,
                        investmentPill: investmentPill(for: account)
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
                    .accessibilityHint(L("Buka dompet"))
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, group.type == groups.first?.type ? 12 : 26)
    }

    /// The card Beranda asked for: lifted to its detail once, after the cards have settled in place.
    private func openRequestedCard() {
        guard !didOpenCard, let id = opensCardId, let account = allCards.first(where: { $0.id == id }) else { return }
        didOpenCard = true
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            openDetail(account)
        }
    }

    /// Tapping the reminder opens Perbarui nilai of that wallet, once the wallets have loaded.
    private func openReminderTarget() {
        guard let id = notificationRouter.pendingInvestmentId,
              let account = viewModel.accounts.first(where: { $0.id == id && $0.isInvestment && $0.isActive }) else { return }
        notificationRouter.pendingInvestmentId = nil
        updatingValue = account
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
        playOdometer(after: 0.45)
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

                if let account = cards.first(where: { $0.id == (selectedID ?? lastSelectedID) }) {
                    let contentTop = detailCardTop + cardHeight + 20
                    // The whole page scrolls: the card is positioned over a spacer and follows the scroll offset.
                    ScrollView {
                        VStack(spacing: 0) {
                            // the card floats above this spacer with hit testing off, so a tap lands here and the page still scrolls
                            Color.clear.frame(height: contentTop)
                                .contentShape(Rectangle())
                                .onTapGesture { if shown { select(account.id) } }
                            detailContent(account, isOpen: shown)
                                .padding(.horizontal, 24)
                                .padding(.bottom, 122)
                        }
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.always)
                    .scrollPosition($detailScrollPosition)
                    .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
                        detailScrollY = offset
                    }
                    .onChange(of: selectedID) { _, id in
                        if id != nil { detailScrollPosition.scrollTo(edge: .top) }
                    }
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
                        isBalanceVisible: isBalanceVisible,
                        // An open card keeps its usage bar; the pile doesn't need it.
                        showsUsage: !shown || account.id == selectedID,
                        isMain: account.id == mainWalletID,
                        investmentPill: investmentPill(for: account),
                        investmentFacts: shown && account.id == selectedID ? investmentFacts(for: account) : []
                    )
                    .frame(height: cardHeight)
                    .scaleEffect(layout.scale, anchor: .top)
                    .padding(.horizontal, 24)
                    .offset(y: layout.y - (shown && account.id == selectedID ? detailScrollY : 0))
                    .opacity(shown && account.id != selectedID ? 0 : 1)
                    .zIndex(layout.z)
                    .animation(cardAnimation.delay(layout.delay), value: selectedID)
                    .onTapGesture { if shown && account.id == selectedID { select(account.id) } }
                    // an open card lets drags through, so the page scrolls from anywhere
                    .allowsHitTesting(!shown)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(selectedID == account.id ? L("Tutup detail") : L("Buka dompet"))
                }

                if shown, let account = cards.first(where: { $0.id == selectedID }) {
                    SmartSheetFooter(primary: L("Ubah"), ink: true, secondary: L("Tutup"),
                                     onPrimary: { path.append(account) }) { closeDetail() }
                        .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 24)
                        .frame(maxWidth: .infinity)
                        .background(Color.appBackground)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .transition(.opacity)
                }
            }
        }
        // Span to the screen bottom so the footer sits 24 pt from the screen edge.
        .ignoresSafeArea(.container, edges: .bottom)
        .onAppear { selectedID = lastSelectedID }
    }

    /// Design 1a: four actions, the bill, the main-wallet switch and the way into the
    /// wallet's recurring bills.
    private func detailContent(_ account: Account, isOpen: Bool) -> some View {
        let statement = viewModel.statement(for: account, transactions: accountTransactions[account.id] ?? [])
        if account.isInvestment {
            return AnyView(VStack(alignment: .leading, spacing: 0) {
                InvestmentDetailContent(
                    account: account, transactions: accountTransactions[account.id] ?? [], isBalanceVisible: isBalanceVisible)
                listSection(L("Aktivitas")) {
                    listRow("arrow.triangle.2.circlepath", L("Perbarui nilai"), tint: .appPrimary) { updatingValue = account }
                    listRow("arrow.left.arrow.right", L("Transfer")) { transferFrom = account }
                    listRow("clock.arrow.circlepath", L("Riwayat")) { path.append(WalletHistoryRoute(account: account)) }
                }
                listSection(L("Pengaturan")) {
                    let reminder = InvestmentReminderStore().interval(for: account.id)
                    listRow("bell", L("Pengingat"), detail: reminder == .off ? nil : L("Diingatkan pukul 09.00"),
                            value: reminder.title) { reminding = account }
                }
                listSection(L("Lainnya")) {
                    moveRow(account)
                    listRow("archivebox", L("Arsipkan"), chevron: false) { archiving = account }
                    listRow("trash", L("Hapus dompet"), chevron: false, destructive: true) { deleting = account }
                }
            })
        }
        if account.isCreditCard {
            return AnyView(VStack(alignment: .leading, spacing: 0) {
                CardDetailContent(
                    card: account, statement: statement,
                    subscriptions: viewModel.subscriptions.filter { $0.accountId == account.id },
                    isBalanceVisible: isBalanceVisible,
                    onPay: { payCard = account }, onRecord: { recordCard = account },
                    onSubscriptions: { path.append(WalletSubscriptionsRoute(account: account)) },
                    onHistory: { path.append(WalletHistoryRoute(account: account)) })
                listSection(L("Aktivitas")) {
                    listRow("clock.arrow.circlepath", L("Riwayat")) { path.append(WalletHistoryRoute(account: account)) }
                    subscriptionsRow(account)
                }
                listSection(L("Lainnya")) {
                    listRow("archivebox", L("Arsipkan"), chevron: false) { archiving = account }
                    listRow("trash", L("Hapus dompet"), chevron: false, destructive: true) { deleting = account }
                }
            })
        }
        return AnyView(VStack(alignment: .leading, spacing: 0) {
            if let statement {
                billBox(statement, card: account)
            }

            listSection(L("Aktivitas"), first: statement == nil) {
                listRow("arrow.left.arrow.right", L("Transfer")) { transferFrom = account }
                listRow("clock.arrow.circlepath", L("Riwayat")) { path.append(WalletHistoryRoute(account: account)) }
                if account.type != .cash { subscriptionsRow(account) }
            }
            listSection(L("Pengaturan")) { mainRow(account) }
            listSection(L("Lainnya")) {
                moveRow(account)
                listRow("archivebox", L("Arsipkan"), chevron: false) { archiving = account }
                listRow("trash", L("Hapus dompet"), chevron: false, destructive: true) { deleting = account }
            }
        })
    }

    /// Shared Workspaces a wallet of Workspace Pribadi can move into (K36): not read-only, not waiting to be deleted.
    private var moveTargets: [Workspace] {
        guard workspaceStore.showsSwitcher, workspaceStore.activeIsPersonal else { return [] }
        return workspaceStore.shared.filter { !$0.isReadOnly && $0.daysUntilDeletion == nil }
    }

    @ViewBuilder private func moveRow(_ account: Account) -> some View {
        if !account.isCreditCard, !moveTargets.isEmpty {
            listRow("arrow.right.square", L("Pindahkan ke Workspace"), chevron: false) { moving = account }
        }
    }

    private func move(_ account: Account, to target: Workspace) {
        closeDetail()
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            do {
                try await workspaceStore.moveWallet(account.id, to: target)
                NotificationCenter.default.post(name: .dataDidChange, object: nil)
                ToastCenter.shared.show(L("%@ dipindah ke %@", account.name, target.displayName))
            } catch let error as WorkspaceError {
                ToastCenter.shared.show(error == .walletLimit
                    ? L("Batas dompet gratis di %@ sudah penuh.", target.displayName)
                    : L("Dompet belum bisa dipindah. Coba lagi."))
            } catch { ToastCenter.shared.show(L("Dompet belum bisa dipindah. Coba lagi.")) }
        }
    }

    private func subscriptionsRow(_ account: Account) -> some View {
        let active = viewModel.subscriptions.filter { $0.accountId == account.id && $0.isActive }
        let monthly = active.reduce(0) { $0 + $1.monthlyAmount }
        return listRow("repeat", L("Tagihan berulang"),
                       detail: active.isEmpty ? L("Belum ada") : L("%lld tagihan · %@/bulan", active.count, masked(monthly))) {
            path.append(WalletSubscriptionsRoute(account: account))
        }
    }

    private func listSection<Content: View>(_ title: String, first: Bool = false,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.app(13, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
                .padding(.top, first ? 18 : 26).padding(.bottom, 2)
            content()
        }
    }

    /// One plain row of the wallet detail: icon, title, optional detail line, hairline underneath.
    private func listRow(_ icon: String, _ title: String, detail: String? = nil, value: String? = nil, chevron: Bool = true,
                         destructive: Bool = false, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 20))
                    .foregroundStyle(destructive ? Color(hex: "D93636") : tint ?? Color.appTextSecondary).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.app(17)).foregroundStyle(destructive ? Color(hex: "D93636") : Color.appText)
                    if let detail {
                        Text(detail).font(.app(13)).foregroundStyle(Color.appTextSecondary).monospacedDigit()
                    }
                }
                Spacer(minLength: 8)
                if let value { Text(value).font(.app(15)).foregroundStyle(Color.appTextSecondary) }
                if chevron {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.appTextTertiary)
                }
            }
            .frame(minHeight: 56)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.appBorder.opacity(0.5)).frame(height: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }

    /// The last statement: a warm question once it is overdue (Pengingat Tagihan 2f), a quiet
    /// "Lunas" once paid (2g), otherwise what's owed with a tap to pay.
    @ViewBuilder
    private func billBox(_ statement: CreditStatement, card: Account) -> some View {
        if statement.status == .overdue {
            overdueBillBox(statement, card: card)
        } else if statement.status == .paid {
            paidBillBox(statement, card: card)
        } else {
            standardBillBox(statement, card: card)
        }
    }

    private func overdueBillBox(_ statement: CreditStatement, card: Account) -> some View {
        let paid = statement.paid >= 1 ? L("Sudah dibayar %@.", masked(statement.paid)) + " " : ""
        let ink = Color(light: 0xC2410C, dark: 0xFFA05C)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Tagihan cut-off %@", Self.dayMonth.string(from: statement.statementDate)))
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                    Text(masked(statement.remaining))
                        .font(.app(20, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(Color.appText)
                        .monospacedDigit()
                }
                Spacer(minLength: 8)
                Label {
                    Text("Lewat jatuh tempo")
                } icon: {
                    Image(systemName: "clock.fill").font(.system(size: 11, weight: .bold))
                }
                .font(.app(12, weight: .semibold))
                .foregroundStyle(ink)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Color(light: 0xFFE6D5, dark: 0x4A2A14), in: Capsule())
            }
            Text(paid + L("Jatuh tempo %@. Kalau sudah kamu bayar di luar Saku, catat supaya terpakai dan status kartu tetap akurat.", Self.dayMonth.string(from: statement.dueDate)))
                .font(.app(14))
                .foregroundStyle(Color.appBody)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button { payCard = card } label: {
                    Text("Bayar sekarang")
                        .font(.app(15, weight: .medium))
                        .foregroundStyle(Color.appText)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Color.appBackground, in: Capsule())
                        .overlay(Capsule().stroke(Color.appText.opacity(0.06), lineWidth: 1))
                }
                Button { recordCard = card } label: {
                    Text("Sudah, catat")
                        .font(.app(15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Color.appPrimary, in: Capsule())
                }
            }
            .buttonStyle(PressScaleStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .background(Color(light: 0xFFF6EE, dark: 0x2A1E15), in: RoundedRectangle(cornerRadius: 16))
    }

    private func paidBillBox(_ statement: CreditStatement, card: Account) -> some View {
        let payments = (accountTransactions[card.id] ?? []).filter {
            $0.date > statement.statementDate
                && (($0.type == .transfer && $0.counterpartyAccountId == card.id) || ($0.type == .cardPayment && $0.accountId == card.id))
        }
        let paidOn = payments.map(\.date).max()
        return Button { path.append(WalletHistoryRoute(account: card)) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Tagihan cut-off %@", Self.dayMonth.string(from: statement.statementDate)))
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                    Text("Lunas")
                        .font(.app(20, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(Color.appText)
                }
                Spacer(minLength: 8)
                if let paidOn {
                    Label(L("Dibayar %@", Self.dayMonth.string(from: paidOn)), systemImage: "checkmark.circle.fill")
                        .font(.app(13))
                        .foregroundStyle(Color.appPrimary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appTextTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(light: 0xF7F7F8, dark: 0x1C1C1E), in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(PressScaleStyle())
    }

    /// What's owed on the last statement; tap to pay it.
    private func standardBillBox(_ statement: CreditStatement, card: Account) -> some View {
        // Nothing printed yet but the card has debt: show what the next statement will bill.
        let upcoming = statement.status == .none && statement.unbilled >= 1
        let owes = statement.remaining >= 1 || upcoming
        // Named for the month it falls due: a 30 Sep cut-off due 20 Okt is the October bill.
        let month = Self.monthName.string(from: upcoming ? CreditStatement.billing(forPurchaseOn: Date(), card: card).due : statement.dueDate)
        let (status, color): (String, Color) = switch statement.status {
        case .overdue: (L("Lewat jatuh tempo"), .appError)
        case .unpaid, .partial: (L("Jatuh tempo %@", Self.dayMonth.string(from: statement.dueDate)), Color(hex: "C2410C"))
        case .paid: (L("Terima kasih"), .appPrimary)
        case .none: (upcoming ? L("Cetak %@", Self.dayMonth.string(from: statement.nextStatementDate)) : L("Belum ada tagihan"), .appTextSecondary)
        }
        return Button { payCard = card } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Tagihan %@", month))
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                    Text(owes ? masked(upcoming ? statement.unbilled : statement.remaining) : statement.status == .paid ? L("Lunas") : "Rp0")
                        .font(.app(20, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(Color.appText)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 8)
                Text(status)
                    .font(.app(13))
                    .foregroundStyle(color)
                    .multilineTextAlignment(.trailing)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appTextTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(light: 0xF7F7F8, dark: 0x1C1C1E), in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(PressScaleStyle())
        .animation(.settle(0.4), value: statement.remaining + statement.unbilled)
    }

    /// A status row, not a switch: there is always one main wallet, so it can't be turned off. On another wallet,
    /// tapping it opens the confirmation sheet.
    private func mainRow(_ account: Account) -> some View {
        let isMain = account.id == mainWalletID
        return Button { if !isMain { makingMain = account } } label: {
            HStack(spacing: 14) {
                Image(systemName: isMain ? "star.fill" : "star").font(.system(size: 20))
                    .foregroundStyle(isMain ? Color.appPrimary : Color.appTextSecondary).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isMain ? L("Dompet utama") : L("Jadikan dompet utama")).font(.app(17)).foregroundStyle(Color.appText)
                    if !isMain {
                        Text("Dipilih otomatis saat mencatat transaksi").font(.app(13)).foregroundStyle(Color.appTextSecondary)
                    }
                }
                Spacer(minLength: 8)
                if isMain {
                    Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.appPrimary)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .frame(minHeight: 56)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.appBorder.opacity(0.5)).frame(height: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .disabled(isMain)
        .animation(.spring(duration: 0.45, bounce: 0.35), value: isMain)
        .sensoryFeedback(.success, trigger: isMain) { _, now in now }
    }

    /// The main wallet, switched at once while a change is saving.
    private var mainWalletID: String? {
        pendingDefaultID ?? viewModel.accounts.first(where: \.isDefault)?.id
    }

    /// Closes the detail first so the card settles back, then it leaves the list.
    private func archive(_ account: Account) {
        closeDetail()
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            if await viewModel.toggleAccountArchive(id: account.id) {
                ToastCenter.shared.show(L("%@ diarsipkan", account.name))
            }
        }
    }

    /// Closes the detail, then deletes the wallet; a wallet with transactions is archived instead (the sheet offers it).
    private func remove(_ account: Account) {
        closeDetail()
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            if await viewModel.removeAccount(id: account.id) {
                ToastCenter.shared.show(L("%@ dihapus", account.name))
            }
        }
    }

    private func makeDefault(_ account: Account) {
        guard let userId = authViewModel.currentUser?.id else { return }
        pendingDefaultID = account.id
        Task {
            await viewModel.setDefaultAccount(id: account.id, userId: userId)
            pendingDefaultID = nil
            NotificationCenter.default.post(name: .dataDidChange, object: nil)
        }
    }


    private func masked(_ amount: Double) -> String {
        isBalanceVisible ? amount.formattedAsCurrency() : "Rp" + hiddenAmount
    }

    private func walletDetail(_ account: Account) -> some View {
        let fresh = viewModel.accounts.first { $0.id == account.id } ?? account
        let statement = viewModel.statement(for: fresh, transactions: accountTransactions[account.id] ?? [])
        return EditWalletView(
            account: fresh,
            transactionCount: accountTransactions[account.id]?.count ?? 0,
            billed: statement?.remaining, running: statement?.unbilled,
            capital: InvestmentSummary(account: fresh, transactions: accountTransactions[account.id] ?? []).capital,
            wealth: WealthSummary(accounts: viewModel.accounts),
            onUpdateValue: { updatingValue = fresh },
            onSave: { edit in await save(edit, on: fresh) },
            onArchive: { await viewModel.toggleAccountArchive(id: account.id) },
            onUnarchive: { await viewModel.toggleAccountArchive(id: account.id) },
            onDelete: { await viewModel.removeAccount(id: account.id) }
        )
    }

    /// Writes the Ubah dompet edits; a new saldo is logged as an adjustment by the view model.
    private func save(_ edit: WalletEdit, on account: Account) async -> Bool {
        guard let userId = authViewModel.currentUser?.id else { return false }
        let saved = await viewModel.rebalanceAccount(
            id: account.id, name: edit.name, type: account.type, icon: edit.icon, isArchived: account.isArchived,
            newBalance: edit.balance, oldBalance: account.balance, userId: userId,
            creditLimit: edit.creditLimit, dueDate: edit.dueDay.map(String.init), statementDay: edit.statementDay,
            color: edit.color, cardNetwork: edit.cardNetwork, billedDelta: edit.billedDelta, runningDelta: edit.runningDelta)
        if saved, edit.isDefault, !account.isDefault {
            await viewModel.setDefaultAccount(id: account.id, userId: userId)
        }
        return saved
    }

    // MARK: Data

    /// Same reload as after any write elsewhere.
    private func reload() {
        guard let userId = authViewModel.currentUser?.id else { return }
        Task {
            await viewModel.loadAccounts(userId: userId, forceRefresh: true)
            await syncAccountTransactions(userId: userId, forceRefresh: true)
            await syncCategories(userId: userId)
        }
    }

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
            let userTransactions = try await TransactionStore.shared.fetchAll(userId: userId)
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
            grouped[key] = grouped[key]?.newestFirst()
        }
        return grouped
    }
}

// MARK: - Card

extension Account {
    /// A known bank, e-wallet, card issuer or platform keeps its brand colour; the saved colour is for wallets without one.
    var walletColor: Color {
        if let icon, let brand = WalletIcon.allIcons.first(where: { $0.id == icon }) { return brand.color }
        if let color, !color.isEmpty { return Color(hex: color) }
        return WalletIcon.resolve(icon)?.color ?? .appPrimary
    }

    var walletShortName: String {
        WalletIcon.resolve(icon)?.shortName ?? String(name.prefix(4)).uppercased()
    }

    /// Asset name of the bank or e-wallet logo shown in the card's white box.
    var brandLogo: String? {
        guard let icon, let brand = WalletIcon.allIcons.first(where: { $0.id == icon }) else { return nil }
        switch brand.category {
        case .bank, .ewallet: return brand.id
        // Investment platforms use their logo once it is in the assets; until then the symbol shows.
        case .investment: return UIImage(named: brand.id) != nil ? brand.id : nil
        default: return nil
        }
    }

    /// Card network; cards saved before the network had its own field kept it as the icon.
    var networkId: String? {
        guard isCreditCard else { return nil }
        if let cardNetwork { return cardNetwork }
        return WalletIcon.icons(for: .credit).contains { $0.id == icon } ? icon : nil
    }

    var typeSymbol: String { isInvestment && icon == "emas" ? "dollarsign.circle" : type.cardSymbol }

    var typeLabel: String {
        switch type {
        case .cash: L("Cash")
        case .bank: L("Bank")
        case .ewallet: L("E-Wallet")
        case .credit: L("Kartu kredit")
        case .investment: L("Investasi")
        }
    }
}

extension Account.AccountType {
    /// Outline symbol drawn large and faint in the card's corner.
    var cardSymbol: String {
        switch self {
        case .bank: "building.columns"
        case .ewallet: "wallet.bifold"
        case .cash: "banknote"
        case .credit: "creditcard"
        case .investment: "chart.line.uptrend.xyaxis"
        }
    }
}

// MARK: - Card pieces (design 2a/3a)

/// The coloured card body: a soft light sweep from the top-left and the type symbol, faint, in the corner.
struct CardSurface: View {
    let color: Color
    let symbol: String
    var symbolTilted = false

    var body: some View {
        RoundedRectangle(cornerRadius: 22)
            .fill(color)
            .overlay(
                LinearGradient(stops: [.init(color: .white.opacity(0.18), location: 0), .init(color: .white.opacity(0), location: 0.55)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
            )
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: symbol)
                    .font(.system(size: 150, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.08))
                    .rotationEffect(.degrees(symbolTilted ? -8 : 0))
                    .offset(x: symbolTilted ? -2 : 18, y: symbolTilted ? 20 : 30)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0)], startPoint: .top, endPoint: .center), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.28), radius: 15, y: 14)
    }
}

/// White 46×30 box with the brand logo, or the type symbol in the card colour.
struct CardLogoBox: View {
    let logo: String?
    let symbol: String
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.white)
            .frame(width: 46, height: 30)
            .overlay {
                if let logo {
                    Image(logo).resizable().scaledToFit().frame(width: 34, height: 18)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(color)
                }
            }
    }
}

/// Network logo on a white 52×32 plate; GPN has no logo, so its name in red.
struct CardNetworkBadge: View {
    let network: String

    var body: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(.white)
            .frame(width: 52, height: 32)
            .overlay {
                if network == "gpn" {
                    Text("GPN")
                        .font(.app(13, weight: .heavy))
                        .tracking(0.5)
                        .foregroundStyle(Color(hex: "C8102E"))
                } else {
                    Image(network).resizable().scaledToFit().frame(width: 40, height: 22)
                }
            }
    }
}

/// Thin white limit-usage bar with "Terpakai …" and the percentage above it.
struct CardUsageBar: View {
    let usedText: String
    let share: Double
    var ink: Color = .white

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Terpakai \(usedText)")
                Spacer()
                Text("\(Int((min(max(share, 0), 1) * 100).rounded()))%")
            }
            .font(.app(12))
            .foregroundStyle(ink.opacity(0.82))
            .monospacedDigit()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(ink.opacity(0.25))
                    Capsule().fill(ink).frame(width: geo.size.width * min(max(share, 0), 1))
                }
            }
            .frame(height: 4)
        }
    }
}

/// Full-size brand-coloured wallet card (design 3a).
struct WalletCard: View {
    let account: Account
    var showsStripAmount: Bool
    var isBalanceVisible: Bool
    /// Credit cards: the limit-usage bar, shown while the card sits in its stack.
    var showsUsage = true
    /// Marks the main wallet on the top strip, so it shows even inside a stack.
    var isMain = false
    /// Investment wallets: the gain pill on the card ("+4%", or the rupiah gain while nothing was put in).
    var investmentPill: (symbol: String, text: String)?
    /// Investment wallets, on the open card: label and value lines under the name.
    var investmentFacts: [(String, String)] = []

    /// Text on the card: white, or dark on a bright brand colour.
    private var ink: Color { account.walletColor.isLight ? Color(hex: "1C1C1E") : .white }

    private var amountText: String {
        if account.needsCardDetails { return "—" }
        let value = account.isCreditCard ? (account.availableCredit ?? 0) : account.balance
        return isBalanceVisible ? value.formattedAsCurrency() : "Rp" + hiddenAmount
    }

    private func nameRow(compactBadge: Bool) -> some View {
        HStack(spacing: 8) {
            Text(account.name)
                .font(.app(17, weight: .semibold))
                .tracking(-0.2)
                .lineLimit(1)
                .fixedSize(horizontal: !compactBadge, vertical: false)
            if isMain {
                MainWalletBadge(compact: compactBadge)
                    .transition(.scale(scale: 0.4, anchor: .leading).combined(with: .opacity))
            }
        }
    }

    var body: some View {
        CardSurface(color: account.walletColor, symbol: account.typeSymbol)
            .overlay(alignment: .top) {
                HStack(spacing: 12) {
                    CardLogoBox(logo: account.brandLogo, symbol: account.typeSymbol, color: account.walletColor)
                    // The pill when it fits; on a tight strip, just the star.
                    ViewThatFits(in: .horizontal) {
                        nameRow(compactBadge: false)
                        nameRow(compactBadge: true)
                    }
                    Spacer(minLength: 8)
                    if showsStripAmount {
                        Text(amountText)
                            .font(.app(15, weight: .semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.22), value: showsStripAmount)
                .frame(height: 56)
                .padding(.horizontal, 20)
                .animation(.spring(duration: 0.45, bounce: 0.35), value: isMain)
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 10) {
                    if account.isCreditCard, showsUsage, let limit = account.creditLimit, limit > 0 {
                        CardUsageBar(usedText: isBalanceVisible ? account.balance.formattedAsCurrency() : "Rp" + hiddenAmount,
                                     share: account.balance / limit, ink: ink)
                            .transition(.opacity)
                    }
                    HStack(alignment: .bottom, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.isCreditCard ? L("Sisa limit") : account.isInvestment ? L("Nilai saat ini") : L("Saldo"))
                                .font(.app(12))
                                .foregroundStyle(ink.opacity(0.8))
                            Text(amountText)
                                .font(.app(32))
                                .tracking(-0.8)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        Spacer(minLength: 0)
                        if account.isCreditCard {
                            VStack(alignment: .trailing, spacing: 2) {
                                if let network = account.networkId {
                                    CardNetworkBadge(network: network).padding(.bottom, 6)
                                }
                                if account.needsCardDetails {
                                    Label(L("Lengkapi"), systemImage: "pencil")
                                        .font(.app(13, weight: .semibold))
                                        .padding(.horizontal, 11)
                                        .frame(height: 28)
                                        .background(ink.opacity(0.2), in: Capsule())
                                } else {
                                    Text("Jatuh tempo")
                                        .font(.app(12))
                                        .foregroundStyle(ink.opacity(0.8))
                                    Text(account.dueDay.map { L("Tgl %lld", $0) } ?? "—")
                                        .font(.app(15, weight: .semibold))
                                        .monospacedDigit()
                                }
                            }
                            .padding(.bottom, 3)
                        } else if let pill = investmentPill {
                            Label(pill.text, systemImage: pill.symbol)
                                .font(.app(13, weight: .semibold))
                                .monospacedDigit()
                                .lineLimit(1)
                                .padding(.horizontal, 11)
                                .frame(height: 28)
                                .background(ink.opacity(0.2), in: Capsule())
                                .padding(.bottom, 4)
                        } else {
                            Text(account.typeLabel)
                                .font(.app(12))
                                .foregroundStyle(ink.opacity(0.82))
                                .padding(.bottom, 5)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
                .animation(.easeInOut(duration: 0.25), value: showsUsage)
            }
            .overlay(alignment: .topLeading) {
                if !investmentFacts.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(investmentFacts.enumerated()), id: \.offset) { _, fact in
                            HStack(spacing: 6) {
                                Text(fact.0).foregroundStyle(ink.opacity(0.8))
                                Text(fact.1).fontWeight(.semibold).monospacedDigit()
                            }
                        }
                    }
                    .font(.app(13))
                    .lineLimit(1)
                    .padding(.horizontal, 20).padding(.top, 62)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: investmentFacts.isEmpty)
            .foregroundStyle(ink)
            .contentShape(RoundedRectangle(cornerRadius: 22))
            .accessibilityElement(children: .combine)
    }
}

/// Gold "Utama" pill on the main wallet's card.
struct MainWalletBadge: View {
    /// Star only, for a strip with little room.
    var compact = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill").font(.system(size: 9, weight: .bold))
            if !compact { Text("Utama").font(.app(11, weight: .semibold)) }
        }
        .foregroundStyle(Color(hex: "3D2E00"))
        .padding(.horizontal, compact ? 5.5 : 7)
        .frame(height: 20)
        .background(Color(hex: "F5B301"), in: Capsule())
        .fixedSize()
        .accessibilityLabel("Dompet utama")
    }
}

/// 46×30 mini card used in plain lists (design 3d).
struct MiniWalletCard: View {
    let account: Account

    var body: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(account.walletColor)
            .overlay(
                LinearGradient(colors: [.white.opacity(0.2), .white.opacity(0)], startPoint: .topLeading, endPoint: .center)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            )
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.white)
                    .frame(width: 18, height: 12)
                    .overlay {
                        if let logo = account.brandLogo {
                            Image(logo).resizable().scaledToFit().frame(width: 14, height: 8)
                        }
                    }
                    .padding(5)
            }
            .frame(width: 46, height: 30)
    }
}

// MARK: - Archived

/// Archived wallets, each with "Pulihkan" to bring it back to the list.
struct ArchivedWalletsView: View {
    let accounts: [Account]
    let onRestore: (Account) async -> Bool
    @AppStorage("isBalanceVisible") private var isBalanceVisible = true
    @State private var restoring: Set<String> = []
    @State private var openGroups: Set<Account.AccountType> = []

    private struct ArchiveGroup: Identifiable {
        let type: Account.AccountType
        let title: String
        let accounts: [Account]
        var id: Account.AccountType { type }
    }

    /// Same groups and order as the wallet page.
    private var groups: [ArchiveGroup] {
        let titled: [(Account.AccountType, String)] = [(.bank, L("Bank")), (.ewallet, L("E-Wallet")), (.cash, L("Cash")), (.investment, L("Investasi")), (.credit, L("Kartu kredit"))]
        return titled.compactMap { type, title in
            let list = accounts.filter { $0.type == type }
            return list.isEmpty ? nil : ArchiveGroup(type: type, title: title, accounts: list)
        }
    }

    var body: some View {
        ScrollView {
            if accounts.isEmpty {
                emptyState.padding(.top, 120).transition(.opacity)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    section(group)
                        .padding(.top, index == 0 ? 12 : 26)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .animation(.settle(0.4), value: accounts.map(\.id))
        }
        .background(Color.appBackground)
        .navigationTitle("Diarsipkan")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(_ group: ArchiveGroup) -> some View {
        let isOpen = openGroups.contains(group.type) || group.accounts.count < 2
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.46)) {
                    if openGroups.contains(group.type) { openGroups.remove(group.type) } else { openGroups.insert(group.type) }
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(group.title).font(.app(20, weight: .semibold)).tracking(-0.2).foregroundStyle(Color.appText)
                    Text("\(group.accounts.count)").font(.app(13)).foregroundStyle(Color.appTextTertiary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .allowsHitTesting(group.accounts.count >= 2)
            .padding(.bottom, 12)

            VStack(spacing: 0) {
                ForEach(Array(group.accounts.enumerated()), id: \.element.id) { index, account in
                    WalletCard(account: account, showsStripAmount: !isOpen && index != group.accounts.count - 1,
                               isBalanceVisible: isBalanceVisible)
                        .frame(height: 216)
                        .opacity(0.55)
                        .overlay(alignment: .topTrailing) {
                            if isOpen { restoreButton(account) }
                        }
                        .padding(.top, index == 0 ? 0 : isOpen ? 12 : 56 - 216)
                        .zIndex(Double(index))
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
    }

    private func restoreButton(_ account: Account) -> some View {
        Button {
            restoring.insert(account.id)
            Task {
                _ = await onRestore(account)
                restoring.remove(account.id)
            }
        } label: {
            Group {
                if restoring.contains(account.id) {
                    ProgressView().controlSize(.small).tint(Color.appText)
                } else {
                    Text("Pulihkan").font(.app(14, weight: .semibold))
                }
            }
            .foregroundStyle(Color.appText)
            .frame(width: 88, height: 34)
            .background(Color.white, in: Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(restoring.contains(account.id))
        .padding(.top, 11).padding(.trailing, 16)
    }

    /// The wallet page's stacked ghost cards, with the archive box in front.
    private var emptyState: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.appTextTertiary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .frame(height: 96).padding(.horizontal, 24)
                RoundedRectangle(cornerRadius: 14).fill(Color.appBackground)
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.appTextTertiary.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                    .frame(height: 100).padding(.horizontal, 12).padding(.top, 16)
                RoundedRectangle(cornerRadius: 14).fill(Color.appFill).frame(height: 100)
                    .overlay(Image(systemName: "archivebox").font(.system(size: 26)).foregroundStyle(Color.appTextTertiary))
                    .padding(.top, 32)
            }
            .frame(width: 176, height: 132)
            .accessibilityHidden(true)
            Text("Belum ada yang diarsipkan").font(.app(20, weight: .semibold)).tracking(-0.2).foregroundStyle(Color.appText)
                .padding(.top, 28)
            Text("Dompet yang diarsipkan disimpan di sini, lengkap dengan riwayatnya.")
                .font(.app(15)).foregroundStyle(Color.appTextSecondary).lineSpacing(3).multilineTextAlignment(.center)
                .padding(.top, 8)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity)
    }
}

/// Pushes a wallet's recurring bills.
struct WalletSubscriptionsRoute: Hashable {
    let account: Account
}

/// "Arsipkan <name>?" on the shared sheet frame.
private struct ArchiveWalletSheet: View {
    let name: String
    let onArchive: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SmartSheet(tone: .neutral, icon: "archivebox", title: L("Arsipkan %@?", name),
                   message: L("Dompet disembunyikan dari daftar dan total. Riwayat transaksi tetap tersimpan dan bisa dipulihkan kapan saja.")) {
            SmartSheetFooter(primary: L("Arsipkan"), secondary: L("Batal"), onPrimary: onArchive) { dismiss() }
        }
    }
}

/// "Jadikan <dompet> utama?": names the wallet that stops being the main one.
private struct MakeMainWalletSheet: View {
    let name: String
    let previous: String?
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SmartSheet(tone: .neutral, icon: "star", title: L("Jadikan %@ utama?", name),
                   message: previous.map { L("Transaksi baru memilih dompet ini lebih dulu. %@ tidak lagi jadi dompet utama.", $0) }
                       ?? L("Transaksi baru memilih dompet ini lebih dulu.")) {
            SmartSheetFooter(primary: L("Jadikan utama"), secondary: L("Batal"), onPrimary: onConfirm) { dismiss() }
        }
    }
}

/// "Hapus dompet ini?" from the open card's detail. A wallet with transactions can't be deleted, so it offers
/// Arsipkan saja instead.
private struct DeleteWalletSheet: View {
    let account: Account
    let transactionCount: Int
    let onDelete: () -> Void
    let onArchiveInstead: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var blocked: Bool { transactionCount > 0 }

    private var message: String {
        if blocked {
            return L("%@ punya %lld transaksi.", account.name, transactionCount) + " "
                + (account.isActive ? L("Arsipkan saja: dompet disembunyikan dari daftar dan total saldo, riwayatnya tetap tersimpan.")
                   : L("Dompet ini sudah diarsipkan, riwayatnya tetap tersimpan."))
        }
        let balance = account.balance
        let rp = balance.formattedAsCurrency()
        if account.isCreditCard {
            return balance > 0 ? L("%@ dan utang %@ akan dihapus dari daftar dan total.", account.name, rp)
                               : L("%@ akan dihapus dari daftar dompet.", account.name)
        }
        return balance != 0 ? L("%@ dan saldonya (%@) akan keluar dari total saldo.", account.name, rp)
                            : L("%@ akan dihapus dari daftar dompet.", account.name)
    }

    var body: some View {
        SmartSheet(tone: blocked ? .neutral : .destructive, icon: blocked ? "archivebox" : "trash",
                   title: blocked ? L("Dompet ini tidak bisa dihapus") : L("Hapus dompet ini?"), message: message,
                   extra: {
                       if !blocked, account.isInvestment, account.balance > 0 {
                           Text(L("Total aset akan berkurang %@", account.balance.formattedAsCurrency()))
                               .font(.app(15, weight: .semibold)).foregroundStyle(Color.appError)
                               .multilineTextAlignment(.center).padding(.top, 14)
                       }
                   }) {
            if !blocked {
                SmartSheetFooter(primary: L("Hapus"), destructive: true, secondary: L("Batal"), onPrimary: onDelete) { dismiss() }
            } else if account.isActive {
                SmartSheetFooter(primary: L("Arsipkan saja"), secondary: L("Batal"), onPrimary: onArchiveInstead) { dismiss() }
            } else {
                SmartSheetFooter(primary: nil, secondary: L("Tutup")) { dismiss() }
            }
        }
    }
}


/// Turns the system edge-swipe back off while `isOff` and this view is on screen. A plain view, not a child view
/// controller, so it never touches the navigation stack; the swipe comes back as soon as the view leaves the window.
private struct BackSwipeOff: UIViewRepresentable {
    let isOff: Bool

    final class Probe: UIView {
        var isOff = false { didSet { apply() } }
        private var nav: UINavigationController? {
            var r: UIResponder? = self
            while let next = r?.next { if let n = next as? UINavigationController { return n }; r = next }
            return nil
        }
        func apply() {
            let off = isOff && window != nil
            nav?.interactivePopGestureRecognizer?.isEnabled = !off
            if #available(iOS 26.0, *) { nav?.interactiveContentPopGestureRecognizer?.isEnabled = !off }
        }
        override func didMoveToWindow() { super.didMoveToWindow(); apply() }
        override func willMove(toWindow newWindow: UIWindow?) {
            if newWindow == nil {
                nav?.interactivePopGestureRecognizer?.isEnabled = true
                if #available(iOS 26.0, *) { nav?.interactiveContentPopGestureRecognizer?.isEnabled = true }
            }
        }
    }

    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) { view.isOff = isOff }
}
