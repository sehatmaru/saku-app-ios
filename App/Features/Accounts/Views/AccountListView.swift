import SwiftUI

struct AccountListView: View {
    @StateObject private var viewModel = AccountListViewModel()

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
        }
    }

    private var totalBalanceCard: some View {
        VStack(spacing: Spacing.sm) {
            Text("Total Saldo")
                .font(.jakarta(15))
                .foregroundColor(.appTextSecondary)

            Text(viewModel.totalBalance.formattedAsCurrency())
                .font(.jakarta(34, weight: .bold))
                .foregroundColor(.appText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
