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
@State private var showsImageConsent = false
@ObservedObject private var plusStore = PlusStore.shared
@State private var showsTrialEnded = false
@State private var trialEndedOffer: PlusReason?
    /// Drives the "Bulan ini" grow-in; reset and set again to replay.
    @State private var isChartShown = false
    /// Day index picked in the "Bulan ini" chart; nil means today.
    @State private var showAllBudgets = false
    @State private var selectedTab: AppTab = .home
    /// Beranda's stack; Dompet is pushed here from the hero's pill.
    @State private var homePath = NavigationPath()
    @State private var didWelcome = false
    /// "Tambah dompet" on the empty Beranda opens Dompet straight into the add sheet.
    @State private var addsWalletOnOpen = false
    @AppStorage(HomeBalanceSetting.key) private var homeBalanceMode = HomeBalanceMode.cash.rawValue
    @State private var showsSafeInfo = false
    /// What the single attention slot under the hero decides from.
    @AppStorage("plusBannersClosed") private var plusBannersClosed = ""
    @AppStorage(GuestCardPolicy.countKey) private var guestDismissCount = 0
    @AppStorage(GuestCardPolicy.untilKey) private var guestHiddenUntil = 0.0
    @AppStorage(SmartTrackerConsent.key) private var smartConsented = false
    @AppStorage("smartTrackerCardDismissed") private var smartCardDismissed = false
    /// Catat tagihan for an overdue card bill, from the banner or a notification.
    /// Kept as the bill it was opened with, so the sheet survives the reload after paying.
    @State private var recordCard: OverdueCardBill?
    @State private var toastText = ""
    @State private var isToastShown = false
    /// The tray pill says "Baru masuk" for a moment after drafts land (design 1a).
    @State private var isTrayFresh = false
    /// Counts the times drafts landed; the Draf pill plays its motion on each.
    @State private var trayLanded = 0
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
        .onChange(of: notificationRouter.opensImageConsent) { _, _ in openImageConsentIfRequested() }
        .onChange(of: notificationRouter.pendingInvestmentId) { _, id in if id != nil { openWalletsPage() } }
        .onChange(of: draftStore.drafts.count) { old, new in
            // "Baru masuk" on the tray pill right after drafts land (design 1a)
            guard new > old else { return }
            withAnimation(.settle(0.25)) { isTrayFresh = true }
            trayLanded += 1
            Task {
                try? await Task.sleep(for: .seconds(2.8))
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
        .onAppear { openDraftsIfRequested(); openImageConsentIfRequested(); askConsentForSharedText(); announceReferralReward() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in askConsentForSharedText(); announceReferralReward() }
        .sheet(isPresented: $showsImageConsent) {
            ImageConsentSheet(profileId: authViewModel.currentUser.flatMap { UUID(uuidString: $0.id) }) {
                showsImageConsent = false
            } onDetails: {
                showsImageConsent = false
                showsConsent = true
            }
        }
        .sheet(isPresented: $showsConsent) {
            SmartTrackerConsentSheet(profileId: authViewModel.currentUser.flatMap { UUID(uuidString: $0.id) }) {
                showsConsent = false
                DraftStore.shared.ingestSharedText()
                openDraftsPage()
            }
        }
        .onAppear { showsTrialEnded = plusStore.trialEndedSummaryDue }
        .onChange(of: plusStore.entitlement) { _, _ in showsTrialEnded = plusStore.trialEndedSummaryDue }
        .onChange(of: plusStore.profileApplied) { _, _ in showsTrialEnded = plusStore.trialEndedSummaryDue }
        .sheet(isPresented: $showsTrialEnded) {
            TrialEndedSheet(wallets: viewModel.accounts.filter(\.isActive).count, categories: viewModel.categories.count,
                            budgets: viewModel.budgets.count) { trialEndedOffer = .general }
        }
        .plusOffer($trialEndedOffer)
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

    /// Tapping "setujui baca gambar" from the share extension: the agreement sheet opens right away.
    private func openImageConsentIfRequested() {
        guard notificationRouter.opensImageConsent else { return }
        notificationRouter.opensImageConsent = false
        showsImageConsent = true
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
                    if !viewModel.overdueBills.isEmpty {
                        OverdueBillBanner(bills: viewModel.overdueBills, isBalanceVisible: isBalanceVisible) { bill in
                            recordCard = bill
                        }
                    }
                    summarySection
                    shortcutRow
                    attentionSlot
                    if hasNoWallets {
                        firstWalletCard
                        emptyHealthSection
                            .padding(.bottom, 90)
                    } else {
                        recentSection
                        periodSection
                        SectionDivider()
                        budgetSection
                        if !viewModel.upcomingSubscriptions.isEmpty {
                            SectionDivider()
                            billsSection
                        }
                        if viewModel.health.isAvailable {
                            Color.clear.frame(height: 90)
                        } else {
                            SectionDivider()
                            emptyHealthSection
                                .padding(.bottom, 90)
                        }
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

    /// The period and what is left of it on the left, the eye on the right.
    private var homeHeader: some View {
        HStack {
            // as tall as the 34 pt title of Transaksi, so the eye sits at the same height there
            ZStack(alignment: .leading) {
                Text(" ").font(.app(34, weight: .bold)).hidden()
                VStack(alignment: .leading, spacing: 2) {
                    Text(PaydayCycle.current.rangeLabel())
                        .font(.app(17, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.appText)
                    Text(L("%lld hari lagi", viewModel.daysLeftInPeriod))
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                }
            }
            Spacer()
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
        .padding(.top, 10)
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

    /// Big total: kas by default, kas + aset when Profil says so. Under it what can be spent per day and how far the
    /// period has come.
    private var summarySection: some View {
        let showsWealth = viewModel.hasInvestments && homeBalanceMode == HomeBalanceMode.all.rawValue
        return VStack(alignment: .leading, spacing: 0) {
            Text("Total saldo")
                .font(.app(15))
                .foregroundStyle(Color.appTextSecondary)
            HeroAmount(value: showsWealth ? viewModel.wealth : viewModel.balance, size: .hero,
                       color: hasNoWallets ? .appTextTertiary : .appText,
                       prefixColor: hasNoWallets ? .appTextTertiary : .appTextSecondary,
                       isVisible: isBalanceVisible, weight: .ultraLight)
                .padding(.top, 2)
            if !hasNoWallets {
                safeToSpendRow.padding(.top, 18)
                periodProgress.padding(.top, 14)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, hasNoWallets ? 24 : 16)
    }

    /// "Hari ke-12 dari 31", day by day.
    private var periodProgress: some View {
        let days = PaydayCycle.current.days()
        let day = min(max(days.total - days.left, 1), days.total)
        return VStack(alignment: .leading, spacing: 8) {
            SegmentBar(value: Double(day) / Double(days.total), count: days.total, height: 8, spacing: 2, replays: false)
            Text(L("Hari ke-%lld dari %lld", day, days.total))
                .font(.app(13))
                .foregroundStyle(Color.appTextSecondary)
        }
    }

    /// Kesehatan finansial, Dompet, and Draf while Smart Tracker is on. With a score the row is tighter.
    private var shortcutRow: some View {
        let health = viewModel.health
        let compact = health.isAvailable
        return HStack(spacing: compact ? 6 : 10) {
            if compact { healthRing(health) }
            walletsButton(compact: compact)
            if smartQuickOn, authViewModel.currentUser != nil {
                DraftPill(count: draftStore.drafts.count, isFresh: isTrayFresh, landed: trayLanded, compact: compact) { openDraftsPage() }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 4)
    }

    /// The ring that opens Kesehatan finansial.
    private func healthRing(_ health: FinancialHealth) -> some View {
        NavigationLink { HealthDetailView(health: health).detailPage() } label: {
            HealthRing(score: health.score)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(L("Kesehatan finansial"))
        .accessibilityValue("\(health.score)")
    }

    // MARK: Attention

    private enum Attention { case plus, guest, smart }

    /// One card at a time under the hero: Saku Plus or trial, saving a guest account, then trying Smart Tracker.
    /// The card bill alert above the hero is its own thing and does not count.
    private var attention: Attention? {
        let closed = Set(plusBannersClosed.split(separator: "|").map(String.init))
        if PlusBanner.pick(for: plusStore.entitlement, dismissed: closed) != nil { return .plus }
        if authViewModel.welcome == nil, GuestCardPolicy.shows(
            isGuest: authViewModel.currentUser?.isGuest == true,
            transactionCount: viewModel.currentMonthTransactionCount,
            signedUpAt: SupabaseSDK.client.auth.currentUser?.createdAt,
            dismissCount: guestDismissCount,
            hiddenUntil: guestHiddenUntil > 0 ? Date(timeIntervalSince1970: guestHiddenUntil) : nil) { return .guest }
        if !smartConsented, !smartCardDismissed, authViewModel.currentUser != nil { return .smart }
        return nil
    }

    @ViewBuilder private var attentionSlot: some View {
        switch attention {
        case .plus: PlusBannerView()
        case .guest: GuestSaveCard(transactionCount: viewModel.currentMonthTransactionCount)
        case .smart: TrySmartTrackerCard()
        case nil: EmptyView()
        }
    }

    // MARK: Recent

    /// The last three transactions; "Lihat semua" opens the Transaksi tab.
    @ViewBuilder private var recentSection: some View {
        let rows = Array(viewModel.recentTransactions.prefix(3))
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader(title: L("Transaksi terakhir"))
                    Button(L("Lihat semua")) { selectedTab = .transactions }
                        .font(.app(15))
                        .foregroundStyle(Color.appPrimary)
                }
                VStack(spacing: 0) {
                    ForEach(rows) { transaction in
                        TransactionRowView(transaction: transaction, categories: viewModel.categories, accounts: viewModel.accounts,
                                           showBalance: isBalanceVisible, showAccount: true)
                    }
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 8)
            SectionDivider()
        }
    }

    // MARK: Safe to spend

    /// Rp amount honouring the eye toggle; negative gets a minus sign.
    private func maskedAmount(_ amount: Double, negative: Bool = false) -> String {
        guard isBalanceVisible else { return hiddenAmount }
        return (negative ? "−" : "") + "Rp" + amount.formattedAsDigits()
    }

    /// "Bisa dipakai Rp45.000/hari": the total spread over the days left in the period; tap for the breakdown.
    private var safeToSpendRow: some View {
        let safe = viewModel.safeToSpend
        func line(visible: Bool) -> Text {
            let isNegative = viewModel.safePerDay == nil && safe < 0
            let value: String
            if let perDay = viewModel.safePerDay {
                value = visible ? "Rp" + perDay.formattedAsDigits() + "/" + L("hari") : hiddenAmount
            } else {
                value = visible ? maskedAmount(safe, negative: safe < 0) : hiddenAmount
            }
            return Text(L("Bisa dipakai") + " ").foregroundStyle(Color.appTextSecondary)
                + Text(value).fontWeight(.semibold).foregroundStyle(isNegative ? Color.appError : Color.appText)
        }
        // The visible text is laid out (hidden) in both states so the row keeps its height when masked.
        let sizedLine = ZStack(alignment: .topLeading) {
            line(visible: true).hidden()
            line(visible: isBalanceVisible)
        }
        return Button { showsSafeInfo = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.appPrimary)
                sizedLine
                    .font(.app(16))
                    .monospacedDigit()
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appTextTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Lihat rincian")
        .sheet(isPresented: $showsSafeInfo) { safeToSpendSheet }
    }

    /// "Bisa dipakai": the per-day amount big, then what it is made of.
    private var safeToSpendSheet: some View {
        let safe = viewModel.safeToSpend
        let perDay = viewModel.safePerDay
        let big = perDay ?? safe
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Bisa dipakai")
                    .font(.app(20, weight: .semibold))
                    .foregroundStyle(Color.appText)
                Spacer()
                Button { showsSafeInfo = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.appTextSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(L("Tutup"))
            }
            .padding(.top, 12)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(isBalanceVisible ? (big < 0 ? "−" : "") + "Rp" + abs(big).formattedAsDigits() : "Rp" + hiddenAmount)
                    .font(.app(44, weight: .light))
                    .tracking(-1.6)
                    .foregroundStyle(big < 0 ? Color.appError : Color.appText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if perDay != nil {
                    Text("/" + L("hari"))
                        .font(.app(17))
                        .foregroundStyle(Color.appTextSecondary)
                }
            }
            .monospacedDigit()
            .padding(.top, 2)

            if perDay != nil {
                Text(L("untuk %lld hari sampai %@", viewModel.daysLeftInPeriod, PaydayCycle.current.lastDayLabel()))
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
                    .padding(.top, 4)
            }

            VStack(alignment: .leading, spacing: 0) {
                safeRow(viewModel.hasInvestments ? L("Saldo kas") : L("Total saldo"), maskedAmount(viewModel.balance))
                safeRow(L("Tagihan kartu kredit"), maskedAmount(viewModel.cardDueTotal, negative: true))
                safeRow(L("Langganan bulan ini"), maskedAmount(viewModel.upcomingBillsTotal, negative: true))
            }
            .padding(.top, 22)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .filterSheet { PrimaryButton(title: L("Mengerti")) { showsSafeInfo = false } }
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
    private func walletsButton(compact: Bool) -> some View {
        Button {
            homePath.append(HomeRoute.wallets)
        } label: {
            HStack(spacing: compact ? 6 : 8) {
                WalletsMark()
                    .scaleEffect(compact ? 0.88 : 1)
                    .frame(width: compact ? 30 : 34, height: compact ? 30 : 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Dompet")
                        .font(.app(14, weight: .semibold))
                        .foregroundStyle(Color.appText)
                    Text("\(viewModel.accounts.filter(\.isActive).count) akun")
                        .font(.app(11))
                        .foregroundStyle(Color.appTextSecondary)
                }
                Spacer(minLength: 0)
                if !compact {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(light: 0x8E8E93, dark: 0x8E8E93))
                }
            }
            .padding(.leading, compact ? 6 : 8)
            .padding(.trailing, compact ? 10 : 12)
            .frame(maxWidth: .infinity)
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

    // MARK: Period

    /// "Periode ini": money in and out, the average per day and the spending calendar.
    private var periodSection: some View {
        let days = viewModel.dailyExpenses
        let average = days.isEmpty ? 0 : days.reduce(0, +) / Double(days.count)
        let period = PaydayCycle.current.period(containing: Date())
        let totalDays = max(Calendar.current.dateComponents([.day], from: period.start, to: period.end).day ?? days.count, days.count)
        let spendingCalendar = PeriodStatistics.spendingCalendar(daily: days, totalDays: totalDays, startOfPeriod: period.start)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: L("Periode ini"))
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

            countStat(average, label: L("rata-rata / hari")) { value in
                isBalanceVisible ? value.rounded(.toNearestOrEven).formattedAsCurrency() : "Rp" + hiddenAmount
            }
            .padding(.top, 22)

            SpendingCalendarGrid(calendar: spendingCalendar, money: StatistikMoney(isVisible: isBalanceVisible))
                .padding(.top, 18)
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

    /// Plays the first time Beranda shows the chart; coming back from another tab or page keeps it as is.
    private func replayChart() {
        guard !isChartShown else { return }
        var reset = SwiftUI.Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            isChartShown = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { isChartShown = true }
    }

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
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Buat budget pertama")
                            .font(.app(17, weight: .semibold))
                            .foregroundStyle(Color.appText)
                        Text("Batasi pengeluaran per kategori. Kamu akan tahu sisanya di tiap periode.")
                            .font(.app(15))
                            .foregroundStyle(Color.appTextSecondary)
                            .lineSpacing(2)
                    }
                    EmptyStateButton(title: L("Buat budget")) { selectedTab = .budget }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.appFill, in: RoundedRectangle(cornerRadius: 20))
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

    // MARK: Upcoming bills

    /// The next three subscriptions to be charged, soonest first.
    private var billsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: L("Tagihan mendatang"))
            VStack(spacing: 0) {
                ForEach(viewModel.upcomingSubscriptions.prefix(3)) { billRow($0) }
            }
            .padding(.top, 6)
        }
        .padding(24)
        .padding(.vertical, 4)
    }

    private func billRow(_ sub: CardSubscription) -> some View {
        let icon = viewModel.categories.first { $0.id == sub.categoryId }?.icon ?? "calendar"
        return HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 19))
                .foregroundStyle(Color.appTextSecondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(sub.name)
                    .font(.app(16, weight: .medium))
                    .foregroundStyle(Color.appText)
                    .lineLimit(1)
                Text(billDue(sub))
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
            }
            Spacer(minLength: 8)
            Text(isBalanceVisible ? "Rp" + sub.amount.formattedAsDigits() : "Rp" + hiddenAmount)
                .font(.app(15))
                .monospacedDigit()
                .foregroundStyle(Color.appText)
        }
        .padding(.vertical, 12)
    }

    /// "Jatuh tempo 3 Nov · 4 hari", or "Jatuh tempo hari ini".
    private func billDue(_ sub: CardSubscription) -> String {
        guard let date = sub.nextBillingDateAsDate else { return "-" }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: date).day ?? 0
        if days <= 0 { return L("Jatuh tempo hari ini") }
        return L("Jatuh tempo %@ · %lld hari", PaydayCycle.dayMonth.string(from: date), days)
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

/// Kesehatan finansial in the shortcut row, timed like the design (5a/5b): the arc fills to the score, the number
/// shows, the arc clears, then a disc with the verdict pops in (a check drawn when healthy, an
/// exclamation otherwise), and it settles back to the arc and the score. It plays once per launch; later it is
/// only the settled ring.
private struct HealthRing: View {
    let score: Int

    @MainActor private enum Intro { static var played = false }
    @State private var start: Date?
    @State private var done = Intro.played

    /// 80 and up is healthy (green check); below that an exclamation, amber from 60 and red under it.
    private var isHealthy: Bool { score >= 80 }
    private var color: Color { isHealthy ? .appPrimary : score >= 60 ? .appWarning : .appError }
    private let showsVerdict = true

    var body: some View {
        TimelineView(.animation(paused: done)) { context in
            let t = done ? 99 : start.map { context.date.timeIntervalSince($0) } ?? 0
            ring(t)
        }
        .frame(width: 48, height: 48)
        .background(Color.appFill, in: Circle())
        .task {
            guard !done else { return }
            Intro.played = true
            start = Date()
            try? await Task.sleep(for: .seconds(5.6))
            done = true
        }
    }

    /// Piecewise values over time, eased between keys like the CSS keyframes.
    private func at(_ t: Double, _ keys: [(Double, Double)], out: Bool = false) -> Double {
        guard let first = keys.first, let last = keys.last else { return 0 }
        if t <= first.0 { return first.1 }
        if t >= last.0 { return last.1 }
        for i in 1..<keys.count where t <= keys[i].0 {
            let (t0, v0) = keys[i - 1], (t1, v1) = keys[i]
            let x = (t - t0) / (t1 - t0)
            let eased = out ? 1 - pow(1 - x, 3) : x * x * (3 - 2 * x)
            return v0 + (v1 - v0) * eased
        }
        return last.1
    }

    private func ring(_ t: Double) -> some View {
        let numberOn = at(t, [(0.4, 0), (0.9, 1), (2.1, 1), (2.5, 0), (4.8, 0), (5.2, 1)])
        let numberScale = at(t, [(0.4, 0.85), (0.9, 1), (2.1, 1), (2.5, 0.8), (4.8, 0.8), (5.2, 1)])
        return ZStack {
            arc(t)
            Text("\(score)")
                .font(.app(score >= 100 ? 11 : 14, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.appText)
                .opacity(numberOn)
                .scaleEffect(numberScale)
            if showsVerdict { verdict(t) }
        }
    }

    /// The score as a round-capped arc on a light track, filling up from the top.
    private func arc(_ t: Double) -> some View {
        let p = Double(min(max(score, 0), 100)) / 100
        let fill = at(t, [(0.1, 0), (1.6, p), (2.4, p), (2.8, 0), (4.6, 0), (5.4, p)], out: true)
        let track = at(t, [(2.4, 1), (2.8, 0), (4.6, 0), (5.0, 1)])
        return ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: 5).opacity(track)
            Circle().trim(from: 0, to: fill)
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .opacity(fill > 0.004 ? 1 : 0)
        }
        .rotationEffect(.degrees(-90))
        .frame(width: 32, height: 32)
    }

    private func verdict(_ t: Double) -> some View {
        let discOpacity = at(t, [(2.4, 0), (2.9, 1), (4.6, 1), (4.9, 0)], out: true)
        let discScale = at(t, [(2.4, 0.4), (2.9, 1.1), (3.25, 1), (4.9, 1)], out: true)
        let glyphOpacity = at(t, [(2.5, 0), (3.0, 1), (4.6, 1), (4.9, 0)], out: true)
        let glyphScale = at(t, [(2.5, 0.5), (3.0, 1.15), (3.35, 1), (4.9, 1)], out: true)
        let drawn = at(t, [(2.6, 0), (3.3, 1)], out: true)
        return ZStack {
            Circle().fill(color).frame(width: 38, height: 38)
                .scaleEffect(discScale)
                .opacity(discOpacity)
            Group {
                if isHealthy {
                    VerdictCheck().trim(from: 0, to: drawn)
                        .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                } else {
                    VerdictMark().stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    Circle().fill(.white).frame(width: 4.8, height: 4.8).offset(y: 9)
                }
            }
            .frame(width: 40, height: 40)
            .scaleEffect(glyphScale)
            .opacity(glyphOpacity)
        }
    }
}

private struct VerdictCheck: Shape {
    func path(in rect: CGRect) -> Path {
        let k = rect.width / 40
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 13 * k, y: rect.minY + 21 * k))
        path.addLine(to: CGPoint(x: rect.minX + 18 * k, y: rect.minY + 26 * k))
        path.addLine(to: CGPoint(x: rect.minX + 27 * k, y: rect.minY + 15 * k))
        return path
    }
}

private struct VerdictMark: Shape {
    func path(in rect: CGRect) -> Path {
        let k = rect.width / 40
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 20 * k, y: rect.minY + 11 * k))
        path.addLine(to: CGPoint(x: rect.minX + 20 * k, y: rect.minY + 23 * k))
        return path
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
