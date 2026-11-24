import Foundation

/// A 0% card installment that is still being billed in the period the user is looking at. Informative only:
/// it reads `card_installments` and the statement logic and changes no total, Net or budget.
struct RunningInstallment: Identifiable, Equatable {
    let id: String
    /// The purchase transaction, opened when a row is tapped.
    let transactionId: String
    /// The card the installment is billed on; for matching notifications (Enhancement 3).
    let accountId: String
    let title: String
    let cardName: String
    /// The card's wallet icon id, for its logo.
    let cardIcon: String?
    let months: Int
    /// Parts billed by the end of the period (0 for a purchase whose first statement is still to come).
    let billedParts: Int
    /// About one part: the purchase divided by the months (the bank's own rounding may differ a little).
    let monthly: Double
    let total: Double
    let purchaseDate: Date
    /// The cut-off each part is billed on, in order (Enhancement 3).
    let billingDates: [Date]
    /// The cut-off the first part is billed on; only set while nothing has been billed.
    let firstBillingDate: Date?
    /// The cut-off the last part is billed on: when the installment is paid off.
    let endDate: Date

    /// An early payoff already chosen: the day, how, and the statement that bills the rest (next-statement mode).
    struct Settlement: Equatable {
        let day: Date
        let mode: CardInstallment.SettleMode
        let billingDate: Date
    }
    let settlement: Settlement?
    let plan: CardInstallment

    var remainingParts: Int { months - billedParts }

    /// S = A - round(A / n) x b: what an early payoff settles (C8).
    var remainingAmount: Double { CardInstallment.remaining(of: total, months: months, billed: billedNow) }

    /// Parts whose cut-off has already passed today; `billedParts` counts to the end of the period instead.
    /// Rows and the detail page show this one so they agree.
    var billedNow: Int { billingDates.filter { $0 <= Date() }.count }
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
            var billings = CreditStatement.partBillings(of: plan, purchaseDate: purchase.date, card: card, calendar: calendar)
            var settlement: RunningInstallment.Settlement?
            if let settle = plan.settlement {
                // paid from a wallet: over from that day; into the next statement: over once that cut-off has passed
                let cutoff = CreditStatement.billing(forPurchaseOn: settle.day, card: card, calendar: calendar).statement
                if settle.mode == .paid ? settle.day <= periodEnd : cutoff <= periodEnd { return nil }
                if settle.mode == .nextStatement { billings = Array(billings.prefix(billed)) + [cutoff] }
                settlement = .init(day: settle.day, mode: settle.mode, billingDate: cutoff)
            }
            return RunningInstallment(id: plan.id, transactionId: purchase.id, accountId: plan.accountId,
                                      title: purchase.displayNote ?? L("Pembelian cicilan"), cardName: card.name, cardIcon: card.icon,
                                      months: plan.months, billedParts: billed, monthly: CardInstallment.part(1, of: purchase.amount, months: plan.months),
                                      total: purchase.amount, purchaseDate: purchase.date, billingDates: billings,
                                      firstBillingDate: billed == 0 ? billings.first : nil,
                                      endDate: billings.last ?? CreditStatement.finalBillingDate(purchaseOn: purchase.date, months: plan.months, card: card, calendar: calendar),
                                      settlement: settlement, plan: plan)
        }
        .sorted { $0.purchaseDate > $1.purchaseDate }
    }
}
