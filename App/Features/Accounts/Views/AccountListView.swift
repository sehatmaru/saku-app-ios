import SwiftUI

struct AccountListView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel: AccountListViewModel

    init(viewModel: AccountListViewModel = AccountListViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    @AppStorage("isBalanceVisible") private var isBalanceVisibleStorage = true
    @State private var isBalanceVisible = true
    @State private var showAddWallet = false
    @State private var showArchived = false
    @State private var expandedSections: Set<String> = ["cash", "bank", "ewallet", "credit"]
    @State private var accountTransactions: [String: [Transaction]] = [:]
    @State private var categories: [Category] = []
    @State private var cachedUserId: String?

    private var walletAccounts: [Account] {
        viewModel.accounts.filter { $0.isActive && !$0.isCreditCard }
    }

    private var cashAccounts: [Account] { viewModel.accounts.filter { $0.isActive && $0.type == .cash } }
    private var bankAccounts: [Account] { viewModel.accounts.filter { $0.isActive && $0.type == .bank } }
    private var ewalletAccounts: [Account] { viewModel.accounts.filter { $0.isActive && $0.type == .ewallet } }

    private var creditAccounts: [Account] {
        viewModel.accounts.filter { $0.isActive && $0.isCreditCard }
    }

    private var archivedAccounts: [Account] {
        viewModel.accounts.filter { !$0.isActive }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    if let error = viewModel.errorMessage, !viewModel.hasLoadedOnce {
                        errorStateView(message: error)
                            .transition(.opacity)
                    } else if !viewModel.hasLoadedOnce {
                        skeletonContent
                            .transition(.opacity)
                    } else {
                        Group {
                            if viewModel.errorMessage != nil {
                                ErrorBanner(message: viewModel.errorMessage!)
                            }
                            totalBalanceCard

                            LazyVStack(spacing: Spacing.lg) {
                                accountSection(id: "cash", title: "Cash", icon: "banknote.fill", color: .appIncome, accounts: cashAccounts)
                                accountSection(id: "bank", title: "Bank", icon: "building.columns.fill", color: .appPrimary, accounts: bankAccounts)
                                accountSection(id: "ewallet", title: "E-Wallet", icon: "wallet.pass.fill", color: .appWarning, accounts: ewalletAccounts)
                                if !creditAccounts.isEmpty {
                                    accountSection(id: "credit", title: "Kartu Kredit", icon: "creditcard.fill", color: .appExpense, accounts: creditAccounts)
                                }
                            }

                            if !archivedAccounts.isEmpty {
                                archiveSection
                            }
                        }
                        .transition(.opacity)
                    }
                }
                .padding()
                .animation(.easeInOut(duration: 0.3), value: viewModel.hasLoadedOnce)
            }
            .background(Color.appGroupedBackground)
            .refreshable {
                guard let userId = authViewModel.currentUser?.id else { return }
                await viewModel.loadAccounts(userId: userId, forceRefresh: true)
                await syncAccountTransactions(userId: userId, forceRefresh: true)
                await syncCategories(userId: userId)
            }
            .navigationTitle("Akun")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.smooth) { isBalanceVisible.toggle() }
                        isBalanceVisibleStorage = isBalanceVisible
                    } label: {
                        Image(systemName: isBalanceVisible ? "eye.fill" : "eye.slash.fill")
                            .font(.jakarta(16))
                            .foregroundColor(.appTextSecondary)
                    }
                }
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
        VStack(spacing: Spacing.lg) {
            RoundedRectangle(cornerRadius: 20).fill(Color.appCardBackground).frame(height: 220).redacted(reason: .placeholder)
            RoundedRectangle(cornerRadius: 16).fill(Color.appCardBackground).frame(height: 120).redacted(reason: .placeholder)
            RoundedRectangle(cornerRadius: 16).fill(Color.appCardBackground).frame(height: 120).redacted(reason: .placeholder)
        }
        .shimmer()
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
            grouped[key] = grouped[key]?.sorted { $0.date > $1.date }
        }
        return grouped
    }

    private func accountSection(id: String, title: String, icon: String, color: Color, accounts: [Account]) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation {
                    if expandedSections.contains(id) {
                        expandedSections.remove(id)
                    } else {
                        expandedSections.insert(id)
                    }
                }
            } label: {
                sectionHeader(title: title, icon: icon, color: color, count: accounts.count, sectionId: id)
            }
            .buttonStyle(.plain)

            if expandedSections.contains(id) {
                VStack(spacing: 0) {
                    ForEach(accounts) { account in
                        NavigationLink(destination: WalletDetailView(
                            account: account,
                            transactions: accountTransactions[account.id] ?? [],
                            categories: categories,
                            onSave: { id, name, type, icon, isArchived, newBalance, oldBalance, creditLimit, dueDate in
                                return await viewModel.rebalanceAccount(id: id, name: name, type: type, icon: icon, isArchived: isArchived, newBalance: newBalance, oldBalance: oldBalance, userId: authViewModel.currentUser?.id ?? "", creditLimit: creditLimit, dueDate: dueDate)
                            },
                            onDelete: { id in return await viewModel.removeAccount(id: id) },
                            onToggleArchive: { id, archived in return await viewModel.toggleAccountArchive(id: id) },
                            onSetDefault: { id in await viewModel.setDefaultAccount(id: id, userId: authViewModel.currentUser?.id ?? "") }
                        )) {
                            AccountCard(account: account)
                        }
                        .buttonStyle(RowPressStyle())
                        if account.id != accounts.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.vertical, Spacing.sm)
            }
        }
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func sectionHeader(title: String, icon: String, color: Color, count: Int, sectionId: String) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(color)
                .frame(width: 4)
                .clipShape(Capsule())

            HStack(spacing: 4) {
                Text(title)
                    .font(.jakarta(15, weight: .semibold))
                    .foregroundColor(.appText)

                Spacer()

                Text("\(count)")
                    .font(.jakarta(13, weight: .semibold))
                    .foregroundColor(.appTextSecondary)

                Image(systemName: "chevron.down")
                    .font(.jakarta(9))
                    .foregroundColor(.appTextSecondary)
                    .rotationEffect(.degrees(expandedSections.contains(sectionId) ? 0 : -90))
                    .padding(.leading, 4)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, 12)
        }
    }

    private var archiveSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation {
                    showArchived.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: showArchived ? "archivebox.fill" : "archivebox")
                        .font(.jakarta(12))
                        .foregroundColor(.appWarning)
                    Text("Diarsipkan")
                        .font(.jakarta(13, weight: .medium))
                        .foregroundColor(.appText)
                    Spacer()
                    Text("\(archivedAccounts.count)")
                        .font(.jakarta(12, weight: .semibold))
                        .foregroundColor(.appTextSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.appTextSecondary.opacity(0.15))
                        .clipShape(Capsule())
                    Image(systemName: "chevron.down")
                        .font(.jakarta(10))
                        .foregroundColor(.appTextSecondary)
                        .rotationEffect(.degrees(showArchived ? 180 : 0))
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .padding(.vertical, 12)
                .padding(.horizontal, Spacing.lg)
            }
            .buttonStyle(.plain)

            if showArchived {
                VStack(spacing: Spacing.lg) {
                    ForEach(archivedAccounts) { account in
                        NavigationLink(destination: WalletDetailView(
                            account: account,
                            transactions: accountTransactions[account.id] ?? [],
                            categories: categories,
                            onSave: { id, name, type, icon, isArchived, newBalance, oldBalance, creditLimit, dueDate in
                                return await viewModel.rebalanceAccount(id: id, name: name, type: type, icon: icon, isArchived: isArchived, newBalance: newBalance, oldBalance: oldBalance, userId: authViewModel.currentUser?.id ?? "", creditLimit: creditLimit, dueDate: dueDate)
                            },
                            onDelete: { id in
                                return await viewModel.removeAccount(id: id)
                            },
                            onToggleArchive: { id, archived in
                                return await viewModel.toggleAccountArchive(id: id)
                            }
                        )) {
                            AccountCard(account: account)
                                .opacity(0.7)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, Spacing.sm)
            }
        }
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var totalBalanceCard: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "wallet.pass.fill")
                    .font(.jakarta(12))
                    .foregroundColor(.appPrimary)
                Text("Total Saldo")
                    .font(.jakarta(12))
                    .foregroundColor(.appTextSecondary)
                Spacer()
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xl)

            Text(isBalanceVisible ? viewModel.totalBalance.formattedAsCurrency() : "Rp********")
                .font(.jakarta(34, weight: .bold))
                .contentTransition(.numericText())
                .foregroundColor(.appText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.sm)

            if viewModel.totalCreditDebt > 0 {
                HStack {
                    Image(systemName: "creditcard.fill")
                        .font(.jakarta(11))
                        .foregroundColor(.appExpense)
                    Text("Total Utang Kartu Kredit")
                        .font(.jakarta(12))
                        .foregroundColor(.appTextSecondary)
                    Spacer()
                    Text(isBalanceVisible ? viewModel.totalCreditDebt.formattedAsCurrency() : "Rp***")
                        .font(.jakarta(13, weight: .semibold))
                        .foregroundColor(.appExpense)
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.sm)
            }

            Divider()
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.lg)

            HStack {
                let totalActive = walletAccounts.count + creditAccounts.count
                Image(systemName: "checkmark.circle.fill")
                    .font(.jakarta(11))
                    .foregroundColor(.appPrimary)
                Text("\(totalActive) Akun Aktif")
                    .font(.jakarta(13))
                    .foregroundColor(.appTextSecondary)
                Spacer()
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.lg)

            Button {
                showAddWallet = true
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "plus")
                        .font(.jakarta(15, weight: .semibold))
                    Text("Tambah")
                        .font(.jakarta(15, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.appPrimary)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.lg)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.appCardBackground)
        )
        .overlay(alignment: .topTrailing) {
            Image(systemName: "wallet.pass.fill")
                .font(.system(size: 48))
                .foregroundColor(.appPrimary.opacity(0.08))
                .offset(x: -12, y: -4)
        }
    }
}

struct AccountCard: View {
    let account: Account
    @AppStorage("isBalanceVisible") private var isBalanceVisible = true

    private var walletIcon: WalletIcon? {
        WalletIcon.resolve(account.icon)
    }

    private var accentColor: Color {
        switch account.type {
        case .cash: return .appIncome
        case .bank: return .appPrimary
        case .ewallet: return .appWarning
        case .credit: return .appExpense
        }
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            WalletIconView(icon: walletIcon, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(account.name)
                        .font(.jakarta(16, weight: .semibold))
                        .foregroundColor(.appText)
                        .lineLimit(1)
                    if account.isDefault {
                        Text("Utama")
                            .font(.jakarta(8, weight: .medium))
                            .foregroundColor(.appWarning)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.appWarning.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            if account.isCreditCard {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Sisa Limit")
                        .font(.jakarta(9))
                        .foregroundColor(.appTextSecondary)
                    Text(isBalanceVisible ? (account.availableCredit?.formattedAsCurrency() ?? "-") : "Rp***")
                        .font(.jakarta(15, weight: .semibold))
                        .foregroundColor(.appText)
                }
            } else {
                Text(isBalanceVisible ? account.balance.formattedAsCurrency() : "Rp***")
                    .font(.jakarta(15, weight: .semibold))
                    .foregroundColor(.appText)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 12)
    }

    private var accountTypeIcon: String {
        switch account.type {
        case .cash: return "banknote"
        case .bank: return "building.columns"
        case .ewallet: return "wallet.pass"
        case .credit: return "creditcard.fill"
        }
    }
}

