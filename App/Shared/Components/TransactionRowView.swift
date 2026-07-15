import SwiftUI

struct TransactionRowView: View {
    let transaction: Transaction
    let categories: [Category]
    let accounts: [Account]
    var showBalance: Bool = true
    var showWalletBadge: Bool = false
    var showArchivedBadge: Bool = false

    private var isTransfer: Bool { transaction.type == .transfer }
    private var isAdjustment: Bool { transaction.type == .adjustment }

    private var cellColor: Color {
        switch transaction.type {
        case .income: .appIncome
        case .expense: .appExpense
        case .transfer: .appText
        case .adjustment: .appText
        }
    }

    private var iconName: String {
        if isAdjustment { return "arrow.2.circlepath" }
        if isTransfer { return "arrow.left.arrow.right" }
        let catIcon = transaction.categoryId.flatMap { cid in categories.first { $0.id == cid }?.icon }
        return catIcon ?? (transaction.type == .income ? "arrow.down" : "arrow.up")
    }

    private var title: String {
        transaction.note ?? typeLabel
    }

    private var typeLabel: String {
        switch transaction.type {
        case .income: "Pemasukan"
        case .expense: "Pengeluaran"
        case .transfer: "Transfer"
        case .adjustment: "Penyesuaian saldo"
        }
    }

    private var signedAmount: Double { transaction.delta ?? transaction.amount }

    private var amountColor: Color {
        isAdjustment ? (signedAmount >= 0 ? .appIncome : .appExpense) : cellColor
    }

    private var amountText: String {
        isAdjustment ? (signedAmount >= 0 ? "+" + signedAmount.formattedAsCurrency() : signedAmount.formattedAsCurrency()) : transaction.amount.formattedAsCurrency()
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            iconSection
            detailSection
            Spacer()
            if showBalance {
                Text(amountText)
                    .font(.jakarta(14, weight: .semibold))
                    .foregroundColor(amountColor)
            } else {
                Text("Rp***")
                    .font(.jakarta(14, weight: .semibold))
                    .foregroundColor(amountColor)
            }
        }
        .padding(.vertical, Spacing.sm)
        .contentShape(Rectangle())
    }

    private var iconSection: some View {
        ZStack {
            Circle()
                .fill(cellColor.opacity((isTransfer || isAdjustment) ? 0.08 : 0.15))
                .frame(width: 44, height: 44)
            Image(systemName: iconName)
                .font(.jakarta(16))
                .foregroundColor(cellColor)
        }
        .overlay(alignment: .bottomTrailing) {
            if showWalletBadge, !isTransfer, !isAdjustment,
               let acc = accounts.first(where: { $0.id == transaction.accountId }),
               let wi = WalletIcon.resolve(acc.icon) {
                walletBadge(wi: wi)
            }
        }
    }

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            if isTransfer,
               let dst = accounts.first(where: { $0.id == transaction.counterpartyAccountId }),
               let dwi = WalletIcon.resolve(dst.icon) {
                HStack(spacing: 3) {
                    if let src = accounts.first(where: { $0.id == transaction.accountId }),
                       let swi = WalletIcon.resolve(src.icon) {
                        ZStack {
                            Circle().fill(swi.color).frame(width: 20, height: 20)
                            Text(swi.shortName)
                                .font(.jakarta(6, weight: .bold))
                                .foregroundColor(.white)
                                .minimumScaleFactor(0.5)
                        }
                    }
                    Image(systemName: "arrow.right")
                        .font(.jakarta(8))
                        .foregroundColor(.appTextSecondary)
                    ZStack {
                        Circle().fill(dwi.color).frame(width: 20, height: 20)
                        Text(dwi.shortName)
                            .font(.jakarta(6, weight: .bold))
                            .foregroundColor(.white)
                            .minimumScaleFactor(0.5)
                    }
                }
                .lineLimit(1)
            } else {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.jakarta(14, weight: .medium))
                        .lineLimit(1)
                    if showArchivedBadge {
                        Text("Diarsipkan")
                            .font(.jakarta(9, weight: .medium))
                            .foregroundColor(.appWarning)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.appWarning.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }

            Text(formattedDate(transaction.date))
                .font(.jakarta(11))
                .foregroundColor(.appTextSecondary)
        }
    }

    private func walletBadge(wi: WalletIcon) -> some View {
        ZStack {
            Circle()
                .fill(wi.color)
                .frame(width: 18, height: 18)
            Text(wi.shortName)
                .font(.jakarta(6, weight: .bold))
                .foregroundColor(.white)
                .minimumScaleFactor(0.5)
        }
        .offset(x: 4, y: 4)
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd MMM yyyy"
        f.locale = Locale(identifier: "id_ID")
        return f.string(from: date)
    }
}