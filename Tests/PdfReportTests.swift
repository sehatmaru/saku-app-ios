import XCTest
@testable import Saku

/// Design "Sheet Pengaturan": "Buat laporan PDF" draws the summary on the device.
final class PdfReportTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private let wallet = Account(id: "bca", name: "BCA", type: .bank, icon: nil, isArchived: false, isDefault: true,
                                 openingBalance: 0, currentBalance: 2_500_000, creditLimit: nil, dueDate: nil)
    private let coffee = Saku.Category(id: "kopi", name: "Makan, Minum", icon: nil, color: nil, type: .expense, systemKey: nil)

    private var transactions: [Transaction] {
        [Transaction(id: "t1", accountId: "bca", counterpartyAccountId: nil, categoryId: "kopi", amount: 25_000,
                     type: .expense, description: nil, note: nil, date: date(2026, 10, 10), delta: nil),
         Transaction(id: "t2", accountId: "bca", counterpartyAccountId: nil, categoryId: nil, amount: 5_000_000,
                     type: .income, description: nil, note: nil, date: date(2026, 10, 1), delta: nil)]
    }

    private var budget: Budget {
        Budget(id: "b1", categoryId: "kopi", name: "Kopi", amount: 500_000, periodUnit: "month",
               periodInterval: 1, startDate: "2026-01-01", endDate: nil, isActive: true,
               spent: 600_000, temporary: nil, baseAmount: nil)
    }

    // MARK: Report model (Fitur 8 US3, design "Laporan Keuangan v3")

    private let interval = DateInterval(start: Date(timeIntervalSince1970: 1_790_000_000),
                                        end: Date(timeIntervalSince1970: 1_792_592_000))
    private var cycle: PaydayCycle { PaydayCycle(day: 25) }

    private func txn(_ id: String, _ type: Transaction.TransactionType, _ amount: Double, category: String? = "kopi") -> Transaction {
        Transaction(id: id, accountId: "bca", counterpartyAccountId: nil, categoryId: category, amount: amount, type: type,
                    description: nil, note: nil, date: interval.start.addingTimeInterval(86_400), delta: nil)
    }

    private func line(_ id: String, spent: Double, amount: Double, source: ResolvedBudgetAmount.Source = .base) -> BudgetHistoryRow {
        BudgetHistoryRow(budgetId: id, categoryId: "kopi", amount: amount, spent: spent, source: source, isDeleted: false, transactions: [])
    }

    private func model(_ txns: [Transaction], accounts: [Account]? = nil, rows: [BudgetHistoryRow] = [], isPrivate: Bool = false) -> ReportModel {
        let period = rows.isEmpty ? nil : BudgetHistoryPeriod(interval: interval, rows: rows, income: 0, expense: 0)
        return ReportModel.make(interval: interval, cycle: cycle, userName: "Rina", transactions: txns, accounts: accounts ?? [wallet],
                                categories: [coffee], period: period, isPrivate: isPrivate)
    }

    func testHeadlineFollowsTheNet() {
        let positive = model([txn("a", .income, 10_000_000), txn("b", .expense, 4_000_000)]).headline.map(\.text).joined()
        XCTAssertTrue(positive.hasPrefix("Net positif +Rp6.000.000"), positive)
        XCTAssertTrue(positive.contains("60%"), "saving rate: net / income")
        let deficit = model([txn("a", .income, 1_000_000), txn("b", .expense, 2_100_000)]).headline.map(\.text).joined()
        XCTAssertEqual(deficit, "Net negatif −Rp1.100.000. Pengeluaran periode ini 210% dari pemasukan. Yuk cari pos yang bisa ditekan.")
        XCTAssertTrue(model([]).headline.map(\.text).joined().hasPrefix("Belum ada"))
    }

    func testTransfersAndCardPaymentsStayOutOfTheFlow() {
        let report = model([txn("a", .income, 100_000), txn("t", .transfer, 900_000), txn("c", .cardPayment, 700_000)])
        XCTAssertEqual(report.income, 100_000); XCTAssertEqual(report.expense, 0)
    }

    func testPrivacyModeHidesAmountsAndWalletsButKeepsSigns() {
        let report = model([txn("a", .income, 10_000_000), txn("b", .expense, 4_000_000)], isPrivate: true)
        let text = report.headline.map(\.text).joined()
        XCTAssertTrue(text.contains("+Rp••••••")); XCTAssertFalse(text.contains("6.000.000"))
        XCTAssertEqual(ReportModel.rupiah(-1_100_000, hidden: true), "−Rp••••••")
        XCTAssertFalse(report.showsWallets, "no wallet names or balances")
        XCTAssertTrue(report.footnote.contains("antar akun"), "footnote must not say 'dompet' either")
        XCTAssertFalse(model([], isPrivate: false).footnote.contains("antar akun"))
    }

    func testMoneyIsWrittenWithoutSpaceAndWithRealMinus() {
        XCTAssertEqual(ReportModel.rupiah(5_160_000), "Rp5.160.000")
        XCTAssertEqual(ReportModel.rupiah(-1_100_000), "−Rp1.100.000")
        XCTAssertEqual(ReportModel.rupiah(5_160_000, sign: true), "+Rp5.160.000")
    }

    func testBudgetsAreSortedHeaviestStatusFirstAndTheProvisionalOneIsMarked() {
        let report = model([txn("a", .expense, 1)], rows: [line("ok", spent: 100, amount: 1_000), line("over", spent: 1_200, amount: 1_000),
                                                           line("near", spent: 900, amount: 1_000, source: .temporary)])
        XCTAssertEqual(report.budgets.map(\.status), [.over, .near, .safe])
        XCTAssertEqual(report.budgets.first { $0.status == .near }?.isProvisional, true)
        XCTAssertEqual(report.totalSpent, 2_200); XCTAssertEqual(report.totalBudget, 3_000)
    }

    func testPageTwoOnlyWhenPageOneHadToCutATable() {
        let few = model([txn("a", .expense, 1)], rows: (1...5).map { line("b\($0)", spent: 1, amount: 10) })
        XCTAssertFalse(few.needsSecondPage); XCTAssertEqual(few.pageCount, 1)
        let many = model([txn("a", .expense, 1)], rows: (1...6).map { line("b\($0)", spent: 1, amount: 10) })
        XCTAssertTrue(many.needsSecondPage); XCTAssertEqual(many.pageCount, 2)
        let wallets = (1...7).map { Account(id: "w\($0)", name: "W\($0)", type: .bank, icon: nil, isArchived: false, isDefault: false,
                                           openingBalance: 1, creditLimit: nil, dueDate: nil) }
        XCTAssertTrue(model([], accounts: wallets).needsSecondPage)
        XCTAssertFalse(model([], accounts: wallets, isPrivate: true).needsSecondPage, "wallets are not shown in privacy mode")
    }

    func testCategoriesKeepFourBiggestAndGroupTheRestAsLainnya() {
        let cats = (1...6).map { Saku.Category(id: "c\($0)", name: "K\($0)", icon: nil, color: nil, type: .expense, systemKey: nil) }
        let txns = (1...6).map { Transaction(id: "t\($0)", accountId: "bca", counterpartyAccountId: nil, categoryId: "c\($0)",
                                              amount: Double($0) * 100, type: .expense, description: nil, note: nil,
                                              date: interval.start.addingTimeInterval(86_400), delta: nil) }
        let report = ReportModel.make(interval: interval, cycle: cycle, userName: "", transactions: txns, accounts: [], categories: cats,
                                      period: nil, isPrivate: false)
        XCTAssertEqual(report.slices.map(\.name), ["K6", "K5", "K4", "K3", "Lainnya"])
        XCTAssertEqual(report.slices.last?.amount, 300)
        XCTAssertEqual(report.allSlices.count, 6)
        XCTAssertTrue(report.needsSecondPage, "more than 5 categories: the rest are listed on page 2")
    }

    func testFileNameCarriesThePeriod() {
        XCTAssertTrue(model([]).fileName.hasPrefix("saku-laporan-20"))
        XCTAssertTrue(model([]).fileName.hasSuffix(".pdf"))
        XCTAssertTrue(model([]).fileName.contains("_"))
    }

    // MARK: Drawing

    @MainActor
    private func pageCount(_ data: Data) -> Int {
        guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider) else { return 0 }
        return document.numberOfPages
    }

    @MainActor
    func testReportIsAnA4PdfOfOnePage() throws {
        let data = PdfReport.data(model([txn("a", .income, 5_000_000), txn("b", .expense, 25_000)], rows: [line("b1", spent: 600_000, amount: 500_000)]))
        XCTAssertTrue(String(decoding: data.prefix(5), as: UTF8.self).hasPrefix("%PDF"))
        XCTAssertEqual(pageCount(data), 1)
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let box = try XCTUnwrap(CGPDFDocument(provider)?.page(at: 1)?.getBoxRect(.mediaBox))
        XCTAssertEqual(box.width, 595, accuracy: 1); XCTAssertEqual(box.height, 842, accuracy: 1)
    }

    @MainActor
    func testLongTablesAddASecondPageAndEmptyDataStillMakesAReport() {
        XCTAssertEqual(pageCount(PdfReport.data(model([txn("a", .expense, 1)], rows: (1...8).map { line("b\($0)", spent: 1, amount: 10) }))), 2)
        XCTAssertEqual(pageCount(PdfReport.data(model([], accounts: []))), 1)
        XCTAssertEqual(pageCount(PdfReport.data(model([txn("a", .income, 1), txn("b", .expense, 2)], isPrivate: true))), 1)
    }

    @MainActor
    func testWritePlacesTheFileInTemporaryFolderWithThePeriodInItsName() throws {
        let report = model([txn("a", .expense, 25_000)])
        let url = try XCTUnwrap(PdfReport.write(report))
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(url.lastPathComponent, report.fileName)
    }

    /// Fitur 8 US4: the free preview shows these numbers, so they must follow the picked period.
    func testSummaryTotalsAndTopCategoriesFollowThePeriod() {
        let oct = DateInterval(start: date(2026, 9, 25), end: date(2026, 10, 25))
        let all = PdfReport.summary(transactions: transactions, categories: [coffee], intervals: nil)
        XCTAssertEqual(all.income, 5_000_000); XCTAssertEqual(all.expense, 25_000)
        XCTAssertEqual(all.topCategories.first?.0, "Makan, Minum")
        let none = PdfReport.summary(transactions: transactions, categories: [coffee],
                                     intervals: [DateInterval(start: date(2025, 1, 1), end: date(2025, 2, 1))])
        XCTAssertEqual(none.income, 0); XCTAssertTrue(none.topCategories.isEmpty)
        XCTAssertEqual(PdfReport.summary(transactions: transactions, categories: [coffee], intervals: [oct]).expense, 25_000)
    }
}
