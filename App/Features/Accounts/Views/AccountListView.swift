import SwiftUI

struct AccountListView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel = AccountListViewModel()
    @AppStorage("isBalanceVisible") private var isBalanceVisible = true
    @State private var showAddWallet = false
    @State private var showArchived = false
    @State private var accountTransactions: [String: [Transaction]] = [:]
    @State private var cachedUserId: String?

    private var activeAccounts: [Account] {
        viewModel.accounts.filter { $0.isActive }
    }

    private var archivedAccounts: [Account] {
        viewModel.accounts.filter { !$0.isActive }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    if !viewModel.hasLoadedOnce {
                        skeletonContent
                    } else {
                        totalBalanceCard

                        ForEach(activeAccounts) { account in
                            NavigationLink(destination: WalletDetailView(
                                    account: account,
                                    transactions: accountTransactions[account.id] ?? [],
                                    onSave: { id, name, type, balance, icon, isArchived in
                                        await viewModel.updateAccount(id: id, name: name, type: type, openingBalance: balance, icon: icon, isArchived: isArchived)
                                    },
                                    onDelete: { id in
                                        await viewModel.removeAccount(id: id)
                                    },
                                    onToggleArchive: { id, archived in
                                        await viewModel.toggleAccountArchive(id: id)
                                    }
                            )) {
                                AccountCard(account: account)
                            }
                            .buttonStyle(.plain)
                        }

                        if !archivedAccounts.isEmpty {
                            archiveSection
                        }
                    }
                }
                .padding()
            }
            .background(Color.appGroupedBackground)
            .refreshable {
                guard let userId = authViewModel.currentUser?.id else { return }
                await viewModel.loadAccounts(userId: userId, forceRefresh: true)
                await syncAccountTransactions(userId: userId)
            }
            .navigationTitle("Dompet")
            .task {
                guard let userId = authViewModel.currentUser?.id else { return }
                await viewModel.loadAccounts(userId: userId)
                await syncAccountTransactions(userId: userId)
            }
            .onReceive(NotificationCenter.default.publisher(for: .dataDidChange)) { _ in
                guard let userId = authViewModel.currentUser?.id else { return }
                Task {
                    await viewModel.loadAccounts(userId: userId, forceRefresh: true)
                    await syncAccountTransactions(userId: userId)
                }
            }
            .sheet(isPresented: $showAddWallet) {
                if let userId = authViewModel.currentUser?.id {
                    AddWalletView { name, type, balance, icon in
                        await viewModel.addAccount(name: name, type: type, openingBalance: balance, icon: icon, userId: userId)
                        await syncAccountTransactions(userId: userId)
                    }
                }
            }
        }
    }

    private var skeletonContent: some View {
        VStack(spacing: Spacing.lg) {
            RoundedRectangle(cornerRadius: 20).fill(Color.appCardBackground).frame(height: 220).redacted(reason: .placeholder)
            RoundedRectangle(cornerRadius: 16).fill(Color.appCardBackground).frame(height: 120).redacted(reason: .placeholder)
            RoundedRectangle(cornerRadius: 16).fill(Color.appCardBackground).frame(height: 120).redacted(reason: .placeholder)
        }
    }

    private func syncAccountTransactions(userId: String, forceRefresh: Bool = false) async {
        if let cached = AppDataCache.shared.accountTransactions(for: userId) {
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
        } catch {
            // Keep existing detail transactions if refresh fails.
        }
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
                            onSave: { id, name, type, balance, icon, isArchived in
                                await viewModel.updateAccount(id: id, name: name, type: type, openingBalance: balance, icon: icon, isArchived: isArchived)
                            },
                            onDelete: { id in
                                await viewModel.removeAccount(id: id)
                            },
                            onToggleArchive: { id, archived in
                                await viewModel.toggleAccountArchive(id: id)
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
                .foregroundColor(.appText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.sm)

            Divider()
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.lg)

            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.jakarta(11))
                    .foregroundColor(.appPrimary)
                Text("\(activeAccounts.count) Dompet Aktif")
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
                    Text("Tambah Dompet")
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

    var body: some View {
        HStack(spacing: Spacing.md) {
            Circle()
                .fill(walletIcon?.color ?? accountTypeColor)
                .frame(width: 44, height: 44)
                .overlay {
                    if let icon = walletIcon {
                        Text(icon.shortName)
                            .font(.jakarta(9, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: accountTypeIcon)
                            .font(.body)
                            .foregroundColor(.white)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.jakarta(17, weight: .semibold))
                Text(account.type.rawValue)
                    .font(.jakarta(12))
                    .foregroundColor(.appTextSecondary)
            }

            Spacer()

            Text(isBalanceVisible ? account.balance.formattedAsCurrency() : "Rp***")
                .font(.jakarta(15, weight: .semibold))
        }
        .padding()
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var accountTypeColor: Color {
        switch account.type {
        case .cash: return .appIncome
        case .bank: return .appPrimary
        case .ewallet: return .appWarning
        }
    }

    private var accountTypeIcon: String {
        switch account.type {
        case .cash: return "banknote"
        case .bank: return "building.columns"
        case .ewallet: return "wallet.pass"
        }
    }
}

#Preview {
    AccountListView()
        .environmentObject(AuthViewModel())
}
