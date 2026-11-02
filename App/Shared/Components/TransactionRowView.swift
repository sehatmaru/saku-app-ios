import SwiftUI

struct TransactionRowView: View {
    let transaction: Transaction
    let categories: [Category]
    let accounts: [Account]
    var showBalance: Bool = true
    /// Appends the account (or "A → B" for transfers) to the subtitle.
    var showAccount: Bool = false
    /// Off inside lists that already group rows under day headers.
    var showDate: Bool = true
    var showArchivedBadge: Bool = false
    /// Under the amount: the wallet's colour swatch and name, or "Sumber → Tujuan" for a transfer.
    var showWalletChip: Bool = false

    private var category: Category? {
        transaction.categoryId.flatMap { cid in categories.first { $0.id == cid } }
    }

    private func accountName(_ id: String?) -> String? {
        accounts.first { $0.id == id }?.name
    }

    /// A transfer into a credit card pays its bill.
    private var isCardPayment: Bool {
        transaction.type == .transfer
            && accounts.first { $0.id == transaction.counterpartyAccountId }?.isCreditCard == true
    }

    private var iconName: String {
        switch transaction.type {
        case .adjustment: "arrow.2.circlepath"
        case .cardPayment: "creditcard"
        case .transfer: isCardPayment ? "creditcard" : "arrow.left.arrow.right"
        case .income: category?.icon ?? "arrow.down"
        case .expense: category?.icon ?? "arrow.up"
        }
    }

    private var typeLabel: String {
        switch transaction.type {
        case .income: L("Pemasukan")
        case .expense: L("Pengeluaran")
        case .transfer: isCardPayment ? L("Bayar tagihan") : L("Transfer")
        case .adjustment: L("Penyesuaian saldo")
        case .cardPayment: L("Bayar tagihan")
        }
    }

    private var title: String {
        transaction.recurringName ?? transaction.displayNote ?? category?.name ?? typeLabel
    }

    private var subtitle: String {
        var parts: [String] = []
        let kind = (transaction.type == .income || transaction.type == .expense) ? category?.name : typeLabel
        if let kind, kind != title { parts.append(kind) }
        if showAccount {
            if transaction.type == .cardPayment {
                parts.append(L("Sumber lain"))
            } else if transaction.type == .transfer,
               let src = accountName(transaction.accountId),
               let dst = accountName(transaction.counterpartyAccountId) {
                parts.append("\(src) → \(dst)")
            } else if let name = accountName(transaction.accountId) {
                parts.append(name)
            }
        }
        if showDate { parts.append(Self.dateFormatter.string(from: transaction.date)) }
        // SAKU-770: the hour of the transaction, so rows on the same day can be told apart.
        if let time = TransactionDates.timeOfDay(transaction.date) { parts.append(time) }
        return parts.joined(separator: " · ")
    }

    private var chipWallets: [Account] {
        var ids = [transaction.accountId]
        if transaction.type == .transfer, let to = transaction.counterpartyAccountId { ids.append(to) }
        return ids.compactMap { id in accounts.first { $0.id == id } }
    }

    @ViewBuilder
    private var walletChip: some View {
        if let source = chipWallets.first {
            HStack(spacing: 5) {
                WalletSwatch(account: source)
                Text(chipWallets.map(\.name).joined(separator: " → "))
                    .font(.app(12))
                    .foregroundStyle(Color.appTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: 168, alignment: .trailing)
        }
    }

    private var signedAmount: Double {
        switch transaction.type {
        case .income: transaction.amount
        case .expense: -transaction.amount
        case .transfer: 0
        case .adjustment: transaction.delta ?? transaction.amount
        case .cardPayment: transaction.amount
        }
    }

    private var amountText: String {
        let body = transaction.amount.formattedAsCurrency().replacingOccurrences(of: "-", with: "")
        guard transaction.type != .transfer else { return body }
        let magnitude = abs(signedAmount).formattedAsCurrency()
        return (signedAmount >= 0 ? "+" : "−") + magnitude
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: iconName)
                .font(.system(size: 19))
                .foregroundStyle(Color.appTextSecondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.app(16, weight: .medium))
                        .foregroundStyle(Color.appText)
                        .lineLimit(1)
                    if transaction.isRecurring {
                        Label("Berulang", systemImage: "repeat")
                            .font(.app(11, weight: .medium))
                            .foregroundStyle(Color.appPrimary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 1)
                            .background(Color.appPrimary.opacity(0.12), in: Capsule())
                            .fixedSize()
                    }
                    if showArchivedBadge {
                        Text("Diarsipkan")
                            .font(.app(11, weight: .medium))
                            .foregroundStyle(Color.appTextSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 1)
                            .overlay(Capsule().strokeBorder(Color.appBorder))
                    }
                }
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(showBalance ? amountText : "Rp" + hiddenAmount)
                    .font(.app(16))
                    .monospacedDigit()
                    .foregroundStyle(signedAmount > 0 ? Color.appIncome : Color.appText)
                    .lineLimit(1)
                    .fixedSize()
                if showWalletChip { walletChip }
            }
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private static var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        f.locale = AppLanguage.locale
        return f
    }
}

/// The wallet's colour as a small card: a stripe for credit cards, a firm edge for cash.
struct WalletSwatch: View {
    let account: Account
    var width: CGFloat = 18
    var height: CGFloat = 12

    var body: some View {
        let ink: Color = account.walletColor.isLight ? .black.opacity(0.4) : .white.opacity(0.55)
        RoundedRectangle(cornerRadius: height / 4)
            .fill(account.walletColor)
            .frame(width: width, height: height)
            .overlay {
                if account.isCreditCard {
                    Rectangle().fill(ink).frame(height: height / 6).frame(maxHeight: .infinity, alignment: .top).padding(.top, height / 4)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: height / 4)
                .strokeBorder(account.type == .cash ? Color.appTextSecondary : Color.gray.opacity(0.35), lineWidth: 1))
    }
}
