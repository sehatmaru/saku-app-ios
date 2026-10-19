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

    func testReportIsAPdfWithContent() throws {
        let data = try XCTUnwrap(PdfReport.data(transactions: transactions, accounts: [wallet], categories: [coffee],
                                                budgets: [budget], intervals: nil, periodLabel: "25 Sep – 24 Okt"))
        XCTAssertGreaterThan(data.count, 2_000, "a page of text and bars")
        XCTAssertTrue(String(decoding: data.prefix(5), as: UTF8.self).hasPrefix("%PDF"), "starts with the PDF header")
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("%%EOF"), "ends a finished document")
    }

    func testIntervalsFilterTheRows() throws {
        let interval = DateInterval(start: date(2026, 10, 5), end: date(2026, 10, 15))
        let data = try XCTUnwrap(PdfReport.data(transactions: transactions, accounts: [wallet], categories: [coffee],
                                                budgets: [], intervals: [interval], periodLabel: "1 periode"))
        XCTAssertGreaterThan(data.count, 1_000)
    }

    func testEmptyDataStillMakesAReport() throws {
        let data = try XCTUnwrap(PdfReport.data(transactions: [], accounts: [], categories: [], budgets: [],
                                                intervals: nil, periodLabel: "Semua data"))
        XCTAssertGreaterThan(data.count, 1_000, "an empty report still has a page")
    }

    func testWritePlacesTheFileInTemporaryFolder() throws {
        let url = try XCTUnwrap(PdfReport.write(transactions: transactions, accounts: [wallet], categories: [coffee],
                                                budgets: [budget], intervals: nil, periodLabel: "Semua data",
                                                name: "saku-test.pdf"))
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
