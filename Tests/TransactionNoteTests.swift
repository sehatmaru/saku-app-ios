import XCTest
@testable import Saku

final class TransactionNoteTests: XCTestCase {
    private func tx(description: String?, note: String?) -> Transaction {
        Transaction(id: "t", accountId: "a", counterpartyAccountId: nil, categoryId: "c", amount: 50_000,
                    type: .expense, description: description, note: note, date: Date(), delta: nil)
    }

    func testCatatanTypedByTheUserIsTheDisplayedNote() {
        // The form saves "Catatan" as `description`; `note` is only set by the system.
        XCTAssertEqual(tx(description: "Netflix", note: nil).displayNote, "Netflix")
        XCTAssertEqual(tx(description: "Netflix", note: "Tagihan berulang: X").displayNote, "Netflix")
        XCTAssertEqual(tx(description: "  ", note: "Penyesuaian").displayNote, "Penyesuaian")
        XCTAssertNil(tx(description: nil, note: nil).displayNote)
    }

    func testSearchMatchesCatatanNoteOrCategoryName() {
        let netflix = tx(description: "Netflix", note: nil)
        XCTAssertTrue(netflix.matches(search: "netflix", categoryName: "Subscription"))   // catatan (description)
        XCTAssertTrue(netflix.matches(search: "subscr", categoryName: "Subscription"))    // category name
        XCTAssertTrue(tx(description: nil, note: "Tagihan berulang: Spotify").matches(search: "spotify", categoryName: nil)) // note
        XCTAssertFalse(netflix.matches(search: "bensin", categoryName: "Subscription"))
        XCTAssertTrue(netflix.matches(search: "  ", categoryName: nil)) // blank query shows everything
    }
}
