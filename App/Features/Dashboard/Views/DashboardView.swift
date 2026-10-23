import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel: DashboardViewModel
    @AppStorage("isBalanceVisible") private var isBalanceVisibleStorage = true

    init(viewModel: DashboardViewModel = DashboardViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    @State private var isBalanceVisible = true
    @State private var showAddSheet = false
@AppStorage(SmartTrackerWays.quickKey) private var smartQuickOn = true
@StateObject private var tabAvatar = TabAvatarCache()
@ObservedObject private var draftStore = DraftStore.shared
@State private var showsConsent = false
    /// Drives the "Bulan ini" grow-in; reset and set again to replay.
    @State private var isChartShown = false
    /// Day index picked in the "Bulan ini" chart; nil means today.
    @State private var selectedDay: Int?
    @State private var showAllBudgets = false
    @State private var selectedTab: AppTab = .home
    /// Beranda's stack; Dompet is pushed here from the hero's pill.
    @State private var homePath = NavigationPath()
    @State private var didWelcome = false
    /// "Tambah dompet" on the empty Beranda opens Dompet straight into the add sheet.
    @State private var addsWalletOnOpen = false
    @AppStorage(HomeBalanceSetting.key) private var homeBalanceMode = HomeBalanceMode.cash.rawValue
    @State private var showsSafeInfo = false
    /// Catat tagihan for an overdue card bill, from the banner or a notification.
    /// Kept as the bill it was opened with, so the sheet survives the reload after paying.
    @State private var recordCard: OverdueCardBill?
    @State private var toastText = ""
    @State private var isToastShown = false
    /// The tray pill says "Baru masuk" for a moment after drafts land (design 1a).
    @State private var isTrayFresh = false
    @State private var trayBump = false
    @ObservedObject private var notificationRouter = NotificationRouter.shared
    @Environment(\.scenePhase) private var scenePhase

    enum AppTab: Hashable {
        case home, transactions, budget, profile
        /// The + beside the bar; selecting it opens the form instead of a page.
        case add
    }

    /// Pages pushed on Beranda by value.
    enum HomeRoute: Hashable {
        case wallets
        case drafts
    }

    var body: some View {
        tabs
        .onChange(of: showAddSheet) { _, isShown in if isShown { Haptics.add() } }
        .tint(.appPrimary)
        .onAppear {
            if !didWelcome {
                didWelcome = true
                Haptics.welcome()
            }
            isBalanceVisible = isBalanceVisibleStorage
            DraftStore.shared.isGuest = authViewModel.currentUser?.isGuest == true
            if let userId = authViewModel.currentUser?.id {
                Task {
                    await SubscriptionBillingService.processDueBills(userId: userId)
                    await SubscriptionBillingService.resyncNotifications(userId: userId)
                    await viewModel.loadDashboard(userId: userId)
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Ingatan follows the account: pick up what other devices learned while this one was away
            if phase == .active { Task { await DraftStore.shared.syncMemory() } }
        }
        .onChange(of: isBalanceVisibleStorage) { _, newValue in
            isBalanceVisible = newValue
        }
        .onReceive(NotificationCenter.default.publisher(for: .dataDidChange)) { _ in
            if let userId = authViewModel.currentUser?.id {
                Task {
                    await viewModel.loadDashboard(userId: userId, forceRefresh: true)
                }
            }
        }
        .fullScreenCover(item: $recordCard) { bill in
            PayCardBillSheet(card: bill.card, statement: bill.statement, wallets: viewModel.accounts, mode: .record,
                             onPaid: { amount, _, isFull in
                toastText = isFull ? L("%@ lunas · pembayaran tercatat", bill.card.name) : L("Pembayaran %@ tercatat", amount.formattedAsCurrency())
                isToastShown = true
            })
        }
        .onChange(of: notificationRouter.pendingCardId) { _, _ in openPendingRecord() }
        .onChange(of: notificationRouter.opensDrafts) { _, _ in openDraftsIfRequested() }
        .onChange(of: notificationRouter.pendingInvestmentId) { _, id in if id != nil { openWalletsPage() } }
        .onChange(of: draftStore.drafts.count) { old, new in
            // "Baru masuk" on the tray pill right after drafts land (design 1a)
            guard new > old else { return }
            withAnimation(.settle(0.25)) { isTrayFresh = true; trayBump = true }
            withAnimation(.settle(0.3).delay(0.16)) { trayBump = false }
            Task {
                try? await Task.sleep(for: .seconds(2.6))
                withAnimation(.settle(0.3)) { isTrayFresh = false }
            }
        }
        .overlay {
            if selectedTab != .home || homePath.isEmpty, viewModel.hasLoadedOnce, smartQuickOn, let userId = authViewModel.currentUser?.id {
                // the gate is watched inside, so a page opening or closing does not re-run this whole screen
                SmartButtonGated {
                    SmartTrackerHomeOverlay(userId: userId, isFresh: viewModel.recentTransactions.isEmpty, onOpenQueue: { openDraftsPage() }) { text in
                        toastText = text
                        isToastShown = true
                    }
                }
            }
        }
        .onAppear { openDraftsIfRequested(); askConsentForSharedText(); announceReferralReward() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in askConsentForSharedText(); announceReferralReward() }
        .sheet(isPresented: $showsConsent) {
            SmartTrackerConsentSheet(profileId: authViewModel.currentUser.flatMap { UUID(uuidString: $0.id) }) {
                showsConsent = false
                DraftStore.shared.ingestSharedText()
                openDraftsPage()
            }
        }
        .onChange(of: viewModel.overdueBills.map(\.id)) { _, _ in openPendingRecord() }
        .onReceive(NotificationCenter.default.publisher(for: .openFirstEntry)) { _ in openFirstEntry() }
        .toast(toastText, isShown: $isToastShown)
        .fullScreenCover(isPresented: $showAddSheet) {
            if let userId = authViewModel.currentUser?.id {
                AddTransactionView(
                    categories: viewModel.categories,
                    accounts: viewModel.accounts,
                    userId: userId,
                    onSave: {
                        Task {
                            await viewModel.loadDashboard(userId: userId, forceRefresh: true)
                        }
                    }
                )
            }
        }
    }

    /// A small notice when a friend's first transaction made this account's AI help grow (Fitur 2 US3). Free real
    /// accounts only: guests take no part and Plus has unlimited help, so no promise is made to them.
    private func announceReferralReward() {
        guard authViewModel.currentUser?.isGuest == false, !PlusStore.shared.isPlus else { return }
        Task {
            guard let summary = try? await SupabaseSDK.fetchReferralSummary() else { return }
            let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX"); format.dateFormat = "yyyy-MM"
            let defaults = UserDefaults.standard
            let result = ReferralSummary.rewardDelta(thisMonth: summary.thisMonth, monthKey: format.string(from: Date()),
                                                     stored: defaults.string(forKey: "referralRewardSeen"))
            defaults.set(result.stored, forKey: "referralRewardSeen")
            guard result.newFriends > 0 else { return }
            toastText = L("Temanmu mencatat transaksi pertama. +%lld jatah AI masuk.", result.newFriends * ReferralSummary.perFriend)
            isToastShown = true
        }
    }

    /// Text was shared to Saku before the user agreed to Smart Tracker: ask now, then read it.
    private func askConsentForSharedText() {
        guard !SmartTrackerConsent.isGranted, ShareInbox.hasItems, authViewModel.isAuthenticated else { return }
        showsConsent = true
    }

    /// Tapping the "new drafts" notification: read what was shared, then show Konfirmasi transaksi.
    private func openDraftsIfRequested() {
        guard notificationRouter.opensDrafts else { return }
        notificationRouter.opensDrafts = false
        DraftStore.shared.ingestSharedText()
        openDraftsPage()
    }

    /// "Catat pengeluaran pertamamu": the Smart Tracker bar when it is on, the add form when it is not.
    private func openFirstEntry() {
        guard SmartTrackerConsent.isGranted, smartQuickOn else { showAddSheet = true; return }
        selectedTab = .home
        if viewModel.hasLoadedOnce {
            NotificationCenter.default.post(name: .openSmartTrackerBar, object: nil)
        } else {
            SmartButtonGate.shared.opensBarOnShow = true
        }
    }

    /// A value reminder was tapped: Dompet opens on the Beranda stack and shows Perbarui nilai there.
    private func openWalletsPage() {
        selectedTab = .home
        var path = NavigationPath()
        path.append(HomeRoute.wallets)
        homePath = path
    }

    /// Konfirmasi transaksi is a page on the Beranda stack, not a sheet.
    private func openDraftsPage() {
        selectedTab = .home
        // one assignment, not reset-then-append: two changes to the path in a row can corrupt a stack that is mid-transition
        var path = NavigationPath()
        path.append(HomeRoute.drafts)
        homePath = path
    }

    /// "Sudah, catat" on the notification: open its card once the bills have loaded.
    private func openPendingRecord() {
        guard let id = notificationRouter.pendingCardId,
              let bill = viewModel.overdueBills.first(where: { $0.card.id == id }) else { return }
        notificationRouter.pendingCardId = nil
        recordCard = bill
    }

    // MARK: - Tabs

    /// The system Liquid Glass tab bar: icon-only tabs with + in the middle and the
    /// initials avatar for Profil.
    private var tabs: some View {
        TabView(selection: Binding(
            get: { selectedTab },
            set: { tab in
                if tab == .add { showAddSheet = true } else { selectedTab = tab }
            }
        )) {
            mainTabs
        }
    }

    @TabContentBuilder<AppTab>
    private var mainTabs: some TabContent<AppTab> {
        Tab(value: AppTab.home) {
            NavigationStack(path: $homePath) {
                mainContent
                    .navigationDestination(for: HomeRoute.self) { route in
                        switch route {
                        case .wallets:
                            AccountListView(startsAdding: addsWalletOnOpen, path: $homePath)
                        case .drafts:
                            if let userId = authViewModel.currentUser?.id { DraftQueueView(userId: userId).detailPage() }
                        }
                    }
            }
            .onChange(of: homePath.count) { _, count in if count == 0 { addsWalletOnOpen = false } }
        } label: { tabLabel(L("Beranda"), "house.fill") }
        Tab(value: AppTab.transactions) {
            TransactionListView(isActive: selectedTab == .transactions) { showAddSheet = true }
        } label: { tabLabel(L("Transaksi"), "list.bullet") }
        Tab(value: AppTab.add) {
            Color.clear
        } label: { tabLabel(L("Tambah transaksi"), "plus") }
        Tab(value: AppTab.budget) {
            BudgetListView()
        } label: { tabLabel(L("Budget"), "chart.pie.fill") }
        Tab(value: AppTab.profile) {
            ProfileView(cash: viewModel.balance, assets: viewModel.assetsTotal)
        } label: {
            Label {
                Text("Profil")
            } icon: {
                Image(uiImage: avatarImage).renderingMode(.original)
            }
            .labelStyle(.iconOnly)
        }
    }

    private func tabLabel(_ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon).labelStyle(.iconOnly)
    }

    /// The initials avatar drawn as a bitmap, since tab items only take images.
    /// Drawn again only when the initials or the photo change: this runs on every pass over the tabs, and a push
    /// or pop of a page triggers several.
    @MainActor
    private var avatarImage: UIImage {
        tabAvatar.image(initials: authViewModel.currentUser?.initials ?? "U", photo: authViewModel.avatarImage)
    }

    // MARK: - Beranda

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                homeHeader

                if let error = viewModel.errorMessage, !viewModel.hasLoadedOnce {
                    errorStateView(message: error)
                        .padding(24)
                } else if !viewModel.hasLoadedOnce {
                    homeSkeleton
                } else {
                    if let error = viewModel.errorMessage {
                        ErrorBanner(message: error).padding(.horizontal, 24).padding(.top, 16)
                    }
                    PlusBannerView()
                    summarySection
                    TrySmartTrackerCard()
                    GuestSaveCard(transactionCount: viewModel.currentMonthTransactionCount)
                    if !viewModel.overdueBills.isEmpty {
                        OverdueBillBanner(bills: viewModel.overdueBills, isBalanceVisible: isBalanceVisible) { bill in
                            recordCard = bill
                        }
                    }
                    if hasNoWallets {
                        firstWalletCard
                        emptyHealthSection
                            .padding(.bottom, 90)
                    } else {
                        SectionDivider()
                        cashFlowSection
                        SectionDivider()
                        healthSection
                        SectionDivider()
                        monthSection
                        SectionDivider()
                        budgetSection
                            .padding(.bottom, 90)
                    }
                }
            }
            // exactly as wide as the screen: something wider than it (a chart, a long amount) can no longer
            // make Beranda scroll sideways
            .containerRelativeFrame(.horizontal)
            .animation(.easeInOut(duration: 0.3), value: viewModel.hasLoadedOnce)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .background(Color.appBackground)
        .refreshable {
            if let userId = authViewModel.currentUser?.id {
                await viewModel.loadDashboard(userId: userId, forceRefresh: true)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    /// Konfirmasi transaksi lives in the header: a plain tray when empty, a green pill with the count when drafts wait.
    @ViewBuilder private var draftTray: some View {
        if smartQuickOn, authViewModel.currentUser != nil {
            let count = draftStore.drafts.count
            Button { openDraftsPage() } label: {
                if count == 0 {
                    Image(systemName: "tray").font(.system(size: 22)).foregroundStyle(Color.appTextSecondary)
                        .frame(width: 40, height: 40)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "tray").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 30, height: 30).background(Color.stGreen, in: Circle())
                            .background { if isTrayFresh { STPulse(color: .stGreen) } }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(L("%lld draf", count)).font(.app(15, weight: .semibold)).monospacedDigit()
                            Text(isTrayFresh ? L("Baru masuk") : "Cek dan simpan")
                                .font(.app(11)).foregroundStyle(isTrayFresh ? Color.stGreen : Color.appTextSecondary)
                        }
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.appTextTertiary)
                    }
                    .foregroundStyle(Color.appText)
                    .padding(.leading, 5).padding(.trailing, 12).frame(height: 40)
                    .background(Color.stChip, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
                    // fresh drafts land with a small bump (design 1a)
                    .scaleEffect(trayBump ? 1.12 : 1)
                    .animation(.spring(duration: 0.3, bounce: 0.6), value: trayBump)
                }
            }
            .buttonStyle(PressScaleStyle())
            .padding(.trailing, 6)
            .accessibilityLabel(L("Konfirmasi transaksi"))
        }
    }

    private var homeHeader: some View {
        HStack {
            Text("Saku")
                .font(.wordmark(19))
                .tracking(-0.5)
                .foregroundStyle(Color.appText)
            Spacer()
            draftTray
            Button {
                withAnimation(.smooth) { isBalanceVisible.toggle() }
                isBalanceVisibleStorage = isBalanceVisible
            } label: {
                // eye.slash is taller than eye; a fixed frame keeps the header (and everything below) still.
                Image(systemName: isBalanceVisible ? "eye" : "eye.slash")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.appText)
                    .frame(width: 28, height: 25)
            }
            .accessibilityLabel(isBalanceVisible ? L("Sembunyikan saldo") : L("Tampilkan saldo"))
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    /// 13a: labels stay, only the numbers shimmer.
    private var homeSkeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Total saldo")
                        .font(.app(15))
                        .foregroundStyle(Color.appTextSecondary)
                    Spacer()
                    SkeletonBlock(width: 128, height: 48, radius: 24)
                }
                SkeletonBlock(width: 250, height: 52, radius: 10)
                    .padding(.top, 6)
                RoundedRectangle(cornerRadius: 3).fill(Color.appFill)
                    .frame(height: 6)
                    .padding(.top, 28)
                HStack {
                    SkeletonBlock(width: 74, height: 14)
                    Spacer()
                    SkeletonBlock(width: 74, height: 14)
                    Spacer()
                    SkeletonBlock(width: 74, height: 14)
                }
                .padding(.top, 14)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 36)

            SectionDivider()

            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: L("Kesehatan finansial"))
                SkeletonBlock(width: 110, height: 50, radius: 10)
                    .padding(.top, 14)
                SegmentBar(value: 0, count: 40, height: 22, spacing: 3)
                    .padding(.top, 16)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        }
        .accessibilityLabel("Memuat")
    }

    /// 13b: a new user with no wallets gets one card pointing at the first wallet.
    private var firstWalletCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tambah dompet pertamamu")
                .font(.app(17, weight: .semibold))
                .foregroundStyle(Color.appText)
            Text("Masukkan saldo rekening bank, e-wallet, atau uang tunai supaya total saldo bisa dihitung.")
                .font(.app(15))
                .foregroundStyle(Color.appTextSecondary)
                .lineSpacing(3)
            EmptyStateButton(title: L("Tambah dompet"), isFullWidth: true) {
                addsWalletOnOpen = true
                homePath.append(HomeRoute.wallets)
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 24)
    }

    private var emptyHealthSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: L("Kesehatan finansial"))
            SegmentBar(value: 0, count: 40, height: 22, spacing: 3)
                .padding(.top, 16)
            Text("Skor muncul setelah kamu mencatat pemasukan atau pengeluaran.")
                .font(.app(15))
                .foregroundStyle(Color.appTextSecondary)
                .lineSpacing(3)
                .padding(.top, 12)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
    }

    private func errorStateView(message: String) -> some View {
        ErrorStateView(message: message) {
            if let userId = authViewModel.currentUser?.id {
                Task {
                    await viewModel.loadDashboard(userId: userId, forceRefresh: true)
                }
            }
        }
    }

    // MARK: Summary

    /// Big total: kas by default, kas + aset when Profil says so.
    private var summarySection: some View {
        let showsWealth = viewModel.hasInvestments && homeBalanceMode == HomeBalanceMode.all.rawValue
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("Total saldo")
                    .font(.app(15))
                    .foregroundStyle(Color.appTextSecondary)
                Spacer()
                walletsButton
            }
            HeroAmount(value: showsWealth ? viewModel.wealth : viewModel.balance, size: .hero,
                       color: hasNoWallets ? .appTextTertiary : .appText,
                       prefixColor: hasNoWallets ? .appTextTertiary : .appTextSecondary,
                       isVisible: isBalanceVisible, weight: .ultraLight)
                .padding(.top, 2)
        }
        .padding(.horizontal, 24)
        .padding(.top, 36)
        .padding(.bottom, hasNoWallets ? 32 : 36)
    }

    // MARK: Cash flow

    /// "Arus kas 25 Sep – 24 Okt": a green/red bar for money in vs out, Masuk · Keluar · Net and Aman dipakai.
    private var cashFlowSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: L("Arus kas %@", PaydayCycle.current.label()))
                NavigationLink("Statistik") { StatistikView(onOpenBudget: { selectedTab = .budget }).detailPage() }
                    .font(.app(15))
                    .foregroundStyle(Color.appPrimary)
            }

            FlowSplitBar(income: viewModel.totalIncome, expense: viewModel.totalExpense)
                .padding(.top, 14)

            HStack {
                flowStat(Lx("Masuk", en: "In"), viewModel.totalIncome)
                Spacer()
                flowStat(Lx("Keluar", en: "Out"), viewModel.totalExpense)
                Spacer()
                flowStat("Net", viewModel.netCashflow, signed: true)
            }
            .padding(.top, 12)

            safeToSpendCard
                .padding(.top, 14)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    // MARK: Safe to spend

    /// Rp amount honouring the eye toggle; negative gets a minus sign.
    private func maskedAmount(_ amount: Double, negative: Bool = false) -> String {
        guard isBalanceVisible else { return hiddenAmount }
        return (negative ? "−" : "") + "Rp" + amount.formattedAsDigits()
    }

    /// "Aman dipakai Rp45.000/hari untuk 4 hari tersisa.": the total spread over the days left in the period.
    private var safeToSpendCard: some View {
        let safe = viewModel.safeToSpend
        func line(visible: Bool) -> Text {
            if let perDay = viewModel.safePerDay {
                return Text(L("Aman dipakai") + " ").foregroundStyle(Color.appText)
                    + Text(visible ? "Rp" + perDay.formattedAsDigits() + "/" + L("hari") : hiddenAmount).fontWeight(.semibold).foregroundStyle(Color.appText)
                    + Text(" " + L("untuk %lld hari tersisa.", viewModel.daysLeftInPeriod)).foregroundStyle(Color.appText)
            }
            return Text(L("Aman dipakai") + " ").foregroundStyle(Color.appText)
                + Text(visible ? maskedAmount(safe, negative: safe < 0) : hiddenAmount).fontWeight(.semibold).foregroundStyle(safe < 0 ? Color.appError : Color.appText)
        }
        // The visible text is laid out (hidden) in both states so the card keeps its height when masked.
        let sizedLine = ZStack(alignment: .topLeading) {
            line(visible: true).hidden()
            line(visible: isBalanceVisible)
        }
        return Button { showsSafeInfo = true } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.appPrimary)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    sizedLine
                        .font(.app(15))
                        .monospacedDigit()
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appTextTertiary)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.appCardBackground.opacity(0), in: RoundedRectangle(cornerRadius: 16))
            .background(Color(light: 0xF7F7F8, dark: 0x1C1C1E), in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Lihat rincian")
        .sheet(isPresented: $showsSafeInfo) { safeToSpendSheet }
    }

    private var safeToSpendSheet: some View {
        let safe = viewModel.safeToSpend
        return PickerSheet(title: L("Aman dipakai"), onDone: { showsSafeInfo = false }) {
            VStack(alignment: .leading, spacing: 0) {
                safeRow(viewModel.hasInvestments ? L("Saldo kas") : L("Total saldo"), maskedAmount(viewModel.balance))
                safeRow(L("Tagihan kartu kredit"), maskedAmount(viewModel.cardDueTotal, negative: true))
                safeRow(L("Langganan bulan ini"), maskedAmount(viewModel.upcomingBillsTotal, negative: true))
                HStack {
                    Text("Aman dipakai")
                        .font(.app(17, weight: .semibold))
                    Spacer()
                    Text(maskedAmount(safe, negative: safe < 0))
                        .font(.app(17, weight: .semibold))
                        .foregroundStyle(safe < 0 ? Color.appError : Color.appText)
                        .monospacedDigit()
                }
                .padding(.vertical, 14)
                Text("Saldo dikurangi tagihan kartu kredit (termasuk belanja yang belum ditagih) dan langganan bulan ini.")
                    .font(.app(15))
                    .foregroundStyle(Color.appBody)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private func safeRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.app(15))
                .foregroundStyle(Color.appTextSecondary)
            Spacer()
            Text(value)
                .font(.app(16))
                .foregroundStyle(Color.appText)
                .monospacedDigit()
        }
        .padding(.vertical, 14)
        .rowSeparator()
    }

    private var hasNoWallets: Bool { !viewModel.accounts.contains(where: \.isActive) }

    /// Animated pocket mark with "Dompet · N akun"; opens the Dompet page.
    private var walletsButton: some View {
        Button {
            homePath.append(HomeRoute.wallets)
        } label: {
            HStack(spacing: 8) {
                WalletsMark()
                VStack(alignment: .leading, spacing: 1) {
                    Text("Dompet")
                        .font(.app(14, weight: .semibold))
                        .foregroundStyle(Color.appText)
                    Text("\(viewModel.accounts.filter(\.isActive).count) akun")
                        .font(.app(11))
                        .foregroundStyle(Color.appTextSecondary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(light: 0x8E8E93, dark: 0x8E8E93))
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .frame(height: 48)
            .background(Color.appFill, in: Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("Buka Dompet")
    }

    /// "Masuk 12 jt"; Net is green when positive and red when negative.
    private func flowStat(_ label: String, _ amount: Double, signed: Bool = false) -> some View {
        let sign = signed ? (amount > 0 ? "+" : amount < 0 ? "−" : "") : ""
        let color: Color = signed ? (amount > 0 ? .appPrimary : amount < 0 ? .appError : .appText) : .appText
        let text = Text(label + " ").foregroundStyle(Color.appTextSecondary)
            + Text(hasNoWallets ? "–" : isBalanceVisible ? sign + amount.abbreviatedRupiah() : hiddenAmount)
                .fontWeight(.medium)
                .foregroundStyle(hasNoWallets ? Color.appTextTertiary : color)
        // A hidden digit keeps the line height the same whether the value or the mask shows.
        return ZStack(alignment: .leading) {
            Text("0").hidden()
            text
        }
        .font(.app(15))
        .monospacedDigit()
        .lineLimit(1)
    }

    // MARK: Health score

    /// Score, bar and the factor costing the most points; tap for every factor and tips.
    @ViewBuilder
    private var healthSection: some View {
        let health = viewModel.health
        if !health.isAvailable {
            emptyHealthSection
        } else {
            NavigationLink { HealthDetailView(health: health).detailPage() } label: {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(title: L("Kesehatan finansial"), trailing: health.label ?? L("Sementara"),
                                  trailingColor: health.isProvisional ? .appTextSecondary : health.color)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(health.score)")
                            .font(.app(56, weight: .light))
                            .tracking(-2)
                            .foregroundStyle(Color.appText)
                        Text("/ 100")
                            .font(.app(17))
                            .foregroundStyle(Color.appTextSecondary)
                    }
                    .padding(.top, 14)

                    SegmentBar(value: Double(health.score) / 100, color: health.color, count: 40, height: 22, spacing: 3, replays: false)
                        .padding(.top, 16)

                    if health.isPartial {
                        Text("Skor sementara, belum termasuk arus kas dan dana darurat.")
                            .font(.app(13))
                            .foregroundStyle(Color.appTextTertiary)
                            .padding(.top, 10)
                    }

                    HStack(spacing: 10) {
                        if let weakest = health.weakest, !health.isHealthy {
                            Image(systemName: weakest.icon)
                                .font(.system(size: 15))
                                .foregroundStyle(weakest.color)
                            (Text("Perbaiki ").foregroundStyle(Color.appTextSecondary)
                             + Text(weakest.title.lowercased()).fontWeight(.medium).foregroundStyle(Color.appText)
                             + Text(" untuk +\(weakest.missing) poin").foregroundStyle(Color.appTextSecondary))
                                .font(.app(15))
                                .lineLimit(1)
                        } else {
                            Text("Semua faktor dalam kondisi baik")
                                .font(.app(15))
                                .foregroundStyle(Color.appTextSecondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.appTextTertiary)
                    }
                    .padding(.top, 18)
                }
                .padding(24)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .accessibilityHint("Lihat detail kesehatan finansial")
        }
    }

    // MARK: This month

    private var monthSection: some View {
        let days = viewModel.dailyExpenses
        let average = days.isEmpty ? 0 : days.reduce(0, +) / Double(days.count)
        let peak = max(days.max() ?? 0, average, 1) * 1.05
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: L("Bulan ini"))
                NavigationLink("Statistik") { StatistikView(onOpenBudget: { selectedTab = .budget }).detailPage() }
                    .font(.app(15))
                    .foregroundStyle(Color.appPrimary)
            }

            HStack(alignment: .top, spacing: 32) {
                countStat(average, label: L("rata-rata / hari")) { value in
                    isBalanceVisible ? value.rounded(.toNearestOrEven).formattedAsCurrency() : "Rp" + hiddenAmount
                }
                countStat(Double(viewModel.currentMonthTransactionCount), label: L("transaksi")) { "\(Int($0.rounded()))" }
            }
            .padding(.top, 14)

            dailyChart(days, average: average, peak: peak)
                .padding(.top, 18)

            HStack {
                Text(Self.dayMonthFormatter.string(from: PaydayCycle.current.period(containing: Date()).start))
                Spacer()
                Text("Hari ini")
            }
            .font(.app(12))
            .foregroundStyle(Color.appTextSecondary)
            .padding(.top, 8)

            let slices = categorySlices
            if !slices.isEmpty {
                categoryBar(slices)
                    .padding(.top, 24)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { legend(slices) }
                    VStack(alignment: .leading, spacing: 6) { legend(slices) }
                }
                .padding(.top, 10)
            }
        }
        .padding(24)
        .padding(.vertical, 4)
        .onAppear(perform: replayChart)
    }

    private func countStat(_ value: Double, label: String, format: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            CountingText(value: isChartShown ? value : 0, format: format)
                .font(.app(28, weight: .light))
                .tracking(-0.8)
                .monospacedDigit()
                .foregroundStyle(Color.appText)
                .animation(.timingCurve(0.33, 1, 0.68, 1, duration: 1.1), value: isChartShown)
            Text(label)
                .font(.app(13))
                .foregroundStyle(Color.appTextSecondary)
        }
    }

    /// One bar per day so far with a dashed daily-average line. Tap a bar to see that day's spending.
    private func dailyChart(_ days: [Double], average: Double, peak: Double) -> some View {
        let height: CGFloat = 96
        let selected = min(selectedDay ?? days.count - 1, days.count - 1)
        return VStack(spacing: 4) {
            if selected >= 0 {
                dayLabel(days, selected: selected)
            }
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(days.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i == selected ? Color.appPrimary : Self.barGray)
                        .animation(.easeInOut(duration: 0.2), value: selected)
                        .frame(height: isChartShown ? max(2, height * days[i] / peak) : 2)
                        .animation(.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.7).delay(Double(i) * 0.022), value: isChartShown)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedDay = i }
                        .accessibilityElement()
                        .accessibilityLabel(dayTitle(i, of: days.count))
                        .accessibilityValue(isBalanceVisible ? "Rp" + days[i].formattedAsDigits() : L("tersembunyi"))
                        .accessibilityAddTraits(i == selected ? [.isButton, .isSelected] : .isButton)
                }
            }
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .bottom)
            .overlay(alignment: .bottom) {
                if average > 0 {
                    DashedLine()
                        .stroke(Color.appTextSecondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .frame(height: 1)
                        .offset(y: -height * average / peak)
                        .opacity(isChartShown ? 1 : 0)
                        .animation(.easeOut(duration: 0.4).delay(isChartShown ? 0.9 : 0), value: isChartShown)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    /// Black pill above the chart naming the selected day and its spending; follows the bar.
    private func dayLabel(_ days: [Double], selected: Int) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let x = (CGFloat(selected) + 0.5) * w / CGFloat(days.count)
            HStack(spacing: 6) {
                Text(dayTitle(selected, of: days.count))
                    .foregroundStyle(Color.appBackground.opacity(0.7))
                Text(isBalanceVisible ? "−Rp" + days[selected].formattedAsDigits() : "Rp" + hiddenAmount)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.appBackground)
                    .contentTransition(.numericText())
            }
            .font(.app(13))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Color.appText, in: Capsule())
            .position(x: min(max(x, 78), max(w - 78, 78)), y: 14)
            .animation(.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.26), value: selected)
            .opacity(isChartShown ? 1 : 0)
            .animation(.easeInOut(duration: 0.3).delay(isChartShown ? 0.7 : 0), value: isChartShown)
        }
        .frame(height: 30)
        .accessibilityHidden(true)
    }

    /// "Hari ini" for the last bar, otherwise e.g. "Sel, 15 Sep".
    private func dayTitle(_ index: Int, of count: Int) -> String {
        guard index != count - 1 else { return L("Hari ini") }
        let calendar = Calendar.current
        let start = PaydayCycle.current.period(containing: Date(), calendar: calendar).start
        let date = calendar.date(byAdding: .day, value: index, to: start) ?? start
        return Self.weekdayDayFormatter.string(from: date)
    }

    /// Plays the first time Beranda shows the chart; coming back from another tab or page keeps it as is.
    private func replayChart() {
        guard !isChartShown else { return }
        var reset = SwiftUI.Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            isChartShown = false
            selectedDay = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { isChartShown = true }
    }

    private struct CategorySlice: Identifiable {
        let name: String
        let share: Double
        let color: Color
        var id: String { name }
    }

    /// Top four spending categories plus "Lainnya".
    private var categorySlices: [CategorySlice] {
        let total = viewModel.categorySpending.map(\.amount).reduce(0, +)
        guard total > 0 else { return [] }
        var slices = viewModel.categorySpending.prefix(4).enumerated().map { i, item in
            CategorySlice(name: item.0.name, share: item.amount / total, color: Self.slicePalette[i])
        }
        let rest = 1 - slices.map(\.share).reduce(0, +)
        if rest > 0.005 {
            slices.append(CategorySlice(name: L("Lainnya"), share: rest, color: Self.slicePalette[4]))
        }
        return slices
    }

    private func categoryBar(_ slices: [CategorySlice]) -> some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(Array(slices.enumerated()), id: \.element.id) { i, slice in
                    Rectangle()
                        .fill(slice.color)
                        .overlay(alignment: .trailing) {
                            Rectangle().fill(Color.appBackground).frame(width: 2)
                        }
                        .frame(width: isChartShown ? geo.size.width * slice.share : 0)
                        .animation(.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.8).delay(0.5 + Double(i) * 0.09), value: isChartShown)
                }
            }
        }
        .frame(height: 8)
        .background(Color.appFill)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func legend(_ slices: [CategorySlice]) -> some View {
        ForEach(slices.prefix(3)) { slice in
            HStack(spacing: 6) {
                Circle().fill(slice.color).frame(width: 8, height: 8)
                Text(slice.name)
                    .foregroundStyle(Color.appTextSecondary)
                    .lineLimit(1)
                Text("\(Int((slice.share * 100).rounded()))%")
                    .foregroundStyle(Color.appText)
                    .monospacedDigit()
            }
            .font(.app(13))
        }
    }

    private static let barGray = Color(light: 0xD9D9DE, dark: 0x3A3A3C)
    private static let slicePalette: [Color] = [
        .appPrimary,
        Color(light: 0x3A3A3C, dark: 0xD1D1D6),
        Color(light: 0x8E8E93, dark: 0x8E8E93),
        Color(light: 0xC7C7CC, dark: 0x636366),
        Color(light: 0xE5E5EA, dark: 0x3A3A3C),
    ]

    // MARK: Budget

    /// Three budgets with the largest spend; "Lihat semua" expands inline.
    private var budgetSection: some View {
        let sorted = viewModel.budgets.sorted { $0.spent > $1.spent }
        let shown = showAllBudgets ? sorted : Array(sorted.prefix(3))
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader(
                title: L("Budget"),
                trailing: sorted.isEmpty ? nil : L("Sisa %@", isBalanceVisible ? max(0, viewModel.totalRemaining).formattedAsCurrency() : "Rp" + hiddenAmount)
            )

            if sorted.isEmpty {
                Text("Belum ada budget")
                    .font(.app(15))
                    .foregroundStyle(Color.appTextSecondary)
                    .padding(.top, 14)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, budget in budgetRow(budget, index: i) }
                }
                .padding(.top, 6)
            }

            if sorted.count > 3 {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { showAllBudgets.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text(showAllBudgets ? L("Tampilkan lebih sedikit") : L("Lihat semua (%lld)", sorted.count))
                        Image(systemName: showAllBudgets ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .font(.app(15, weight: .medium))
                    .foregroundStyle(Color.appText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.appFill, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
            }
        }
        .padding(24)
        .padding(.vertical, 4)
    }

    private func budgetRow(_ budget: Budget, index: Int) -> some View {
        let category = viewModel.categories.first { $0.id == budget.categoryId }
        let ratio = budget.progress
        return HStack(spacing: 14) {
            Image(systemName: category?.icon ?? "tag")
                .font(.system(size: 19))
                .foregroundStyle(Color.appTextSecondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(category?.name ?? budget.name)
                        .font(.app(16, weight: .medium))
                        .foregroundStyle(Color.appText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Group {
                        if isBalanceVisible {
                            Text("Rp" + budget.spent.abbreviatedRupiah())
                                .foregroundStyle(Color.appText)
                                + Text(" / " + budget.amount.abbreviatedRupiah())
                                .foregroundStyle(Color.appTextTertiary)
                        } else {
                            Text("Rp" + hiddenAmount).foregroundStyle(Color.appText)
                        }
                    }
                    .font(.app(15))
                    .monospacedDigit()
                    .lineLimit(1)
                }
                SegmentBar(value: ratio, color: ratio >= 1 ? .appError : ratio >= 0.8 ? .appWarning : .appPrimary,
                           delay: 0.3 + Double(index) * 0.08, replays: false)
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: Formatting

    /// "Hari ini", "Kemarin", or "Kamis, 24 Sep".
    static func dayHeader(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return L("Hari ini") }
        if calendar.isDateInYesterday(date) { return L("Kemarin") }
        return shortDayFormatter.string(from: date)
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = format
        f.locale = AppLanguage.locale
        return f
    }

    private static var shortDayFormatter: DateFormatter { formatter("EEEE, d MMM") }
    private static var dayMonthFormatter: DateFormatter { formatter("d MMM") }
    private static var weekdayDayFormatter: DateFormatter { formatter("EEE, d MMM") }
}

/// The Dompet pill's mark: the pocket pops in, then the cards rise and fan.
/// Every 5 s the cards drop back in and rise again.
private struct WalletsMark: View {
    @State private var showsPocket = false
    @State private var isOpen = false
    @State private var isFanned = false

    var body: some View {
        PocketLogo(isOpen: isOpen, isFanned: isFanned, stagger: 0.12, duration: 0.9,
                   pocketColor: .appBrand, isPlain: true)
            .frame(width: 29, height: 29)
            .opacity(showsPocket ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: showsPocket)
            .scaleEffect(showsPocket ? 1 : 0.6, anchor: .bottom)
            .animation(.timingCurve(0.3, 1.4, 0.5, 1, duration: 0.7), value: showsPocket)
            .frame(width: 34, height: 34)
            .accessibilityHidden(true)
            .task { await play() }
    }

    private func play() async {
        var reset = SwiftUI.Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            showsPocket = false
            isOpen = false
            isFanned = false
        }
        let start = ContinuousClock.now
        for (t, step) in [(0.15, 1), (0.65, 2), (1.25, 3)] {
            try? await Task.sleep(until: start + .seconds(t), clock: .continuous)
            guard !Task.isCancelled else { return }
            switch step {
            case 1: showsPocket = true
            case 2: isOpen = true
            default: isFanned = true
            }
        }
        // Loops until the view goes away.
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            isOpen = false
            isFanned = false
            try? await Task.sleep(for: .seconds(1))
            isOpen = true
            try? await Task.sleep(for: .seconds(0.6))
            isFanned = true
        }
    }
}

/// The Profil tab's avatar bitmap, kept until the initials or the photo change.
@MainActor
final class TabAvatarCache: ObservableObject {
    private var key = ""
    private var photo: UIImage?
    private var cached: UIImage?

    func image(initials: String, photo: UIImage?) -> UIImage {
        if let cached, key == initials, self.photo === photo { return cached }
        let renderer = ImageRenderer(content: InitialsAvatar(initials: initials, size: 28, fontSize: 11, image: photo))
        renderer.scale = UITraitCollection.current.displayScale
        let image = renderer.uiImage?.withRenderingMode(.alwaysOriginal) ?? UIImage()
        key = initials
        self.photo = photo
        cached = image
        return image
    }
}
