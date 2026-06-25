import SwiftUI

struct AccountListView: View {
    @StateObject private var viewModel = AccountListViewModel()
    @State private var showAddWallet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    totalBalanceCard

                    ForEach(viewModel.accounts) { account in
                        AccountCard(account: account)
                    }
                }
                .padding()
            }
            .background(Color.appGroupedBackground)
            .navigationTitle("Dompet")
            .onAppear {
                viewModel.loadAccounts()
            }
            .alert("Tambah Dompet", isPresented: $showAddWallet) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Fitur akan segera tersedia.")
            }
        }
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
                Text("\(viewModel.accounts.count) Akun Terdaftar")
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

    var body: some View {
        HStack(spacing: Spacing.md) {
            Circle()
                .fill(accountTypeColor)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: accountTypeIcon)
                        .font(.body)
                        .foregroundColor(.white)
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
