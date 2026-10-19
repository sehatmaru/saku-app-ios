import XCTest
@testable import Saku

/// Fitur 8, free part (US1 & US2): the CSV files (TC 46-50).
final class CsvExportTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private let wallet = Account(id: "bca", name: "BCA", type: .bank, icon: nil, isArchived: false, isDefault: true,
                                 openingBalance: 1_000_000, currentBalance: 2_500_000, creditLimit: nil, dueDate: nil)
    private let card = Account(id: "card", name: "BCA Visa", type: .credit, icon: nil, isArchived: false, isDefault: false,
                               openingBalance: 0, currentBalance: 2_500_000, creditLimit: 10_000_000, dueDate: "5", statementDay: 20)
    private let coffee = Saku.Category(id: "kopi", name: "Makan, Minum", icon: nil, color: nil, type: .expense, systemKey: nil)

    private func txn(_ id: String, type: Transaction.TransactionType = .expense, amount: Double = 25_000, date: Date,
                     account: String = "bca", counterparty: String? = nil, categoryId: String? = "kopi",
                     description: String? = nil, note: String? = nil) -> Transaction {
        Transaction(id: id, accountId: account, counterpartyAccountId: counterparty, categoryId: categoryId, amount: amount,
                    type: type, description: description, note: note, date: date, delta: nil)
    }

    private var transactions: [Transaction] {
        [
            txn("in-range", date: date(2026, 10, 10), description: "Kopi Kenangan"),
            txn("before", date: date(2026, 9, 1)),
            txn("after", date: date(2026, 10, 25)),
        ]
    }

    /// TC 46: a payday period with the comma, like Google Sheets reads it.
    func testTC46PaydayPeriodWithCommaReadsCorrectly() {
        let interval = DateInterval(start: date(2026, 9, 25, 0), end: date(2026, 10, 25, 0))
        let csv = CsvExport.transactions(transactions, accounts: [wallet], categories: [coffee],
                                         interval: interval, delimiter: .comma)

        XCTAssertTrue(csv.hasPrefix(CsvExport.utf8BOM), "UTF-8 with BOM")
        let lines = csv.dropFirst().split(separator: "\r\n", omittingEmptySubsequences: true).map(String.init)
        XCTAssertEqual(lines.count, 2, "header + the one transaction in range")
        XCTAssertEqual(lines[0], "Tanggal,Jenis,Kategori,Dompet,Dompet tujuan,Nominal,Catatan")
        XCTAssertTrue(lines[1].hasPrefix("2026-10-10,Pengeluaran,\"Makan, Minum\",BCA,,"), "date yyyy-MM-dd, jenis filled, comma inside a value quoted")
        XCTAssertTrue(lines[1].contains(",25000,"), "plain amount without thousands separators")
        XCTAssertTrue(lines[1].hasSuffix(",Kopi Kenangan"))
    }

    /// TC 47: the semicolon separates the columns for Excel with Indonesian settings.
    func testTC47SemicolonSplitsColumns() {
        let csv = CsvExport.transactions(transactions, accounts: [wallet], categories: [coffee], delimiter: .semicolon)
        let lines = csv.dropFirst().split(separator: "\r\n", omittingEmptySubsequences: true).map(String.init)

        XCTAssertEqual(lines[0], "Tanggal;Jenis;Kategori;Dompet;Dompet tujuan;Nominal;Catatan")
        XCTAssertEqual(lines[0].split(separator: ";", omittingEmptySubsequences: false).count, 7)
        XCTAssertEqual(lines[1].split(separator: ";", omittingEmptySubsequences: false).count, 7, "every row splits into 7 columns")
        XCTAssertTrue(lines[1].contains("Makan, Minum"), "a comma is not special in semicolon mode, so the name stays plain")
    }

    /// TC 48: a free date range keeps only what is inside it; nil keeps everything.
    func testTC48RangeAndAllData() {
        let interval = DateInterval(start: date(2026, 10, 1, 0), end: date(2026, 10, 15, 0))
        let ranged = CsvExport.transactions(transactions, accounts: [wallet], categories: [coffee],
                                            interval: interval, delimiter: .comma)
        let rangedLines = ranged.split(separator: "\r\n").count - 1
        XCTAssertEqual(rangedLines, 1, "only the 10 Oct transaction")

        let all = CsvExport.transactions(transactions, accounts: [wallet], categories: [coffee], delimiter: .comma)
        let allLines = all.split(separator: "\r\n").count - 1
        XCTAssertEqual(allLines, 3, "all data")

        let startIncluded = DateInterval(start: date(2026, 10, 10, 12), end: date(2026, 10, 11, 0))
        let included = CsvExport.transactions(transactions, accounts: [wallet], categories: [coffee],
                                              interval: startIncluded, delimiter: .comma)
        XCTAssertEqual(included.split(separator: "\r\n").count - 1, 1, "the start of the range is included")
    }

    /// TC 49: name, type, current balance and opening balance match the app.
    func testTC49WalletCsv() {
        let csv = CsvExport.wallets([wallet, card], delimiter: .comma)
        let lines = csv.dropFirst().split(separator: "\r\n", omittingEmptySubsequences: true).map(String.init)

        XCTAssertEqual(lines[0], "Nama,Jenis,Saldo Saat Ini,Saldo Awal")
        XCTAssertEqual(lines[1], "BCA,Bank,2500000,1000000")
        XCTAssertEqual(lines[2], "BCA Visa,Kartu kredit,2500000,0")
    }

    /// TC 50: category, amount, period and spent match the app.
    func testTC50BudgetCsv() {
        let budget = Budget(id: "b1", categoryId: "kopi", name: "Kopi", amount: 500_000, periodUnit: "month",
                            periodInterval: 1, startDate: "2026-01-01", endDate: nil, isActive: true,
                            spent: 123_456, temporary: nil, baseAmount: nil)
        let csv = CsvExport.budgets([budget], categories: [coffee], delimiter: .comma)
        let lines = csv.dropFirst().split(separator: "\r\n", omittingEmptySubsequences: true).map(String.init)

        XCTAssertEqual(lines[0], "Kategori,Nominal,Periode,Terpakai")
        XCTAssertTrue(lines[1].hasPrefix("\"Makan, Minum\",500000,"), "the category name is quoted because of its comma")
        XCTAssertTrue(lines[1].hasSuffix(",123456"), "spent is plain")
        let period = String(lines[1].dropFirst("\"Makan, Minum\",500000,".count).dropLast(",123456".count))
        XCTAssertTrue(period.range(of: #"^\d{4}-\d{2}-\d{2} – \d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
                      "period start – end, both yyyy-MM-dd")
    }

    /// US1: transfers carry both wallets; adjustments still have a type.
    func testTransferAndAdjustmentColumns() {
        let transfer = txn("t1", type: .transfer, amount: 100_000, date: date(2026, 10, 5), account: "bca", counterparty: "card", categoryId: nil)
        let adjustment = txn("t2", type: .adjustment, amount: 5_000, date: date(2026, 10, 6), categoryId: nil)
        let csv = CsvExport.transactions([transfer, adjustment], accounts: [wallet, card], categories: [], delimiter: .comma)
        let lines = csv.dropFirst().split(separator: "\r\n", omittingEmptySubsequences: true).map(String.init)

        // BOM dropped by dropFirst; lines[0] is the header, then newest first (adjustment Oct 6, transfer Oct 5)
        XCTAssertTrue(lines[1].contains(",Penyesuaian,"), "jenis is never empty — row: \(lines[1])")
        XCTAssertTrue(lines[2].contains(",Transfer,,BCA,BCA Visa,"), "source and destination wallets — row: \(lines[2])")
    }

    func testAmountsArePlainNumbers() {
        XCTAssertEqual(CsvExport.amount(25_000), "25000")
        XCTAssertEqual(CsvExport.amount(1_234.5), "1234.5")
        XCTAssertEqual(CsvExport.amount(0), "0")
        XCTAssertEqual(CsvExport.date(date(2026, 10, 9)), "2026-10-09")
    }

    func testQuotingEscapesQuotesAndLineBreaks() {
        XCTAssertEqual(CsvExport.field("a,b", .comma), "\"a,b\"")
        XCTAssertEqual(CsvExport.field("a\"b", .comma), "\"a\"\"b\"")
        XCTAssertEqual(CsvExport.field("a\nb", .comma), "\"a\nb\"")
        XCTAssertEqual(CsvExport.field("a,b", .semicolon), "a,b")
    }

    /// A note that starts with a formula character stays text in a spreadsheet.
    func testFormulaCharactersAreNeutralised() {
        XCTAssertEqual(CsvExport.text("=SUM(A1)"), "'=SUM(A1)")
        XCTAssertEqual(CsvExport.text("-diskon"), "'-diskon")
        XCTAssertEqual(CsvExport.text("Kopi"), "Kopi")
        let csv = CsvExport.wallets([Account(id: "w", name: "@dompet", type: .cash, icon: nil, isArchived: false, isDefault: false, openingBalance: 0, currentBalance: -5, creditLimit: nil, dueDate: nil)], delimiter: .comma)
        XCTAssertTrue(csv.contains("'@dompet,Cash,-5,0"), "amounts keep their minus sign")
    }

    /// Ekspor data: several periods picked by hand are all exported, nothing outside them.
    func testSeveralPeriodsKeepOnlyTransactionsInsideThem() {
        let sept = DateInterval(start: date(2026, 8, 25, 0), end: date(2026, 9, 25, 0))
        let oct = DateInterval(start: date(2026, 9, 25, 0), end: date(2026, 10, 25, 0))
        let csv = CsvExport.transactions(transactions, accounts: [wallet], categories: [coffee],
                                         intervals: [sept, oct], delimiter: .comma)
        XCTAssertEqual(csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }.count, 3, "header plus the two inside the periods")
    }
}
