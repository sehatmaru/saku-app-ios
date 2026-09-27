import SwiftUI

/// Dompet: one card stack per wallet type (design 6c). Tap a closed stack to fan it out,
/// tap a card in an open stack to open that wallet, tap the group title to close it again.
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
                    .padding(.top, index == 0 ? 0 : isOpen ? 12 : stripHeight - cardHeight)
                    .zIndex(Double(index))
                    .onTapGesture {
                        if isOpen || group.accounts.count == 1 {
                            path.append(account)
                        } else {
                            setGroup(group.type, open: true)
                        }
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(isOpen || group.accounts.count == 1 ? "Buka dompet" : "Buka tumpukan")
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
