import XCTest
@testable import Saku

final class NotificationFilterTests: XCTestCase {
    private func allows(_ title: String, _ sub: String = "", ignore: [String] = [], only: [String] = []) -> Bool {
        NotificationFilter.allows(title: title, subtitle: sub, ignore: ignore, only: only)
    }

    func testEmptyListsAllowEverything() {
        XCTAssertTrue(allows("Transfer berhasil"))
    }

    func testIgnoreMatchesTitleOrSubtitleWithoutCase() {
        XCTAssertFalse(allows("Promo Akhir Tahun", ignore: ["promo"]))
        XCTAssertFalse(allows("BCA mobile", "Cashback hingga 50%", ignore: ["CASHBACK"]))
        XCTAssertTrue(allows("Transfer berhasil", ignore: ["promo"]))
    }

    func testOnlyKeepsMatchesAndIgnoreWins() {
        XCTAssertTrue(allows("Transfer berhasil", only: ["transfer"]))
        XCTAssertFalse(allows("Info saldo", only: ["transfer"]))
        XCTAssertFalse(allows("Transfer promo", ignore: ["promo"], only: ["transfer"]))
    }

    func testRecentTitlesAreNewestFirstDedupedAndCapped() {
        let saved = NotificationFilter.recent
        defer { NotificationFilter.recent = saved }
        NotificationFilter.recent = []
        for i in 0..<12 { NotificationFilter.remember(title: "Judul \(i)") }
        NotificationFilter.remember(title: "judul 5")
        XCTAssertEqual(NotificationFilter.recent.count, NotificationFilter.recentLimit)
        XCTAssertEqual(NotificationFilter.recent.first, "judul 5")
        XCTAssertEqual(NotificationFilter.recent.filter { $0.lowercased() == "judul 5" }.count, 1)
    }
}
