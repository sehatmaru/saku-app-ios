import XCTest
@testable import Saku

final class SmartParserTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return c
    }()

    /// Thursday 8 Okt 2026, 14:00.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 14))! }

    private func account(_ id: String, _ name: String, _ type: Account.AccountType) -> Account {
        Account(id: id, name: name, type: type, icon: nil, isArchived: false, isDefault: false, openingBalance: 0,
                creditLimit: nil, dueDate: nil)
    }

    private func category(_ id: String, _ name: String, _ type: CategoryType = .expense) -> Saku.Category {
        Category(id: id, name: name, icon: nil, color: nil, type: type, systemKey: nil)
    }

    private var context: SmartParser.Context {
        SmartParser.Context(
            accounts: [account("bca", "BCA", .bank), account("gopay", "GoPay", .ewallet), account("cc", "BCA Visa", .credit),
                       account("bibit", "Bibit", .investment), account("cash", "Tunai", .cash)],
            categories: [category("kopi", "Jajan & Kopi"), category("makan", "Makan Harian"), category("trans", "Transportasi"),
                         category("gaji", "Gaji", .income)],
            now: now, calendar: calendar)
    }

    private func parse(_ text: String) -> [Draft] { SmartParser.parse(text, context: context) }

    func testAmountForms() {
        for (text, value) in [("kopi 25rb", 25_000.0), ("kopi 25 ribu", 25_000), ("kopi 25k", 25_000), ("kopi 25.000", 25_000),
                              ("laptop 2,5jt", 2_500_000), ("laptop 2.5 juta", 2_500_000), ("jajan goceng", 5_000),
                              ("parkir ceban", 10_000), ("makan gocap", 50_000), ("servis cepek", 100_000), ("kopi 25000", 25_000)] {
            XCTAssertEqual(SmartParser.amount(in: text)?.value, value, text)
        }
    }

    func testCoffeeWithWalletAndYesterday() {
        let d = parse("kopi 25rb gopay kemarin")[0]
        XCTAssertEqual(d.kind, .expense)
        XCTAssertEqual(d.amount, 25_000)
        XCTAssertEqual(d.title, "Kopi")
        XCTAssertEqual(d.accountId, "gopay")
        XCTAssertEqual(d.categoryId, "kopi")
        XCTAssertEqual(calendar.startOfDay(for: d.date), calendar.date(from: DateComponents(year: 2026, month: 10, day: 7)))
        XCTAssertTrue(d.isComplete)
    }

    func testTodayByDefaultAndNoWalletIsFlagged() {
        let d = parse("makan siang 40rb")[0]
        XCTAssertEqual(d.date, now)
        XCTAssertNil(d.accountId)
        XCTAssertEqual(d.missing, [.account])
    }

    func testSeveralTransactionsInOneSentence() {
        let drafts = parse("kopi 25rb, parkir 5rb")
        XCTAssertEqual(drafts.map(\.amount), [25_000, 5_000])
        XCTAssertEqual(drafts.map(\.categoryId), ["kopi", "trans"])
    }

    func testTopUpIsATransferNotAnExpense() {
        let d = parse("top up gopay 100rb dari bca")[0]
        XCTAssertEqual(d.kind, .transfer)
        XCTAssertEqual(d.accountId, "bca")
        XCTAssertEqual(d.counterpartyAccountId, "gopay")
    }

    func testCardPayment() {
        let d = parse("bayar kartu kredit bca visa 2jt")[0]
        XCTAssertEqual(d.kind, .cardPayment)
        XCTAssertEqual(d.counterpartyAccountId, "cc")
        XCTAssertEqual(d.amount, 2_000_000)
    }

    func testSavingGoesToTheInvestmentWalletNeverAnExpense() {
        let d = parse("nabung bibit 500rb")[0]
        XCTAssertEqual(d.kind, .transfer)
        XCTAssertEqual(d.counterpartyAccountId, "bibit")
        var none = context
        none.accounts.removeAll { $0.id == "bibit" }
        let manual = SmartParser.parse("nabung bibit 500rb", context: none)[0]
        XCTAssertEqual(manual.kind, .transfer)
        XCTAssertTrue(manual.needsInvestmentWallet)
        XCTAssertFalse(manual.isComplete)
    }

    func testIncome() {
        let d = parse("gaji 8jt bca")[0]
        XCTAssertEqual(d.kind, .income)
        XCTAssertEqual(d.amount, 8_000_000)
        XCTAssertEqual(d.accountId, "bca")
        XCTAssertEqual(d.categoryId, "gaji")
    }

    func testDates() {
        func day(_ text: String) -> Int { calendar.component(.day, from: parse(text)[0].date) }
        XCTAssertEqual(day("kopi 25rb tanggal 3"), 3)
        XCTAssertEqual(day("kopi 25rb senin lalu"), 5)
        XCTAssertEqual(day("kopi 25rb 3 hari lalu"), 5)
    }

    func testEnglish() {
        let d = parse("coffee 25k yesterday gopay")[0]
        XCTAssertEqual(d.amount, 25_000)
        XCTAssertEqual(d.accountId, "gopay")
        XCTAssertEqual(d.categoryId, "kopi")
    }

    func testUnreadableKeepsTheUsersWords() {
        let d = parse("blablabla tidak jelas")[0]
        XCTAssertTrue(d.isUnreadable)
        XCTAssertEqual(d.title, "blablabla tidak jelas")
        XCTAssertNil(d.amount)
    }

    func testLearnedChoiceBeatsKeywords() {
        var learned = context
        learned.memory = [MerchantMemory.Entry(keyword: "kopi", kind: .expense, categoryId: "makan", accountId: "cash")]
        let d = SmartParser.parse("kopi 25rb", context: learned)[0]
        XCTAssertEqual(d.categoryId, "makan")
        XCTAssertEqual(d.accountId, "cash")
    }

    // MARK: Category lists (Perampingan Kategori)

    private func categoryName(_ text: String, in names: [String]) -> String? {
        let categories = names.map { category($0, $0) }
        let ctx = SmartParser.Context(accounts: context.accounts, categories: categories, now: now, calendar: calendar)
        return SmartParser.parse(text, context: ctx).first.flatMap { d in categories.first { $0.id == d.categoryId }?.name }
    }

    func testSlimListSendsSubscriptionsToBillsAndOwnPurchasesToHousehold() {
        let slim = ["Transportasi", "Jajan & Kopi", "Makan Harian", "Belanja & Rumah Tangga", "Tagihan & Langganan",
                    "Kesehatan & Olahraga", "Lain-lain"]
        XCTAssertEqual(categoryName("netflix 54rb gopay", in: slim), "Tagihan & Langganan")
        XCTAssertEqual(categoryName("beli pagar 350rb", in: slim), "Belanja & Rumah Tangga")
        XCTAssertEqual(categoryName("makan di restoran 150rb", in: slim), "Makan Harian")
        XCTAssertEqual(categoryName("arisan 250rb", in: slim), "Lain-lain")
        XCTAssertEqual(categoryName("dokter 200rb", in: slim), "Kesehatan & Olahraga")
        XCTAssertEqual(categoryName("futsal 80rb", in: slim), "Kesehatan & Olahraga")
        XCTAssertEqual(categoryName("nonton bioskop 100rb", in: slim), "Lain-lain")
    }

    func testOldListKeepsItsCategories() {
        let old = ["Belanja & Rumah Tangga", "Hiburan", "Perawatan & Kesehatan", "Olahraga & Kebugaran", "Sosial & Donasi", "Restoran & Mall"]
        XCTAssertEqual(categoryName("netflix 54rb", in: old), "Hiburan")
        XCTAssertEqual(categoryName("pulsa 50rb", in: old), "Belanja & Rumah Tangga")
        XCTAssertEqual(categoryName("dokter 200rb", in: old), "Perawatan & Kesehatan")
        XCTAssertEqual(categoryName("futsal 80rb", in: old), "Olahraga & Kebugaran")
        XCTAssertEqual(categoryName("arisan 250rb", in: old), "Sosial & Donasi")
    }
}
