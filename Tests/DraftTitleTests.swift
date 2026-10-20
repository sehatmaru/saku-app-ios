import XCTest
@testable import Saku

/// BUG-38: a name cleared in Konfirmasi transaksi stays empty when the draft is saved;
/// the transaction-kind default must never be filled back in.
final class DraftTitleTests: XCTestCase {
    func testEmptyTitleSavesNothing() {
        var draft = Draft()
        XCTAssertNil(draft.savedTitle)
        draft.title = "   "
        XCTAssertNil(draft.savedTitle, "spaces only count as empty")
    }

    func testTypedTitleIsSavedTrimmed() {
        var draft = Draft()
        draft.title = "  Kopi Kenangan "
        XCTAssertEqual(draft.savedTitle, "Kopi Kenangan")
    }

    func testKindDefaultIsNeverSavedAsTheName() {
        for kind in Draft.Kind.allCases {
            var draft = Draft()
            draft.kind = kind
            XCTAssertNil(draft.savedTitle, "\(kind): a cleared field must not come back as \(draft.kindTitle)")
        }
    }
}
