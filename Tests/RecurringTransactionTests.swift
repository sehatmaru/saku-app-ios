import XCTest
@testable import Saku

final class RecurringTransactionTests: XCTestCase {
    private func txn(ref: String?, note: String?) -> Transaction {
        Transaction(id: "t", accountId: "a", counterpartyAccountId: nil, categoryId: "c", amount: 50_000,
                    type: .expense, description: nil, note: note, date: Date(), delta: nil, clientReferenceId: ref)
    }

    func testAutoPostedBillIsRecurringAndNamed() {
        let t = txn(ref: "sub_abc_2026-10-08", note: "Tagihan berulang: Spotify")
        XCTAssertTrue(t.isRecurring)
        XCTAssertEqual(t.recurringName, "Spotify")
    }

    func testOrdinaryTransactionIsNot() {
        let t = txn(ref: "6F1B-uuid", note: "Tagihan berulang: Spotify")
        XCTAssertFalse(t.isRecurring)
        XCTAssertNil(t.recurringName)
        XCTAssertFalse(txn(ref: nil, note: nil).isRecurring)
    }

    func testRecurringFilterCountsAndResets() {
        var filter = TransactionFilter()
        XCTAssertFalse(filter.hasActiveFilters)
        filter.recurringOnly = true
        XCTAssertTrue(filter.hasActiveFilters)
        XCTAssertEqual(filter.activeFilterCount, 1)
        filter.reset()
        XCTAssertFalse(filter.recurringOnly)
    }
}
