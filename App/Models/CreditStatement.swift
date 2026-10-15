import Foundation

/// A credit card's billing cycle worked out from its balance and transactions.
///
/// The card's balance is its debt. Charges between two cut-offs are billed on the second
/// cut-off (the statement) and due on the next due day. A 0% installment is billed one
/// equal part per statement. What was billed at the last cut-off, minus payments since, is
/// what the user still owes now; everything else on the card is not billed yet.
struct CreditStatement {
    enum Status {
        /// Nothing was billed at the last cut-off.
        case none
        case unpaid, partial, paid, overdue
    }

    /// The last cut-off, at the start of that day; charges up to its end were billed.
    let statementDate: Date
    let dueDate: Date
    let nextStatementDate: Date
    /// Billed at the last cut-off.
    let statementAmount: Double
    /// Paid into the card since the last cut-off.
    let paid: Double
    /// Still owed on the last statement.
    let remaining: Double
    /// Debt not billed yet: charges since the cut-off and installment parts still to come.
    let unbilled: Double
    /// Charges since the last cut-off (payments not netted): what the next statement will bill.
    let currentPeriod: Double
    let status: Status
    /// What's left of the minimum payment after what was already paid.
    let minimumDue: Double
    /// Rough interest next month if only the minimum is paid.
    let interestIfMinimum: Double
    /// Days past the due date while the statement is still owed; 0 otherwise.
    let daysOverdue: Int

    /// The first day whose purchases get the longest interest-free period, and when they're due.
    let bestPurchaseDate: Date
    let bestPurchaseDueDate: Date

    /// Typical Indonesian card interest per month, for estimates only.
    static let monthlyInterest = 0.0175
    static let minimumShare = 0.1
    static let minimumFloor = 50_000.0

    // MARK: Build

    init?(card: Account, transactions: [Transaction], installments: [CardInstallment],
          today: Date = Date(), calendar: Calendar = .current) {
        guard card.isCreditCard else { return nil }
        let cycle = Cycle(card: card, calendar: calendar)
        let todayStart = calendar.startOfDay(for: today)

        let last = cycle.lastCutoff(before: todayStart)
        let boundary = cycle.dayAfter(last)
        statementDate = last
        nextStatementDate = cycle.cutoff(monthAfter: last)
        dueDate = cycle.dueDate(after: last)

        // Everything that moved the debt after the cut-off, so we can rewind to it.
        var changeSince = 0.0
        var paidSince = 0.0
        for txn in transactions where txn.date >= boundary {
            let effect = Self.debtEffect(of: txn, on: card.id)
            changeSince += effect
            // A balance adjustment made after the cut-off is debt the next statement bills; one dated
            // on the cut-off day or before (see `lastCutoffNoon`) is part of the statement itself.
            if txn.type == .adjustment, txn.accountId == card.id { changeSince += txn.delta ?? 0 }
            if txn.type == .transfer, txn.counterpartyAccountId == card.id { paidSince += txn.amount }
            if txn.type == .cardPayment, txn.accountId == card.id { paidSince += txn.amount }
        }
        let balanceAtCutoff = card.balance - changeSince

        // Installment parts the statement hasn't reached yet stay out of what was billed.
        let purchases = Dictionary(transactions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var unbilledParts = 0.0
        for installment in installments where installment.accountId == card.id {
            guard let purchase = purchases[installment.transactionId], purchase.date < boundary else { continue }
            let billed = cycle.cutoffsReached(from: purchase.date, through: last, cap: installment.months)
            unbilledParts += purchase.amount / Double(installment.months) * Double(installment.months - billed)
        }

        // A starting bill entered as "not printed yet" joins the statement at the cut-off it waited for.
        var unbilledOpening = 0.0
        if let until = card.openingUnbilledUntil.flatMap(Self.dateOnly.date(from:)), last < until {
            unbilledOpening = card.openingBalance
        }

        let billedAmount = max(0, balanceAtCutoff - unbilledParts - unbilledOpening)
        statementAmount = billedAmount
        paid = paidSince
        remaining = max(0, billedAmount - paidSince)
        unbilled = max(0, card.balance - remaining)
        currentPeriod = max(0, changeSince + paidSince)

        let minimum = billedAmount > 0 ? min(billedAmount, max(billedAmount * Self.minimumShare, Self.minimumFloor)) : 0
        minimumDue = max(0, minimum - paidSince)
        interestIfMinimum = max(0, remaining - minimumDue) * Self.monthlyInterest

        status = switch (billedAmount < 1, remaining < 1, todayStart > dueDate, paidSince > 0) {
        case (true, _, _, _): .none
        case (_, true, _, _): .paid
        case (_, _, true, _): .overdue
        case (_, _, _, true): .partial
        default: .unpaid
        }

        daysOverdue = status == .overdue
            ? max(calendar.dateComponents([.day], from: dueDate, to: todayStart).day ?? 0, 0)
            : 0

        // Buying the day after a cut-off pushes the bill out a full cycle.
        bestPurchaseDate = boundary == todayStart ? todayStart : cycle.dayAfter(nextStatementDate)
        let bestStatement = cycle.cutoff(monthAfter: boundary == todayStart ? last : nextStatementDate)
        bestPurchaseDueDate = cycle.dueDate(after: bestStatement)
    }

    /// How a transaction changes this card's debt: spending and cash out raise it, refunds and
    /// payments into the card lower it. Adjustments are left out: they're set against the
    /// balance directly, not billed.
    static func debtEffect(of txn: Transaction, on cardId: String) -> Double {
        switch txn.type {
        case .expense where txn.accountId == cardId: txn.amount
        case .income where txn.accountId == cardId: -txn.amount
        case .transfer where txn.accountId == cardId: txn.amount
        case .transfer where txn.counterpartyAccountId == cardId: -txn.amount
        case .cardPayment where txn.accountId == cardId: -txn.amount
        default: 0
        }
    }

    private static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// The next cut-off after today for a card cutting off on `statementDay`, as "yyyy-MM-dd".
    static func nextCutoffString(statementDay: Int, today: Date = Date(), calendar: Calendar = .current) -> String {
        let cycle = Cycle(statementDay: statementDay, dueDay: statementDay, calendar: calendar)
        return dateOnly.string(from: cycle.cutoff(monthAfter: cycle.lastCutoff(before: calendar.startOfDay(for: today))))
    }

    /// Noon on the last cut-off day: a balance adjustment dated here lands in the printed statement.
    static func lastCutoffNoon(statementDay: Int, today: Date = Date(), calendar: Calendar = .current) -> Date {
        let cycle = Cycle(statementDay: statementDay, dueDay: statementDay, calendar: calendar)
        let day = cycle.lastCutoff(before: calendar.startOfDay(for: today))
        return calendar.date(byAdding: .hour, value: 12, to: day) ?? day
    }

    /// The statement a purchase made on `date` lands on, and when that's due.
    static func billing(forPurchaseOn date: Date, card: Account, calendar: Calendar = .current) -> (statement: Date, due: Date) {
        let cycle = Cycle(card: card, calendar: calendar)
        let day = calendar.startOfDay(for: date)
        let statement = cycle.cutoff(monthAfter: cycle.lastCutoff(before: day))
        return (statement, cycle.dueDate(after: statement))
    }

    /// The cut-off the last part of an installment bought on `purchase` is billed on.
    static func finalBillingDate(purchaseOn purchase: Date, months: Int, card: Account, calendar: Calendar = .current) -> Date {
        let cycle = Cycle(card: card, calendar: calendar)
        var cutoff = cycle.cutoff(monthAfter: cycle.lastCutoff(before: calendar.startOfDay(for: purchase)))
        for _ in 1..<max(months, 1) { cutoff = cycle.cutoff(monthAfter: cutoff) }
        return cutoff
    }

    /// The cut-offs every part of an installment bills on, in order (one per month). Used to match
    /// a bank notification against the part it belongs to (Enhancement 3).
    static func partBillings(of installment: CardInstallment, purchaseDate: Date, card: Account,
                             calendar: Calendar = .current) -> [Date] {
        let cycle = Cycle(card: card, calendar: calendar)
        var cutoff = cycle.cutoff(monthAfter: cycle.lastCutoff(before: calendar.startOfDay(for: purchaseDate)))
        var dates: [Date] = []
        for _ in 0..<max(installment.months, 1) {
            dates.append(cutoff)
            cutoff = cycle.cutoff(monthAfter: cutoff)
        }
        return dates
    }

    /// Parts of an installment billed so far (0...months).
    static func billedParts(of installment: CardInstallment, purchaseDate: Date, card: Account,
                            today: Date = Date(), calendar: Calendar = .current) -> Int {
        let cycle = Cycle(card: card, calendar: calendar)
        let last = cycle.lastCutoff(before: calendar.startOfDay(for: today))
        return cycle.cutoffsReached(from: purchaseDate, through: last, cap: installment.months)
    }

    // MARK: Billing cycles

    /// One billing period of a card: the charges between two cut-offs and the payments made toward them.
    struct BillingCycle: Identifiable {
        let start: Date
        /// The cut-off the period ends on; for the open period, the one it is waiting for.
        let end: Date
        let dueDate: Date
        /// Not billed yet: after the last cut-off.
        let isOpen: Bool
        var transactions: [Transaction]
        var charged: Double
        var paid: Double
        var id: Date { end }
    }

    /// The card's periods, newest first: the open one, then each billed one back to its first transaction.
    /// A payment counts toward the statement printed before the day it was made.
    static func cycles(card: Account, transactions: [Transaction], today: Date = Date(),
                       calendar: Calendar = .current, maxCycles: Int = 24) -> [BillingCycle] {
        guard card.isCreditCard else { return [] }
        let cycle = Cycle(card: card, calendar: calendar)
        let todayStart = calendar.startOfDay(for: today)
        let earliest = transactions.map { calendar.startOfDay(for: $0.date) }.min() ?? todayStart

        let last = cycle.lastCutoff(before: todayStart)
        var ends = [cycle.cutoff(monthAfter: last), last]
        func start(of end: Date) -> Date { cycle.dayAfter(cycle.lastCutoff(before: end)) }
        while ends.count < maxCycles, let tail = ends.last, start(of: tail) > earliest {
            ends.append(cycle.lastCutoff(before: tail))
        }
        var result = ends.enumerated().map { index, end in
            BillingCycle(start: start(of: end), end: end, dueDate: cycle.dueDate(after: end),
                         isOpen: index == 0, transactions: [], charged: 0, paid: 0)
        }
        func index(of day: Date) -> Int? { result.firstIndex { day >= $0.start && day <= $0.end } }

        for txn in transactions.sorted(by: { $0.date > $1.date }) {
            guard let own = index(of: calendar.startOfDay(for: txn.date)) else { continue }
            let effect = debtEffect(of: txn, on: card.id)
            let target = effect < 0 && own + 1 < result.count ? own + 1 : own
            result[target].transactions.append(txn)
            if effect > 0 { result[target].charged += effect } else if effect < 0 { result[target].paid -= effect }
        }
        return result
    }

    // MARK: Cycle dates

    /// Cut-off and due days of one card, clamped to each month's length.
    private struct Cycle {
        let statementDay: Int
        let dueDay: Int
        let calendar: Calendar

        init(statementDay: Int, dueDay: Int, calendar: Calendar) {
            self.statementDay = statementDay
            self.dueDay = dueDay
            self.calendar = calendar
        }

        init(card: Account, calendar: Calendar) {
            // Cards saved before cut-off existed: assume the statement prints 15 days before the due day.
            let due = card.dueDay ?? ((card.statementDay ?? 25) + 14) % 31 + 1
            statementDay = card.statementDay ?? (due + 15) % 31 + 1
            dueDay = due
            self.calendar = calendar
        }

        func day(_ day: Int, inMonthOf date: Date) -> Date {
            let comps = calendar.dateComponents([.year, .month], from: date)
            let first = calendar.date(from: comps) ?? date
            let length = calendar.range(of: .day, in: .month, for: first)?.count ?? 28
            return calendar.date(byAdding: .day, value: min(day, length) - 1, to: first) ?? first
        }

        func dayAfter(_ date: Date) -> Date {
            calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }

        /// The latest cut-off strictly before `day`; a cut-off day itself is still open.
        func lastCutoff(before day: Date) -> Date {
            let thisMonth = self.day(statementDay, inMonthOf: day)
            if thisMonth < day { return thisMonth }
            let previous = calendar.date(byAdding: .month, value: -1, to: day) ?? day
            return self.day(statementDay, inMonthOf: previous)
        }

        func cutoff(monthAfter date: Date) -> Date {
            let next = calendar.date(byAdding: .month, value: 1, to: date) ?? date
            return day(statementDay, inMonthOf: next)
        }

        /// The first due day after a cut-off.
        func dueDate(after cutoff: Date) -> Date {
            let sameMonth = day(dueDay, inMonthOf: cutoff)
            if sameMonth > cutoff { return sameMonth }
            let next = calendar.date(byAdding: .month, value: 1, to: cutoff) ?? cutoff
            return day(dueDay, inMonthOf: next)
        }

        /// Cut-offs from the one that bills `purchase` through `last`, capped.
        func cutoffsReached(from purchase: Date, through last: Date, cap: Int) -> Int {
            var cutoff = cutoff(monthAfter: lastCutoff(before: calendar.startOfDay(for: purchase)))
            var count = 0
            while cutoff <= last, count < cap {
                count += 1
                cutoff = self.cutoff(monthAfter: cutoff)
            }
            return count
        }
    }
}
