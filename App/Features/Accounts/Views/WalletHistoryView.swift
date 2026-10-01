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
                case .income, .cardPayment: flow.0 += txn.amount
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
                    EmptyMessage(icon: "clock.arrow.circlepath", title: L("Belum ada transaksi"),
                                 message: L("Transaksi yang kamu catat di %@ akan muncul di sini.", account.name))
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
        .navigationTitle("Riwayat")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            try? await Task.sleep(for: .milliseconds(120))
            isEntered = true
        }
    }

    /// Design 1c: this month's two totals side by side in a soft box.
    private var header: some View {
        let flow = monthFlow
        let card = account.isCreditCard
        return HStack(spacing: 0) {
            flowLabel(card ? L("Terpakai bulan ini") : L("Keluar bulan ini"), flow.out, color: .appText)
            Rectangle().fill(Color(light: 0xE5E5EA, dark: 0x3A3A3C)).frame(width: 1)
            flowLabel(card ? L("Dibayar bulan ini") : L("Masuk bulan ini"), flow.in, color: .appPrimary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(light: 0xF7F7F8, dark: 0x1C1C1E), in: RoundedRectangle(cornerRadius: 16))
        .padding(.top, 8)
    }

    private func flowLabel(_ title: String, _ amount: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.app(13)).foregroundStyle(Color.appTextSecondary)
            Text(isBalanceVisible ? amount.formattedAsCurrency() : "Rp" + hiddenAmount)
                .font(.app(18, weight: .semibold))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rows: some View {
        let list = sorted
        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.element.id) { index, transaction in
                if index == 0 || !Calendar.current.isDate(transaction.date, inSameDayAs: list[index - 1].date) {
                    Text(DashboardView.dayHeader(for: transaction.date))
                        .font(.app(13, weight: .semibold))
                        .foregroundStyle(Color.appTextSecondary)
                        .padding(.top, 22)
                        .padding(.bottom, 4)
                }
                NavigationLink(destination: TransactionDetailView(transaction: transaction, categories: categories,
                                                                  accounts: accounts).detailPage()) {
                    TransactionRowView(transaction: transaction, categories: categories, accounts: accounts,
                                       showBalance: isBalanceVisible, showDate: false)
                }
                .buttonStyle(RowPressStyle())
            }
            Text("Semua transaksi sudah ditampilkan")
                .font(.app(13))
                .foregroundStyle(Color.appTextTertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 28)
        }
    }
}
