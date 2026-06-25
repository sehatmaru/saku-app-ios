import SwiftUI

struct AccountListView: View {
    @StateObject private var viewModel = AccountListViewModel()
    @State private var showAddWallet = false
    @State private var showArchived = false

    private var activeAccounts: [Account] {
        viewModel.accounts.filter { $0.isActive }
    }

    private var archivedAccounts: [Account] {
        viewModel.accounts.filter { !$0.isActive }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                totalBalanceCard

                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        ForEach(activeAccounts) { account in
                            NavigationLink(destination: WalletDetailView(
                                account: account,
                                onSave: { updated in
                                    viewModel.updateAccount(updated)
                                },
                                onDelete: { id in
                                    viewModel.removeAccount(id)
                                },
                                onToggleArchive: { id in
                                    viewModel.toggleAccountArchive(id)
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
                    .padding()
                }
            }
            .background(Color.appGroupedBackground)
            .navigationTitle("Dompet")
            .onAppear {
                viewModel.loadAccounts()
            }
            .sheet(isPresented: $showAddWallet) {
                AddWalletView { account in
                    viewModel.addAccount(account)
                }
            }
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
                    Text("Dompet Diarsipkan")
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
                .padding(.vertical, 12)
                .padding(.horizontal, Spacing.lg)
            }
            .buttonStyle(.plain)

            if showArchived {
                VStack(spacing: Spacing.lg) {
                    ForEach(archivedAccounts) { account in
                        NavigationLink(destination: WalletDetailView(
                            account: account,
                            onSave: { updated in
                                viewModel.updateAccount(updated)
                            },
                            onDelete: { id in
                                viewModel.removeAccount(id)
                            },
                            onToggleArchive: { id in
                                viewModel.toggleAccountArchive(id)
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

            Text(viewModel.totalBalance.formattedAsCurrency())
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
        .padding(.horizontal)
        .padding(.top)
        .padding(.bottom, 4)
    }
}

struct AccountCard: View {
    let account: Account

    private var walletIcon: WalletIcon? {
        WalletIcon.allIcons.first { $0.id == account.icon }
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

            Text(account.balance.formattedAsCurrency())
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
