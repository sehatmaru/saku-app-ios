import Foundation

/// Builds the CSV files for Profil › Ekspor data (Fitur 8, US1 & US2). Pure and read only:
/// nothing is written back, and every file is made on the device.
enum CsvExport {
    /// Comma for Google Sheets; semicolon for Excel with Indonesian settings (US1).
    enum Delimiter: String, CaseIterable {
        case comma = ","
        case semicolon = ";"
    }

    /// UTF-8 with BOM, so spreadsheets read the text right away (US1).
    static let utf8BOM = "\u{FEFF}"

    // MARK: Files

    /// Every transaction in `interval` (nil = everything), newest first.
    static func transactions(_ transactions: [Transaction], accounts: [Account], categories: [Category],
                             interval: DateInterval? = nil, delimiter: Delimiter) -> String {
        let wallets = Dictionary(accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let names = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let rows = transactions
            .filter { txn in
                guard let interval else { return true }
                return txn.date >= interval.start && txn.date < interval.end
            }
            .newestFirst()
            .map { txn in
                [date(txn.date), typeLabel(txn.type),
                 text(txn.categoryId.flatMap { names[$0] } ?? ""),
                 text(wallets[txn.accountId] ?? ""),
                 text(txn.counterpartyAccountId.flatMap { wallets[$0] } ?? ""),
                 amount(txn.amount), text(txn.displayNote ?? "")]
            }
        return file([L("Tanggal"), L("Jenis"), L("Kategori"), L("Dompet"), L("Dompet tujuan"), L("Nominal"), L("Catatan")],
                    rows, delimiter)
    }

    /// Name, type, current balance and opening balance (US2).
    static func wallets(_ accounts: [Account], delimiter: Delimiter) -> String {
        let rows = accounts.map { [text($0.name), walletTypeLabel($0.type), amount($0.balance), amount($0.openingBalance)] }
        return file([L("Nama"), L("Jenis"), L("Saldo Saat Ini"), L("Saldo Awal")], rows, delimiter)
    }

    /// Category, amount, period and spent (US2).
    static func budgets(_ budgets: [Budget], categories: [Category], delimiter: Delimiter) -> String {
        let names = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let rows = budgets.map { budget in
            [text(names[budget.categoryId] ?? budget.name), amount(budget.amount), period(budget), amount(budget.spent)]
        }
        return file([L("Kategori"), L("Nominal"), L("Periode"), L("Terpakai")], rows, delimiter)
    }

    // MARK: Pieces

    /// Header and rows joined with the chosen separator, CRLF and a BOM.
    static func file(_ header: [String], _ rows: [[String]], _ delimiter: Delimiter) -> String {
        let lines = ([header] + rows).map { row in row.map { field($0, delimiter) }.joined(separator: delimiter.rawValue) }
        return utf8BOM + lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Quotes a value only when it would break the row (separator, quote or line break inside).
    static func field(_ value: String, _ delimiter: Delimiter) -> String {
        guard value.contains(delimiter.rawValue) || value.contains("\"") || value.contains("\n") || value.contains("\r") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Free text that starts with = + - @ would run as a formula in Excel and Sheets; a leading apostrophe keeps it text.
    static func text(_ value: String) -> String {
        guard let first = value.first, "=+-@\t".contains(first) else { return value }
        return "'" + value
    }

    /// Plain number: no thousands separators, a dot for decimals, no trailing zeros (US1).
    static func amount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSNumber) ?? "\(value)"
    }

    /// yyyy-MM-dd, the one date format spreadsheets understand (US1).
    static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// The app's own words, so the file matches what is on screen (TC 46: jenis always filled).
    static func typeLabel(_ type: Transaction.TransactionType) -> String {
        switch type {
        case .expense: L("Pengeluaran")
        case .income: L("Pemasukan")
        case .transfer: L("Transfer")
        case .cardPayment: L("Bayar kartu")
        case .adjustment: L("Penyesuaian")
        }
    }

    static func walletTypeLabel(_ type: Account.AccountType) -> String {
        switch type {
        case .bank: L("Bank")
        case .ewallet: L("E-Wallet")
        case .cash: L("Cash")
        case .investment: L("Investasi")
        case .credit: L("Kartu kredit")
        }
    }

    /// "2026-09-25 – 2026-10-24": the budget's period in force now.
    static func period(_ budget: Budget, now: Date = Date(), calendar: Calendar = .current) -> String {
        let start: Date
        let end: Date
        switch budget.periodUnit {
        case "month":
            let period = PaydayCycle.current.period(containing: now, calendar: calendar)
            start = period.start
            end = calendar.date(byAdding: .day, value: -1, to: period.end) ?? period.end
        case "week":
            let week = calendar.dateInterval(of: .weekOfYear, for: now)
            start = week?.start ?? now
            end = week.map { calendar.date(byAdding: .day, value: -1, to: $0.end) ?? now } ?? now
        default:
            start = ISO8601DateFormatter().date(from: budget.startDate) ?? now
            end = budget.endDate.flatMap { ISO8601DateFormatter().date(from: $0) } ?? start
        }
        return date(start) + " – " + date(end)
    }
}
