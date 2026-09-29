import SwiftUI

/// Pushes a wallet's full history (the plain `Account` route opens its edit page).
struct WalletHistoryRoute: Hashable {
    let account: Account
}

/// Every transaction on one wallet, newest first, grouped by day. Pushed from "Riwayat".
struct WalletHistoryView: View {
    let account: Account
    let transactions: [Transaction]
    let categories: [Category]
    let accounts: [Account]
    let isBalanceVisible: Bool

    @State private var isEntered = false

    private var sorted: [Transaction] { transactions.sorted { $0.date > $1.date } }

    /// What went in and out of this wallet this month; a card's charges count as out.
    private var monthFlow: (in: Double, out: Double) {
        let calendar = Calendar.current
        return sorted.filter { calendar.isDate($0.date, equalTo: Date(), toGranularity: .month) }
            .reduce(into: (0.0, 0.0)) { flow, txn in
                switch txn.type {
                case .income: flow.0 += txn.amount
                case .expense: flow.1 += txn.amount
                case .transfer:
                    if txn.counterpartyAccountId == account.id { flow.0 += txn.amount } else { flow.1 += txn.amount }
                case .adjustment: break
                }
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .opacity(isEntered ? 1 : 0)
                    .offset(y: isEntered ? 0 : 10)
                if sorted.isEmpty {
                    EmptyMessage(icon: "clock.arrow.circlepath", title: "Belum ada transaksi",
                                 message: "Transaksi yang kamu catat di \(account.name) akan muncul di sini.")
                        .padding(.top, 80)
                } else {
                    rows
                        .opacity(isEntered ? 1 : 0)
                        .offset(y: isEntered ? 0 : 18)
                        .animation(.settle(0.5).delay(0.08), value: isEntered)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .animation(.settle(0.46), value: isEntered)
        }
        .scrollIndicators(.hidden)
        .background(Color.appBackground)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            try? await Task.sleep(for: .milliseconds(120))
            isEntered = true
        }
    }

    private var header: some View {
        let flow = monthFlow
        return VStack(alignment: .leading, spacing: 6) {
            Text("Riwayat")
                .font(.app(13))
                .foregroundStyle(Color.appTextSecondary)
            Text(account.name)
                .font(.app(30, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(Color.appText)
            HStack(spacing: 16) {
                flowLabel(account.isCreditCard ? "Dibayar bulan ini" : "Masuk bulan ini", flow.in, color: .appIncome)
                flowLabel(account.isCreditCard ? "Terpakai bulan ini" : "Keluar bulan ini", flow.out, color: .appError)
            }
            .padding(.top, 10)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func flowLabel(_ title: String, _ amount: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.app(12)).foregroundStyle(Color.appTextSecondary)
            Text(isBalanceVisible ? amount.formattedAsCurrency() : "Rp•••")
                .font(.app(16, weight: .semibold))
                .foregroundStyle(amount > 0 ? color : Color.appText)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rows: some View {
        let list = sorted
        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.element.id) { index, transaction in
                if index == 0 || !Calendar.current.isDate(transaction.date, inSameDayAs: list[index - 1].date) {
                    Text(DashboardView.dayHeader(for: transaction.date))
                        .font(.app(13))
                        .tracking(0.2)
                        .foregroundStyle(Color.appTextSecondary)
                        .padding(.top, 22)
                }
                NavigationLink(destination: TransactionDetailView(transaction: transaction, categories: categories,
                                                                  accounts: accounts).detailPage()) {
                    TransactionRowView(transaction: transaction, categories: categories, accounts: accounts,
                                       showBalance: isBalanceVisible, showDate: false)
                }
                .buttonStyle(RowPressStyle())
            }
        }
    }
}
