import SwiftUI

/// Dompet: wallets as a stack of cards (design 5a). Tapping a card lifts it to the top,
/// drops the rest into a pile at the bottom and reveals balance, actions and recent transactions.
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
    /// Index into `cards` of the opened card; nil shows the closed stack.
    @State private var selectedIndex: Int?
    /// Keeps the detail content populated while it fades out.
    @State private var lastIndex: Int?
    @State private var transferFrom: Account?
    @State private var path = NavigationPath()

    // Layout from the design, in points.
    private let cardHeight: CGFloat = 216
    private let closedTop: CGFloat = 104
    private let closedStep: CGFloat = 56
    private let openStackTop: CGFloat = 604
    private let openStackStep: CGFloat = 8

    /// Active wallets, main account last so it sits in front of the stack.
    private var cards: [Account] {
        let order: [Account.AccountType] = [.cash, .ewallet, .bank, .credit]
        return viewModel.accounts
            .filter(\.isActive)
            .sorted { lhs, rhs in
                if lhs.isDefault != rhs.isDefault { return rhs.isDefault }
                return (order.firstIndex(of: lhs.type) ?? 0) < (order.firstIndex(of: rhs.type) ?? 0)
            }
    }

    private var archivedAccounts: [Account] {
        viewModel.accounts.filter { !$0.isActive }
    }

    var body: some View {
        NavigationStack(path: $path) {
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
                        stack
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: viewModel.hasLoadedOnce)
            }
            .scrollDisabled(selectedIndex != nil)
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
            .onChange(of: viewModel.accounts.count) { _, _ in selectedIndex = nil }
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
            .sheet(item: $transferFrom) { account in
                if let userId = authViewModel.currentUser?.id {
                    AddTransactionView(
                        categories: categories,
                        accounts: viewModel.accounts,
                        userId: userId,
                        onSave: {},
                        initialType: .transfer,
                        initialAccount: account
                    )
                    .presentationDetents([.fraction(0.68), .large])
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        ScreenHeader(title: "Dompet") {
            if selectedIndex != nil {
                Button("Selesai") { close() }
                    .font(.app(17, weight: .semibold))
                    .foregroundStyle(Color.appPrimary)
            } else {
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
        .frame(height: 54)
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
            RoundedRectangle(cornerRadius: 4).fill(Color.appFill).frame(width: 220, height: 40)
            RoundedRectangle(cornerRadius: 16).fill(Color.appFill).frame(height: cardHeight).padding(.top, 40)
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
        .shimmer()
    }

    // MARK: Stack

    private var stack: some View {
        let cards = cards
        let isOpen = selectedIndex != nil
        let closedHeight = closedTop + CGFloat(max(cards.count - 1, 0)) * closedStep + cardHeight
        return ZStack(alignment: .top) {
            summary
                .opacity(isOpen ? 0 : 1)
                .offset(y: isOpen ? -12 : 0)
                .animation(.easeOut(duration: 0.26), value: isOpen)
                .allowsHitTesting(!isOpen)

            if let index = selectedIndex ?? lastIndex, cards.indices.contains(index) {
                detail(cards[index])
                    .padding(.top, cardHeight + 20)
                    .opacity(isOpen ? 1 : 0)
                    .offset(y: isOpen ? 0 : 18)
                    .animation(.spring(response: 0.46, dampingFraction: 0.9).delay(isOpen ? 0.2 : 0), value: isOpen)
                    .allowsHitTesting(isOpen)
            }

            if cards.isEmpty {
                emptyState.padding(.top, closedTop)
            }

            ForEach(Array(cards.enumerated()), id: \.element.id) { index, account in
                let layout = cardLayout(index: index, count: cards.count)
                WalletCard(
                    account: account,
                    showsStripAmount: !isOpen && index != cards.count - 1,
                    isBalanceVisible: isBalanceVisible
                )
                .frame(height: cardHeight)
                .scaleEffect(layout.scale, anchor: .top)
                .offset(y: layout.y)
                .zIndex(layout.z)
                .animation(.spring(response: 0.54, dampingFraction: 0.86).delay(layout.delay), value: selectedIndex)
                .onTapGesture { toggle(index) }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(selectedIndex == index ? "Tutup kartu" : "Buka kartu")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
        .frame(minHeight: max(closedHeight, openStackTop + cardHeight), alignment: .top)
    }

    private func cardLayout(index: Int, count: Int) -> (y: CGFloat, scale: CGFloat, z: Double, delay: Double) {
        guard let selected = selectedIndex else {
            return (closedTop + CGFloat(index) * closedStep, 1, Double(index + 1), Double(count - 1 - index) * 0.03)
        }
        if index == selected { return (0, 1, 50, 0) }
        let k = CGFloat(index < selected ? index : index - 1)
        return (openStackTop + k * openStackStep, 0.9 + k * 0.02, 10 + Double(k), 0.04 + Double(k) * 0.03)
    }

    private func toggle(_ index: Int) {
        lastIndex = index
        selectedIndex = selectedIndex == index ? nil : index
    }

    private func close() {
        selectedIndex = nil
    }

    private var summary: some View {
        let active = cards.count
        return VStack(alignment: .leading, spacing: 0) {
            Text("Total saldo · \(active) akun")
                .font(.app(15))
                .foregroundStyle(Color.appTextSecondary)
            HeroAmount(value: viewModel.totalBalance, size: .medium, isVisible: isBalanceVisible)
                .padding(.top, 6)
            HStack {
                if viewModel.totalCreditDebt > 0 {
                    Text("Utang kartu kredit " + masked(viewModel.totalCreditDebt))
                        .monospacedDigit()
                }
                Spacer()
                if !archivedAccounts.isEmpty {
                    Button("Arsip (\(archivedAccounts.count))") { path.append("archived") }
                        .foregroundStyle(Color.appTextSecondary)
                }
            }
            .font(.app(13))
            .foregroundStyle(Color.appTextSecondary)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: Detail

    private func detail(_ account: Account) -> some View {
        let recent = Array((accountTransactions[account.id] ?? []).prefix(3))
        return VStack(alignment: .leading, spacing: 0) {
            if account.isCreditCard, let limit = account.creditLimit {
                VStack(alignment: .leading, spacing: 6) {
                    ThinProgress(value: account.creditUtilization ?? 0)
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
                .padding(.top, 4)
            }

            HStack(spacing: 0) {
                action("Transfer", icon: "arrow.left.arrow.right") { transferFrom = account }
                action("Sesuaikan", icon: "slider.horizontal.3") { path.append(account) }
                action("Riwayat", icon: "clock.arrow.circlepath") { path.append(account) }
                action("Ubah", icon: "pencil") { path.append(account) }
            }
            .padding(.top, 16)

            HStack(alignment: .firstTextBaseline) {
                Text("Transaksi terakhir")
                    .font(.app(17, weight: .semibold))
                    .foregroundStyle(Color.appText)
                Spacer()
                Button("Semua") { path.append(account) }
                    .font(.app(15))
                    .foregroundStyle(Color.appPrimary)
            }
            .padding(.top, 18)

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

    private func action(_ title: String, icon: String, perform: @escaping () -> Void) -> some View {
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

    private func masked(_ amount: Double) -> String {
        isBalanceVisible ? amount.formattedAsCurrency() : "Rp" + hiddenAmount
    }

    /// Short month of the next occurrence of `day`, e.g. "Okt".
    private static func nextDueMonth(day: Int) -> String {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.component(.day, from: now)
        let date = today <= day ? now : (calendar.date(byAdding: .month, value: 1, to: now) ?? now)
        let f = DateFormatter()
        f.dateFormat = "MMM"
        f.locale = Locale(identifier: "id_ID")
        return f.string(from: date)
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
