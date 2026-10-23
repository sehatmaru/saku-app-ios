import Foundation

/// The value and the capital of an investment wallet at each change (Perbarui nilai, setor, tarik), for the chart
/// in its detail (Fitur 7 US1). Built from the same transactions as `InvestmentHistory`; nothing new is stored.
struct InvestmentSeries: Equatable {
    struct Point: Equatable {
        let date: Date
        let value: Double
        let capital: Double
        /// A real change (shown as a dot); false for the point that only anchors the line at the start of the range.
        let isChange: Bool
    }

    enum Range: CaseIterable {
        case months3, months6, year1, all

        var title: String {
            switch self {
            case .months3: L("3 bulan")
            case .months6: L("6 bulan")
            case .year1: L("1 tahun")
            case .all: L("Semua")
            }
        }

        /// The first day the range shows; nil for all of it.
        func start(from now: Date, calendar: Calendar = .current) -> Date? {
            switch self {
            case .months3: calendar.date(byAdding: .month, value: -3, to: now)
            case .months6: calendar.date(byAdding: .month, value: -6, to: now)
            case .year1: calendar.date(byAdding: .year, value: -1, to: now)
            case .all: nil
            }
        }
    }

    /// Oldest first, in the range. The line runs from the wallet's state at the start of the range.
    let points: [Point]

    /// The chart needs two points to draw a line between.
    var hasLine: Bool { points.count >= 2 }

    init(points: [Point]) { self.points = points }

    init(account: Account, transactions: [Transaction], range: Range, now: Date = Date()) {
        var value = account.openingBalance
        var capital = account.openingBalance
        var all: [Point] = []
        if account.openingBalance > 0 {
            let opened = account.openedDate ?? transactions.map(\.date).min() ?? now
            all.append(Point(date: opened, value: value, capital: capital, isChange: true))
        }
        let ordered = transactions
            .filter { $0.accountId == account.id || $0.counterpartyAccountId == account.id }
            .filter { $0.type == .transfer || ($0.type == .adjustment && $0.accountId == account.id) }
            .sorted { $0.date < $1.date }
        for txn in ordered {
            switch txn.type {
            case .transfer where txn.counterpartyAccountId == account.id:
                value += txn.amount; capital += txn.amount
            case .transfer:
                value -= txn.amount; capital -= txn.amount
            default:
                value += txn.delta ?? txn.amount
            }
            all.append(Point(date: txn.date, value: value, capital: capital, isChange: true))
        }

        self.init(all: all, range: range, now: now)
    }

    /// The part of a full history that a range shows, oldest first.
    init(all: [Point], range: Range, now: Date = Date()) {
        guard let start = range.start(from: now), let first = all.first(where: { $0.date >= start }) else {
            points = range.start(from: now) == nil ? all : []
            return
        }
        var inRange = all.filter { $0.date >= start }
        // the line starts at the left edge with what the wallet was worth before the range began
        if let before = all.last(where: { $0.date < start }), first.date > start {
            inRange.insert(Point(date: start, value: before.value, capital: before.capital, isChange: false), at: 0)
        }
        points = inRange
    }

    /// The value axis: a little room above and below the lines.
    var valueBounds: ClosedRange<Double> {
        let all = points.flatMap { [$0.value, $0.capital] }
        guard let low = all.min(), let high = all.max() else { return 0...1 }
        let pad = max((high - low) * 0.12, high == low ? max(abs(high) * 0.05, 1) : 0)
        return (low - pad)...(high + pad)
    }
}
