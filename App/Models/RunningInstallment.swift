import Foundation

/// A 0% card installment that is still being billed in the period the user is looking at. Informative only:
/// it reads `card_installments` and the statement logic and changes no total, Net or budget.
struct RunningInstallment: Identifiable, Equatable {
    let id: String
    let title: String
    let cardName: String
    let months: Int
    /// Parts billed by the end of the period (0 for a purchase whose first statement is still to come).
    let billedParts: Int
    /// About one part: the purchase divided by the months (the bank's own rounding may differ a little).
    let monthly: Double
    let total: Double
    let purchaseDate: Date
    /// The cut-off the first part is billed on; only set while nothing has been billed.
    let firstBillingDate: Date?

    var remainingParts: Int { months - billedParts }
}

enum RunningInstallments {
    /// The installments still running at `periodEnd`: fewer parts billed (cut-offs of the card passed since the
    /// purchase, counted up to the end of the period) than months. Past periods use the same call with their own end.
    static func compute(installments: [CardInstallment], transactions: [Transaction], accounts: [Account],
                        periodEnd: Date, calendar: Calendar = .current) -> [RunningInstallment] {
        let cards = Dictionary(accounts.filter(\.isCreditCard).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let purchases = Dictionary(transactions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return installments.compactMap { plan -> RunningInstallment? in
            guard plan.months > 0, let card = cards[plan.accountId], let purchase = purchases[plan.transactionId],
                  purchase.date <= periodEnd else { return nil }
            let billed = CreditStatement.billedParts(of: plan, purchaseDate: purchase.date, card: card, today: periodEnd, calendar: calendar)
            guard billed < plan.months else { return nil }
            let first = billed == 0 ? CreditStatement.billing(forPurchaseOn: purchase.date, card: card, calendar: calendar).statement : nil
            return RunningInstallment(id: plan.id, title: purchase.displayNote ?? L("Pembelian cicilan"), cardName: card.name,
                                      months: plan.months, billedParts: billed, monthly: purchase.amount / Double(plan.months),
                                      total: purchase.amount, purchaseDate: purchase.date, firstBillingDate: first)
        }
        .sorted { $0.purchaseDate > $1.purchaseDate }
    }
}
