import SwiftUI

/// Dompet: one card stack per wallet type (design 6c). Tap any card to open its detail like
/// design 5a (the card lifts to the top, every other card drops into a pile at the bottom);
/// tap a group title to fan its stack out or close it.
struct AccountListView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel: AccountListViewModel

    /// Opens the add-wallet sheet as soon as the page appears.
    private let startsAdding: Bool
    /// Beranda's navigation path: Dompet is pushed onto it and pushes its own pages there too,
    /// so the system back button and edge swipe work like everywhere else.
    @Binding private var path: NavigationPath

    init(viewModel: AccountListViewModel = AccountListViewModel(), startsAdding: Bool = false,
         path: Binding<NavigationPath>) {
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
    @State private var toastText = ""
    @State private var isToastShown = false
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
        let titled: [(Account.AccountType, String)] = [(.bank, L("Bank")), (.ewallet, L("E-Wallet")), (.cash, L("Cash")), (.investment, L("Investasi")), (.credit, L("Kartu kredit"))]
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
            .sheet(item: $archiving) { account in
                ArchiveWalletSheet(name: account.name) {
                    archiving = nil
                    archive(account)
                }
            }
            .toast(toastText, isShown: $isToastShown)
            .fullScreenCover(item: $payCard) { card in
                if let statement = viewModel.statement(for: card, transactions: accountTransactions[card.id] ?? []) {
                    PayCardBillSheet(card: card, statement: statement, wallets: viewModel.accounts,
                                     onPaid: { _, _, _ in showToast(L("Pembayaran tercatat")) })
                }
            }
            .fullScreenCover(item: $recordCard) { card in
                if let statement = viewModel.statement(for: card, transactions: accountTransactions[card.id] ?? []) {
                    PayCardBillSheet(card: card, statement: statement, wallets: viewModel.accounts, mode: .record,
                                     onPaid: { amount, _, isFull in
                        showToast(isFull ? L("%@ lunas · pembayaran tercatat", card.name) : L("Pembayaran %@ tercatat", amount.formattedAsCurrency()))
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
                        await NotificationManager.shared.resyncInvestmentReminders(accounts: viewModel.accounts, transactions: accountTransactions.values.flatMap { $0 })
                    }
                    return ok
                }
            }
            .sheet(item: $reminderOffer) { account in
                InvestmentReminderSheet(account: account, transactions: accountTransactions[account.id] ?? [], offer: true)
            }
            .onChange(of: notificationRouter.pendingInvestmentId) { _, _ in openReminderTarget() }
            .onChange(of: viewModel.accounts.count) { _, _ in openReminderTarget() }
            .onAppear { openReminderTarget() }
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
                    AddWalletView(isLimited: { FreeLimits.isWalletLimited($0, in: viewModel.accounts, isPlus: plus.isPlus) }) { wallet in
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

    /// Archive and balance; while a card's detail is open, only "Selesai".
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        if selectedID != nil {
            // Same top bar as the transaction detail: back on the left, Ubah on the right.
            ToolbarItem(placement: .topBarLeading) {
                Button(action: closeDetail) { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Kembali")
            }
            if let open = allCards.first(where: { $0.id == selectedID }), open.isCreditCard || open.isInvestment {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Ubah") { path.append(open) }
                        .font(.app(17, weight: .semibold))
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Selesai", action: closeDetail)
                        .fontWeight(.semibold)
                }
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
        let count = viewModel.accounts.filter(\.isActive).count
        let hasAssets = viewModel.accounts.contains { $0.isActive && $0.isInvestment }
        // With an investment wallet the big number is Total kekayaan; without one nothing changes.
        let total = hasAssets ? viewModel.totalBalance + viewModel.assetsTotal : viewModel.totalBalance
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(hasAssets ? "Total kekayaan" : "Total saldo").font(.app(15)).foregroundStyle(Color.appTextSecondary)
                Spacer()
                Text("\(count) dompet").font(.app(13)).foregroundStyle(Color.appTextTertiary)
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

            if hasAssets {
                HStack(alignment: .top, spacing: 12) {
                    heroPart(icon: "wallet.bifold", tint: .appTextSecondary, title: L("Saldo kas"), value: viewModel.totalBalance)
                    heroPart(icon: "chart.line.uptrend.xyaxis", tint: .appInvestment, title: L("Total aset"), value: viewModel.assetsTotal)
                }
                .padding(.top, 12)
            }

            if !activeCards.isEmpty {
                creditSummary.padding(.top, 18)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .onAppear { playOdometer(after: 0.3) }
    }

    /// "+4%" with a trend arrow, or the rupiah gain/loss when there is no capital to take a percentage of.
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

    private func heroPart(icon: String, tint: Color, title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(tint)
                Text(title).font(.app(13)).foregroundStyle(Color.appTextSecondary).lineLimit(1)
            }
            Text(masked(value)).font(.app(16, weight: .medium)).monospacedDigit().foregroundStyle(Color.appText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var creditSummary: some View {
        let debt = activeCards.reduce(0) { $0 + max($1.balance, 0) }
        let limit = activeCards.reduce(0) { $0 + ($1.creditLimit ?? 0) }
        let share = limit > 0 ? min(debt / limit, 1) : 0
        // One card: its due day in the subtitle. Several: each card gets its own row below.
        let nextDue = activeCards.count == 1 ? activeCards.first.flatMap(dueDate(of:)) : nil
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: "1A1F71"))
                    .frame(width: 32, height: 32)
                    .overlay(Image(systemName: "creditcard").font(.system(size: 15)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Kartu kredit").font(.app(15, weight: .semibold))
                    Text(nextDue.map { L("Terpakai · tempo %@", Self.dayMonth.string(from: $0)) }
                         ?? (activeCards.count > 1 ? L("Terpakai · %lld kartu", activeCards.count) : L("Terpakai")))
                        .font(.app(12))
                        .foregroundStyle(Color.appTextSecondary)
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                HStack(spacing: 0) {
                    Text("Rp")
                    if isBalanceVisible {
                        OdometerText(text: debt.formattedAsDigits(), digitHeight: 22,
                                     font: .app(17, weight: .semibold), delay: 0.35, isOn: odometerOn)
                    } else {
                        Text(hiddenAmount)
                    }
                }
                .font(.app(17, weight: .semibold))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(light: 0xE5E5EA, dark: 0x3A3A3C))
                    Capsule().fill(Color.appText)
                        .frame(width: geo.size.width * (odometerOn ? share : 0))
                        .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 1.1).delay(0.5), value: odometerOn)
                }
            }
            .frame(height: 4)
            HStack {
                Text("\(Int((share * 100).rounded()))% dari limit \(masked(limit))")
                Spacer()
                Text("Sisa \(masked(max(limit - debt, 0)))")
            }
            .font(.app(12))
            .foregroundStyle(Color.appTextSecondary)
            .monospacedDigit()
            if activeCards.count > 1 {
                Divider().padding(.vertical, 2)
                ForEach(activeCards) { card in
                    HStack(spacing: 8) {
                        Circle().fill(card.walletColor).frame(width: 8, height: 8)
                        Text(card.name).foregroundStyle(Color.appText).lineLimit(1)
                        if let due = dueDate(of: card) {
                            Text(L("tempo %@", Self.dayMonth.string(from: due))).foregroundStyle(Color.appTextSecondary)
                        }
                        Spacer(minLength: 8)
                        Text(masked(max(card.balance, 0))).foregroundStyle(Color.appText)
                    }
                    .font(.app(13))
                    .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(light: 0xF7F7F8, dark: 0x1C1C1E), in: RoundedRectangle(cornerRadius: 16))
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
            .disabled(group.accounts.count < 2)
            .accessibilityHint(group.accounts.count < 2 ? "" : isOpen ? L("Tutup tumpukan") : L("Buka tumpukan"))
            .padding(.bottom, group.type == .investment && InvestmentAllocation(accounts: group.accounts) != nil ? 4 : 12)

            if group.type == .investment, let allocation = InvestmentAllocation(accounts: group.accounts) {
                InvestmentAllocationView(allocation: allocation, isBalanceVisible: isBalanceVisible)
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
                    ScrollView {
                        detailContent(account, isOpen: shown)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 24)
                    }
                    .scrollIndicators(.hidden)
                    .frame(height: max(pileTop - contentTop - 8, 0))
                    .padding(.top, contentTop)
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
                        investmentPill: investmentPill(for: account)
                    )
                    .frame(height: cardHeight)
                    .scaleEffect(layout.scale, anchor: .top)
                    .padding(.horizontal, 24)
                    .offset(y: layout.y)
                    .zIndex(layout.z)
                    .animation(cardAnimation.delay(layout.delay), value: selectedID)
                    .onTapGesture { if shown { select(account.id) } }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(selectedID == account.id ? L("Tutup detail") : L("Buka dompet"))
                }
            }
        }
        // Span to the screen bottom so `safeAreaInsets.bottom` reports the tab bar height.
        .ignoresSafeArea(.container, edges: .bottom)
        .onAppear { selectedID = lastSelectedID }
    }

    /// Design 1a: four actions, the bill, the main-wallet switch and the way into the
    /// wallet's recurring bills.
    private func detailContent(_ account: Account, isOpen: Bool) -> some View {
        let statement = viewModel.statement(for: account, transactions: accountTransactions[account.id] ?? [])
        if account.isInvestment {
            return AnyView(InvestmentDetailContent(
                account: account, transactions: accountTransactions[account.id] ?? [], isBalanceVisible: isBalanceVisible,
                onDeposit: { assetTransfer = AssetTransferRoute(account: account, mode: .deposit) },
                onWithdraw: { assetTransfer = AssetTransferRoute(account: account, mode: .withdraw) },
                onUpdateValue: { updatingValue = account },
                onHistory: { path.append(WalletHistoryRoute(account: account)) }))
        }
        if account.isCreditCard {
            return AnyView(CardDetailContent(
                card: account, statement: statement,
                subscriptions: viewModel.subscriptions.filter { $0.accountId == account.id },
                isBalanceVisible: isBalanceVisible,
                onPay: { payCard = account }, onRecord: { recordCard = account },
                onSubscriptions: { path.append(WalletSubscriptionsRoute(account: account)) },
                onHistory: { path.append(WalletHistoryRoute(account: account)) }))
        }
        return AnyView(VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                if account.isCreditCard {
                    detailAction(L("Bayar"), icon: "creditcard", isPrimary: true) { payCard = account }
                } else {
                    detailAction(L("Transfer"), icon: "arrow.left.arrow.right") { transferFrom = account }
                }
                detailAction(L("Riwayat"), icon: "clock.arrow.circlepath") { path.append(WalletHistoryRoute(account: account)) }
                detailAction(L("Ubah"), icon: "pencil") { path.append(account) }
                detailAction(L("Arsipkan"), icon: "archivebox") { archiving = account }
            }
            .padding(.horizontal, -8)

            if let statement {
                billBox(statement, card: account)
                    .padding(.top, 18)
            }

            defaultToggle(account)
                .padding(.top, 14)

            if account.type != .cash && !account.isInvestment {
                subscriptionsLink(account)
                    .padding(.top, 6)
            }
        })
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

    /// The system switch: on makes this the main wallet; there's always one, so it can't
    /// be switched off here.
    private func defaultToggle(_ account: Account) -> some View {
        let isDefault = account.id == mainWalletID
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Dompet utama")
                    .font(.app(16))
                    .foregroundStyle(Color.appText)
                Text("Dipilih otomatis saat mencatat transaksi")
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
            }
            Spacer(minLength: 8)
            Toggle("Dompet utama", isOn: Binding(get: { isDefault }, set: { if $0 { makeDefault(account) } }))
                .labelsHidden()
                .tint(.appPrimary)
                .allowsHitTesting(!isDefault)
        }
        .frame(height: 64)
        .sensoryFeedback(.success, trigger: isDefault) { _, now in now }
    }

    private func subscriptionsLink(_ account: Account) -> some View {
        let active = viewModel.subscriptions.filter { $0.accountId == account.id && $0.isActive }
        let monthly = active.reduce(0) { $0 + $1.monthlyAmount }
        return Button { path.append(WalletSubscriptionsRoute(account: account)) } label: {
            HStack(spacing: 14) {
                Image(systemName: "repeat")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.appBody)
                    .frame(width: 40, height: 40)
                    .background(Color.appFill, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tagihan berulang")
                        .font(.app(16))
                        .foregroundStyle(Color.appText)
                    Text(active.isEmpty ? L("Belum ada") : L("%lld tagihan · %@/bulan", active.count, masked(monthly)))
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appTextTertiary)
            }
            .frame(height: 64)
            .overlay(alignment: .top) { Rectangle().fill(Color.appDivider).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Color.appDivider).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
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
                showToast(L("%@ diarsipkan", account.name))
            }
        }
    }

    private func showToast(_ text: String) {
        toastText = text
        isToastShown = true
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

    private func detailAction(_ title: String, icon: String, isPrimary: Bool = false,
                              perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(isPrimary ? .white : Color.appText)
                    .frame(width: 52, height: 52)
                    .background(isPrimary ? Color.appPrimary : Color.appFill, in: Circle())
                Text(title)
                    .font(.app(13))
                    .foregroundStyle(Color.appBody)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressScaleStyle())
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
            grouped[key] = grouped[key]?.newestFirst()
        }
        return grouped
    }
}

// MARK: - Card

extension Account {
    var walletColor: Color {
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

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Terpakai \(usedText)")
                Spacer()
                Text("\(Int((min(max(share, 0), 1) * 100).rounded()))%")
            }
            .font(.app(12))
            .foregroundStyle(.white.opacity(0.82))
            .monospacedDigit()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule().fill(.white).frame(width: geo.size.width * min(max(share, 0), 1))
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
                                     share: account.balance / limit)
                            .transition(.opacity)
                    }
                    HStack(alignment: .bottom, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.isCreditCard ? L("Sisa limit") : account.isInvestment ? L("Nilai saat ini") : L("Saldo"))
                                .font(.app(12))
                                .foregroundStyle(.white.opacity(0.8))
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
                                        .background(.white.opacity(0.2), in: Capsule())
                                } else {
                                    Text("Jatuh tempo")
                                        .font(.app(12))
                                        .foregroundStyle(.white.opacity(0.8))
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
                                .background(.white.opacity(0.2), in: Capsule())
                                .padding(.bottom, 4)
                        } else {
                            Text(account.typeLabel)
                                .font(.app(12))
                                .foregroundStyle(.white.opacity(0.82))
                                .padding(.bottom, 5)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
                .animation(.easeInOut(duration: 0.25), value: showsUsage)
            }
            .foregroundStyle(.white)
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

    var body: some View {
        ScrollView {
            if accounts.isEmpty {
                EmptyMessage(icon: "archivebox", title: L("Belum ada yang diarsipkan"),
                             message: L("Dompet yang diarsipkan disimpan di sini, lengkap dengan riwayatnya."))
                    .padding(.horizontal, 40)
                    .padding(.top, 120)
                    .transition(.opacity)
            }
            LazyVStack(spacing: 0) {
                ForEach(accounts) { account in
                    HStack(spacing: 14) {
                        MiniWalletCard(account: account)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name)
                                .font(.app(16, weight: .medium))
                                .foregroundStyle(Color.appText)
                            Text(isBalanceVisible ? account.balance.formattedAsCurrency() : "Rp" + hiddenAmount)
                                .font(.app(13))
                                .monospacedDigit()
                                .foregroundStyle(Color.appTextSecondary)
                        }
                        Spacer()
                        Button {
                            restoring.insert(account.id)
                            Task {
                                _ = await onRestore(account)
                                restoring.remove(account.id)
                            }
                        } label: {
                            Group {
                                if restoring.contains(account.id) {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Text("Pulihkan").font(.app(14, weight: .semibold))
                                }
                            }
                            .foregroundStyle(Color.appText)
                            .frame(width: 88, height: 34)
                            .background(Color.appFill, in: Capsule())
                        }
                        .buttonStyle(PressScaleStyle())
                        .disabled(restoring.contains(account.id))
                    }
                    .padding(.vertical, 12)
                    .rowSeparator()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 24)
            .animation(.settle(0.4), value: accounts.map(\.id))
        }
        .background(Color.appBackground)
        .navigationTitle("Diarsipkan")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Pushes a wallet's recurring bills.
struct WalletSubscriptionsRoute: Hashable {
    let account: Account
}

/// "Arsipkan <name>?" as a short sheet with one black button.
private struct ArchiveWalletSheet: View {
    let name: String
    let onArchive: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Arsipkan \(name)?")
                    .font(.app(17, weight: .semibold))
                Spacer()
                Button("Batal") { dismiss() }
                    .font(.app(17))
                    .foregroundStyle(Color.appPrimary)
            }
            .frame(height: 48)
            Text("Dompet disembunyikan dari daftar dan total. Riwayat transaksi tetap tersimpan dan bisa dipulihkan kapan saja.")
                .font(.app(15))
                .lineSpacing(3)
                .foregroundStyle(Color.appBody)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onArchive) {
                Label("Arsipkan", systemImage: "archivebox")
                    .font(.app(17, weight: .semibold))
                    .foregroundStyle(Color.appBackground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.appText, in: Capsule())
            }
            .buttonStyle(PressScaleStyle())
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .presentationDetents([.height(250)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }
}
