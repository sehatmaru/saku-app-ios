import XCTest
@testable import Saku

final class NotificationParserTests: XCTestCase {
    private func account(_ id: String, _ name: String, _ type: Account.AccountType) -> Account {
        Account(id: id, name: name, type: type, icon: nil, isArchived: false, isDefault: false, openingBalance: 0,
                creditLimit: nil, dueDate: nil)
    }

    private var context: SmartParser.Context {
        SmartParser.Context(accounts: [account("gopay", "GoPay", .ewallet), account("bca", "BCA", .bank)],
                            categories: [Saku.Category(id: "kopi", name: "Jajan & Kopi", icon: nil, color: nil, type: .expense, systemKey: nil)])
    }

    func testPaymentUsesTheAppsWallet() {
        let drafts = NotificationParser.parse(app: "GoPay", title: "Pembayaran berhasil", subtitle: "",
                                              body: "Pembayaran Rp25.000 ke Kopi Kenangan berhasil. Saldo GoPay kamu Rp1.234.567", context: context)
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].kind, .expense)
        XCTAssertEqual(drafts[0].amount, 25_000)
        XCTAssertEqual(drafts[0].accountId, "gopay")
        XCTAssertEqual(drafts[0].source, .notification)
        XCTAssertEqual(drafts[0].title, "Kopi Kenangan")
    }

    func testIncomingMoney() {
        let drafts = NotificationParser.parse(app: "BCA", title: "Dana masuk", subtitle: "",
                                              body: "Anda menerima transfer Rp500.000 dari Budi. Rek 1234567890", context: context)
        XCTAssertEqual(drafts.first?.kind, .income)
        XCTAssertEqual(drafts.first?.amount, 500_000)
        XCTAssertEqual(drafts.first?.accountId, "bca")
    }

    func testNoAmountIsIgnored() {
        XCTAssertTrue(NotificationParser.parse(app: "BCA", title: "BCA mobile", subtitle: "", body: "Ada transaksi baru, buka aplikasi", context: context).isEmpty)
    }

    func testBalanceIsNotTakenAsTheAmount() {
        let amount = NotificationParser.firstAmount(in: NotificationParser.sanitize("Saldo Rp9.999.999. Bayar Rp12.500"))
        XCTAssertEqual(amount, 12_500)
    }
}
