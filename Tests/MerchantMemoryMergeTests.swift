import XCTest
@testable import Saku

final class MerchantMemoryMergeTests: XCTestCase {
    private func entry(_ keyword: String, category: String? = "c", uses: Int = 1, at seconds: TimeInterval, deleted: Bool = false) -> MerchantMemory.Entry {
        var e = MerchantMemory.Entry(keyword: keyword, kind: .expense, categoryId: category, accountId: nil, uses: uses,
                                     updatedAt: Date(timeIntervalSince1970: seconds))
        if deleted { e.deletedAt = e.updatedAt }
        return e
    }

    func testRemoteOnlyEntryIsAddedAndNothingIsPushed() {
        let result = MerchantMemory.merge(local: [], tombstones: [], remote: [entry("kopi", at: 10)])
        XCTAssertEqual(result.live.map(\.keyword), ["kopi"])
        XCTAssertTrue(result.toPush.isEmpty)
    }

    func testLocalOnlyEntryIsPushed() {
        let result = MerchantMemory.merge(local: [entry("parkir", at: 10)], tombstones: [], remote: [])
        XCTAssertEqual(result.live.map(\.keyword), ["parkir"])
        XCTAssertEqual(result.toPush.map(\.keyword), ["parkir"])
    }

    func testLatestChangeWinsInBothDirections() {
        let newerLocal = MerchantMemory.merge(local: [entry("kopi", category: "new", at: 20)], tombstones: [], remote: [entry("kopi", category: "old", at: 10)])
        XCTAssertEqual(newerLocal.live.first?.categoryId, "new")
        XCTAssertEqual(newerLocal.toPush.count, 1)

        let newerRemote = MerchantMemory.merge(local: [entry("kopi", category: "old", at: 10)], tombstones: [], remote: [entry("kopi", category: "new", at: 20)])
        XCTAssertEqual(newerRemote.live.first?.categoryId, "new")
        XCTAssertTrue(newerRemote.toPush.isEmpty)
    }

    func testNewerTombstoneRemovesTheEntryEverywhere() {
        let fromServer = MerchantMemory.merge(local: [entry("kopi", at: 10)], tombstones: [], remote: [entry("kopi", at: 20, deleted: true)])
        XCTAssertTrue(fromServer.live.isEmpty)
        XCTAssertEqual(fromServer.tombstones.count, 1)

        let fromDevice = MerchantMemory.merge(local: [], tombstones: [entry("kopi", at: 20, deleted: true)], remote: [entry("kopi", at: 10)])
        XCTAssertTrue(fromDevice.live.isEmpty)
        XCTAssertEqual(fromDevice.toPush.first?.deletedAt != nil, true)
    }

    func testEntryLearnedAfterAForgetComesBack() {
        let result = MerchantMemory.merge(local: [entry("kopi", at: 30)], tombstones: [], remote: [entry("kopi", at: 20, deleted: true)])
        XCTAssertEqual(result.live.map(\.keyword), ["kopi"])
    }

    func testOnlyTheMostUsedFiveHundredStay() {
        let local = (0..<510).map { entry("k\($0)", uses: $0 + 1, at: TimeInterval($0)) }
        let result = MerchantMemory.merge(local: local, tombstones: [], remote: [])
        XCTAssertEqual(result.live.count, MerchantMemory.limit)
        XCTAssertFalse(result.live.contains { $0.keyword == "k0" })
        XCTAssertTrue(result.live.contains { $0.keyword == "k509" })
        XCTAssertEqual(result.tombstones.count, 10)
        XCTAssertEqual(result.toPush.count, 510)
    }
}
