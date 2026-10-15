import XCTest
@testable import Saku

final class ImageParserTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return c
    }()

    private func account(_ id: String, _ name: String, _ type: Account.AccountType) -> Account {
        Account(id: id, name: name, type: type, icon: nil, isArchived: false, isDefault: false, openingBalance: 0, creditLimit: nil, dueDate: nil)
    }

    private var context: SmartParser.Context {
        SmartParser.Context(accounts: [account("gopay", "GoPay", .ewallet), account("bca", "BCA", .bank)],
                            categories: [Category(id: "kopi", name: "Jajan & Kopi", icon: nil, color: nil, type: .expense, systemKey: nil)],
                            now: calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 14))!, calendar: calendar)
    }

    func testPaymentProofIsOneDraft() {
        let r = ImageParser.parse(lines: ["Pembayaran berhasil", "GoPay", "Kopi Kenangan", "14 Okt 2026", "Total  Rp 25.000", "Saldo GoPay Rp 500.000"], context: context)
        XCTAssertEqual(r.drafts.count, 1)
        XCTAssertEqual(r.drafts[0].amount, 25_000)
        XCTAssertEqual(r.drafts[0].accountId, "gopay")
        XCTAssertEqual(r.drafts[0].source, .photo)
        XCTAssertNil(r.drafts[0].note)
    }

    func testReceiptTakesTotalNotSubtotalOrTax() {
        let r = ImageParser.parse(lines: ["INDOMARET", "12/10/2026", "Subtotal 90.000", "PPN 9.900", "Total 99.900", "Tunai 100.000"], context: context)
        XCTAssertEqual(r.drafts.first?.amount, 99_900)
        XCTAssertEqual(r.drafts.first?.title, "Indomaret")
    }

    func testMissingDateUsesTodayAndIsMarked() {
        let r = ImageParser.parse(lines: ["Warung Bu Ani", "Total Rp 30.000"], context: context)
        XCTAssertEqual(r.drafts.first?.date, context.now)
        XCTAssertNotNil(r.drafts.first?.note)
    }

    func testHistoryBecomesOneDraftPerRowAndCapsAtTwenty() {
        var lines = ["Mutasi rekening BCA"]
        for i in 1...22 { lines += ["\(i % 28 + 1)/10/2026", "TRX \(i)", "-\(i + 10).000"] }
        let r = ImageParser.parse(lines: lines, context: context)
        XCTAssertEqual(r.drafts.count, 20)
        XCTAssertTrue(r.truncated)
        XCTAssertEqual(r.drafts[0].accountId, "bca")
    }

    func testNothingReadableGivesNoDraft() {
        XCTAssertTrue(ImageParser.parse(lines: ["abc", "xyz"], context: context).drafts.isEmpty)
        XCTAssertTrue(ImageParser.parse(lines: [], context: context).drafts.isEmpty)
    }
}
