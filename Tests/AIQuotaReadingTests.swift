import XCTest
@testable import Saku

final class AIQuotaReadingTests: XCTestCase {
    private func decode(_ json: String) throws -> AIQuotaReading {
        try JSONDecoder().decode(AIQuotaReading.self, from: Data(json.utf8))
    }

    func testFreeAccountReadsLeftAndTotal() throws {
        let q = try decode(#"{"is_plus":false,"base":50,"referral_bonus":20,"total":70,"used":32,"left":38}"#)
        XCTAssertEqual(q.left, 38)
        XCTAssertEqual(q.total, 70)
        XCTAssertFalse(q.isOut)
    }

    func testUsedUpIsOut() throws {
        let q = try decode(#"{"is_plus":false,"base":50,"referral_bonus":0,"total":50,"used":50,"left":0}"#)
        XCTAssertTrue(q.isOut)
    }

    func testPlusIsUnlimited() throws {
        let q = try decode(#"{"is_plus":true,"base":50,"referral_bonus":0,"total":null,"used":3,"left":null}"#)
        XCTAssertNil(q.left)
        XCTAssertFalse(q.isOut)
    }
}
