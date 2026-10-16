import XCTest
@testable import Saku

/// TC 45: drafts left for 30 days expire and are removed, and the queue warns beforehand
/// ("N draf akan dihapus dalam 3 hari ...").
@MainActor
final class DraftExpiryTests: XCTestCase {
    private func makeStore() -> DraftStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("draft-expiry-\(UUID().uuidString).json")
        return DraftStore(fileURL: url)
    }

    private func draft(ageInDays: Int, title: String = "Kopi") -> Draft {
        var d = Draft(kind: .expense, amount: 25_000, title: title)
        d.createdAt = Calendar.current.date(byAdding: .day, value: -ageInDays, to: Date())!
        return d
    }

    /// Only the drafts inside their last three days are counted for the banner.
    func testExpiringSoonCountsOnlyTheLastThreeDays() {
        let store = makeStore()
        store.add([draft(ageInDays: 28, title: "Sebentar lagi"), draft(ageInDays: 20, title: "Masih lama")])

        XCTAssertEqual(store.expiringSoon, 1)
    }

    /// A draft past its 30 days is dropped on the next purge.
    func testThirtyDayOldDraftIsPurged() {
        let store = makeStore()
        store.add([draft(ageInDays: 31, title: "Lama")])
        XCTAssertEqual(store.drafts.count, 1, "add() itself does not purge")

        store.purgeExpired()

        XCTAssertTrue(store.drafts.isEmpty)
    }
}
