import XCTest
@testable import Saku

/// Enhancement 3 (SAKU-735): a notification that is already recorded as a running installment or an
/// active recurring bill does not become a draft; it shows as an information row with Batalkan.
/// Scenarios mirror TC 82-97 in Plane.
@MainActor
final class AlreadyRecordedTests: XCTestCase {
    private let calendar = Calendar.current

    /// Card: statement prints on the 20th, like the running-installment tests.
    private let card = Account(id: "card", name: "BCA Visa", type: .credit, icon: nil, isArchived: false, isDefault: false,
                               openingBalance: 0, currentBalance: 6_000_000, creditLimit: 10_000_000, dueDate: "5", statementDay: 20)

    private func makeStore() -> (store: DraftStore, url: URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("already-recorded-\(UUID().uuidString).json")
        return (DraftStore(fileURL: url), url)
    }

    private func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    /// A purchase some months ago paid in equal parts; about Rp829.084 a month for 6 parts of Rp4.974.504.
    private func installmentSetup(monthsAgo: Int = 2, months: Int = 6, amount: Double = 4_974_504)
        -> (plan: CardInstallment, purchase: Transaction, running: RunningInstallment?) {
        let purchaseDate = calendar.date(byAdding: .month, value: -monthsAgo, to: calendar.startOfDay(for: Date()))!
        let purchase = Transaction(id: "tv-\(UUID().uuidString)", accountId: card.id, counterpartyAccountId: nil, categoryId: nil,
                                   amount: amount, type: .expense, description: "iPhone 15", note: nil, date: purchaseDate, delta: nil)
        let plan = CardInstallment(id: "ci-\(UUID().uuidString)", accountId: card.id, transactionId: purchase.id, months: months)
        let running = RunningInstallments.compute(installments: [plan], transactions: [purchase], accounts: [card], periodEnd: Date()).first
        return (plan, purchase, running)
    }

    private func subscription(name: String = "Netflix", amount: Double = 186_000, nextBilling: Date?) -> CardSubscription {
        CardSubscription(id: "sub-\(UUID().uuidString)", accountId: card.id, name: name, amount: amount, frequency: .monthly,
                         nextBillingDate: nextBilling.map(dayString), isActive: true, categoryId: nil, note: nil,
                         createdAt: nil, updatedAt: nil)
    }

    private func postedBill(_ name: String = "Netflix", amount: Double = 186_000, date: Date = Date()) -> Transaction {
        Transaction(id: "tv-\(UUID().uuidString)", accountId: card.id, counterpartyAccountId: nil, categoryId: nil, amount: amount,
                    type: .expense, description: nil, note: "Tagihan berulang: \(name)", date: date, delta: nil,
                    clientReferenceId: "sub_x_\(dayString(date))")
    }

    private func notificationDraft(amount: Double, date: Date, accountId: String? = nil, title: String = "Potongan cicilan") -> Draft {
        Draft(kind: .expense, amount: amount, title: title, accountId: accountId, date: date, source: .notification)
    }

    // MARK: Installments

    /// TC 82: the monthly part matches within Rp2 and 3 days; no draft, an information row instead.
    func testTC82InstallmentPartDoesNotBecomeADraft() {
        let (store, _) = makeStore()
        let setup = installmentSetup()
        let running = setup.running!
        store.seedReferenceData(accounts: [card], recent: [setup.purchase], installments: [setup.plan], subscriptions: [])

        let result = store.addFromNotification([notificationDraft(amount: running.monthly + 1, date: running.billingDates[1], accountId: card.id)],
                                               appName: "BCA")

        XCTAssertEqual(result.added, 0)
        XCTAssertEqual(result.skipped, 1)
        XCTAssertTrue(store.drafts.isEmpty)
        XCTAssertEqual(store.notices.count, 1)
        XCTAssertEqual(store.notices.first?.match, .installment(title: "iPhone 15"))
        XCTAssertEqual(store.notices.first?.draft.sourceName, "BCA")
    }

    /// TC 83: the wallet does not have to be detected (K2).
    func testTC83InstallmentMatchesWithoutWallet() {
        let (store, _) = makeStore()
        let setup = installmentSetup()
        let running = setup.running!
        store.seedReferenceData(accounts: [card], recent: [setup.purchase], installments: [setup.plan], subscriptions: [])

        let result = store.addFromNotification([notificationDraft(amount: running.monthly + 1, date: running.billingDates[1])], appName: "BCA")

        XCTAssertEqual(result.skipped, 1)
        XCTAssertTrue(store.drafts.isEmpty)
    }

    /// TC 84: beyond the Rp2 tolerance it stays a draft (K3).
    func testTC84AmountOutsideToleranceStaysADraft() {
        let (store, _) = makeStore()
        let setup = installmentSetup()
        let running = setup.running!
        store.seedReferenceData(accounts: [card], recent: [setup.purchase], installments: [setup.plan], subscriptions: [])

        let result = store.addFromNotification([notificationDraft(amount: running.monthly + 5, date: running.billingDates[1], accountId: card.id)],
                                               appName: "BCA")

        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.skipped, 0)
        XCTAssertEqual(store.drafts.count, 1)
        XCTAssertTrue(store.notices.isEmpty)
    }

    /// TC 89: a date outside the 3-day window stays a draft (K4).
    func testTC89DateOutsideWindowStaysADraft() {
        let (store, _) = makeStore()
        let setup = installmentSetup()
        let running = setup.running!
        store.seedReferenceData(accounts: [card], recent: [setup.purchase], installments: [setup.plan], subscriptions: [])

        let late = calendar.date(byAdding: .day, value: 5, to: running.billingDates[1])!
        let result = store.addFromNotification([notificationDraft(amount: running.monthly, date: late, accountId: card.id)], appName: "BCA")

        XCTAssertEqual(result.added, 1)
        XCTAssertTrue(store.notices.isEmpty)
    }

    /// TC 90: a plan that is paid off in Saku is not matched (K13).
    func testTC90PaidOffInstallmentStaysADraft() {
        let (store, _) = makeStore()
        // 8 months ago, 6 parts: nothing is still running.
        let setup = installmentSetup(monthsAgo: 8, months: 6)
        XCTAssertNil(setup.running)
        store.seedReferenceData(accounts: [card], recent: [setup.purchase], installments: [setup.plan], subscriptions: [])

        let result = store.addFromNotification([notificationDraft(amount: setup.purchase.amount / 6, date: Date(), accountId: card.id)], appName: "BCA")

        XCTAssertEqual(result.added, 1)
        XCTAssertTrue(store.notices.isEmpty)
    }

    /// TC 88: the amount fits two installments and there is no wallet to tell them apart (K7).
    func testTC88AmbiguousWithoutWalletStaysADraft() {
        let (store, _) = makeStore()
        let first = installmentSetup()
        let second = installmentSetup()
        store.seedReferenceData(accounts: [card], recent: [first.purchase, second.purchase],
                                installments: [first.plan, second.plan], subscriptions: [])

        let amount = first.running!.monthly
        let date = first.running!.billingDates[1]
        let result = store.addFromNotification([notificationDraft(amount: amount, date: date)], appName: "BCA")

        XCTAssertEqual(result.added, 1)
        XCTAssertTrue(store.notices.isEmpty)
    }

    // MARK: Recurring bills

    /// TC 85: the bill already posted its transaction today; the notification still does not become a draft.
    func testTC85PostedRecurringBillIsNotADraft() {
        let (store, _) = makeStore()
        let sub = subscription(nextBilling: calendar.date(byAdding: .month, value: 1, to: Date()))
        store.seedReferenceData(accounts: [card], recent: [postedBill()], installments: [], subscriptions: [sub])

        let result = store.addFromNotification([notificationDraft(amount: 186_000, date: Date(), accountId: card.id, title: "Netflix")],
                                               appName: "BCA")

        XCTAssertEqual(result.skipped, 1)
        XCTAssertTrue(store.drafts.isEmpty)
        XCTAssertEqual(store.notices.first?.match, .bill(name: "Netflix"))
    }

    /// TC 86: the notification arrives before the bill posts; the registered bill matches (K9).
    func testTC86RegisteredBillBeforePostingIsNotADraft() {
        let (store, _) = makeStore()
        let billingDate = calendar.date(byAdding: .day, value: 2, to: Date())!
        let sub = subscription(nextBilling: billingDate)
        store.seedReferenceData(accounts: [card], recent: [], installments: [], subscriptions: [sub])

        let result = store.addFromNotification([notificationDraft(amount: 186_000, date: Date())], appName: "BCA")

        XCTAssertEqual(result.skipped, 1)
        XCTAssertTrue(store.drafts.isEmpty)
    }

    /// TC 87: a different amount stays a draft; nothing is changed on the bill.
    func testTC87DifferentBillAmountStaysADraft() {
        let (store, _) = makeStore()
        let sub = subscription(nextBilling: Date())
        store.seedReferenceData(accounts: [card], recent: [], installments: [], subscriptions: [sub])

        let result = store.addFromNotification([notificationDraft(amount: 200_000, date: Date())], appName: "BCA")

        XCTAssertEqual(result.added, 1)
        XCTAssertTrue(store.notices.isEmpty)
    }

    // MARK: The notice row and Batalkan

    /// TC 91: the information row lives 7 days, then disappears (K10).
    func testTC91NoticeIsKeptForSevenDays() {
        let (store, _) = makeStore()
        let setup = installmentSetup()
        let running = setup.running!
        store.seedReferenceData(accounts: [card], recent: [setup.purchase], installments: [setup.plan], subscriptions: [])
        store.addFromNotification([notificationDraft(amount: running.monthly, date: running.billingDates[1])], appName: "BCA")
        XCTAssertEqual(store.notices.count, 1)

        store.purgeExpired(now: Date().addingTimeInterval(6 * 24 * 3600))
        XCTAssertEqual(store.notices.count, 1, "still shown on day 6")
        store.purgeExpired(now: Date().addingTimeInterval(8 * 24 * 3600))
        XCTAssertTrue(store.notices.isEmpty, "gone after 7 days")
    }

    /// TC 92: Batalkan turns the notification back into a draft.
    func testTC92CancelNoticeMakesADraft() {
        let (store, _) = makeStore()
        let setup = installmentSetup()
        let running = setup.running!
        store.seedReferenceData(accounts: [card], recent: [setup.purchase], installments: [setup.plan], subscriptions: [])
        store.addFromNotification([notificationDraft(amount: running.monthly, date: running.billingDates[1])], appName: "BCA")
        let notice = store.notices.first!

        store.cancelNotice(notice)

        XCTAssertTrue(store.notices.isEmpty)
        XCTAssertEqual(store.drafts.count, 1)
        XCTAssertEqual(store.drafts.first?.amount, running.monthly)
        XCTAssertEqual(store.drafts.first?.source, .notification)
        XCTAssertEqual(store.drafts.first?.sourceName, "BCA")
    }

    // MARK: Reverse order (K6)

    /// TC 94: a waiting draft is skipped when the bill posts; TC 95: a different draft is kept.
    func testTC94And95WaitingDraftsAreSkippedOnlyWhenTheyMatch() {
        let (store, _) = makeStore()
        store.addFromNotification([notificationDraft(amount: 186_000, date: Date(), title: "Netflix"),
                                   notificationDraft(amount: 55_000, date: Date(), title: "Spotify")], appName: "BCA")
        XCTAssertEqual(store.drafts.count, 2)

        store.skipWaitingDrafts(billName: "Netflix", amount: 186_000, accountId: card.id, billingDate: Date())

        XCTAssertEqual(store.drafts.count, 1, "the other draft stays")
        XCTAssertEqual(store.drafts.first?.amount, 55_000)
        XCTAssertEqual(store.notices.count, 1)
        XCTAssertEqual(store.notices.first?.match, .bill(name: "Netflix"))
    }

    /// K6 only touches notification drafts: a typed draft is the user's own words.
    func testTypedDraftIsNeverSkippedByAPostedBill() {
        let (store, _) = makeStore()
        var typed = notificationDraft(amount: 186_000, date: Date(), title: "Netflix")
        typed.source = .typed
        store.add([typed])

        store.skipWaitingDrafts(billName: "Netflix", amount: 186_000, accountId: card.id, billingDate: Date())

        XCTAssertEqual(store.drafts.count, 1)
        XCTAssertTrue(store.notices.isEmpty)
    }

    // MARK: Privacy and the SM8 warning

    /// TC 93: raw notification text, balances and account numbers are never stored.
    func testTC93RawNotificationTextIsNotStored() {
        let (store, url) = makeStore()
        let gopay = Account(id: "gopay", name: "GoPay", type: .ewallet, icon: nil, isArchived: false, isDefault: false,
                            openingBalance: 0, creditLimit: nil, dueDate: nil)
        store.seedReferenceData(accounts: [gopay], recent: [], installments: [], subscriptions: [])
        let body = "Pembayaran Rp25.000 ke Kopi Kenangan berhasil. Saldo GoPay kamu Rp1.234.567. Rek 1234567890"
        let drafts = NotificationParser.parse(app: "GoPay", title: "Pembayaran berhasil", subtitle: "", body: body, context: store.context)
        XCTAssertFalse(drafts.isEmpty)

        store.addFromNotification(drafts, appName: "GoPay")

        let saved = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        XCTAssertFalse(saved.contains("1234567890"), "no account number")
        XCTAssertFalse(saved.contains("Saldo GoPay kamu"), "no raw notification text")
    }

    /// TC 97: the ordinary duplicate check (SM8) still adds "Mirip transaksi lain" to a plain notification.
    func testTC97OrdinaryNotificationKeepsTheSM8Warning() {        let (store, _) = makeStore()
        let gopay = Account(id: "gopay", name: "GoPay", type: .ewallet, icon: nil, isArchived: false, isDefault: false,
                            openingBalance: 0, creditLimit: nil, dueDate: nil)
        let saved = Transaction(id: "tv", accountId: "gopay", counterpartyAccountId: nil, categoryId: nil, amount: 25_000,
                                type: .expense, description: "Kopi Kenangan", note: nil, date: Date(), delta: nil)
        store.seedReferenceData(accounts: [gopay], recent: [saved], installments: [], subscriptions: [])

        let result = store.addFromNotification([notificationDraft(amount: 25_000, date: Date(), accountId: "gopay", title: "Kopi Kenangan")],
                                               appName: "GoPay")

        XCTAssertEqual(result.added, 1)
        XCTAssertNotNil(store.drafts.first?.duplicateNote)
    }

    func testNoticeExpiresWhenTheDayOfTheNotificationIsOver() {
        var draft = Draft()
        draft.date = Date()
        let notice = SkippedNotice(draft: draft, match: .bill(name: "XL Satu"))
        XCTAssertTrue(notice.expiresAt > Date())
        draft.date = calendar.date(byAdding: .day, value: -1, to: Date())!
        XCTAssertTrue(SkippedNotice(draft: draft, match: .bill(name: "XL Satu")).expiresAt <= Date())
    }
}
