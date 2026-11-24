import Foundation

/// Turning a purchase that already happened into a 0% installment (PRD Cicilan Berulang Setelah Transaksi, C3, C6).
enum InstallmentConversion {
    /// "yyyy-MM-dd" of the day the parts start from when the purchase is already on a closed statement (the conversion
    /// day); nil when it is still in the running period, so the purchase date counts as for a new installment.
    static func startsFrom(purchaseDate: Date, card: Account, today: Date = Date(), calendar: Calendar = .current) -> String? {
        let last = CreditStatement.lastCutoff(card: card, today: today, calendar: calendar)
        guard calendar.startOfDay(for: purchaseDate) <= last else { return nil }
        return CardInstallment.dateOnly.string(from: today)
    }

    /// What the conversion does to the last bill, for the warning of C6: the payments made since the cut-off can end up
    /// larger than what is still billed, and the excess takes off the next bill.
    static func overpayment(card: Account, transactions: [Transaction], installments: [CardInstallment], adding plan: CardInstallment,
                            today: Date = Date(), calendar: Calendar = .current) -> Double {
        guard let after = CreditStatement(card: card, transactions: transactions, installments: installments + [plan],
                                          today: today, calendar: calendar) else { return 0 }
        return max(0, after.paid - after.statementAmount)
    }
}
