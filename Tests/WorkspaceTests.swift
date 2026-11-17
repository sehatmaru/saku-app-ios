import XCTest
@testable import Saku

final class WorkspaceTests: XCTestCase {
    private func decode(_ json: String) throws -> Workspace {
        try JSONDecoder().decode(Workspace.self, from: Data(json.utf8))
    }

    private let shared = """
    {"id":"6f0f3b9e-8b7e-4b8e-9d5c-1f2a3b4c5d6e","kind":"shared","name":"Rumah","icon":"house","color":"hijau","role":"member",
     "owner_id":"2f0f3b9e-8b7e-4b8e-9d5c-1f2a3b4c5d6e","owner_name":"Ruth","member_count":3,"is_read_only":false,"is_default":false,
     "default_reset":false,"deletion_scheduled_for":null,"payday_day":25}
    """

    func testDecodesAMyspacesRow() throws {
        let w = try decode(shared)
        XCTAssertEqual(w.name, "Rumah")
        XCTAssertEqual(w.memberCount, 3)
        XCTAssertEqual(w.paydayDay, 25)
        XCTAssertFalse(w.isOwner)
        XCTAssertFalse(w.isPersonal)
        XCTAssertEqual(w.displayName, "Rumah")
        XCTAssertNil(w.daysUntilDeletion)
    }

    func testPersonalHasNoIconOrOwnerAndIsNamedByTheApp() throws {
        let w = try decode("""
        {"id":"6f0f3b9e-8b7e-4b8e-9d5c-1f2a3b4c5d6e","kind":"personal","name":"Pribadi","icon":null,"color":null,"role":"owner",
         "owner_id":null,"owner_name":null,"member_count":1,"is_read_only":false,"is_default":true,
         "default_reset":false,"deletion_scheduled_for":null,"payday_day":null}
        """)
        XCTAssertTrue(w.isPersonal)
        XCTAssertTrue(w.isOwner)
        XCTAssertEqual(w.displayName, L("Workspace Pribadi"))
    }

    func testDaysUntilDeletionCountsWholeDays() throws {
        let when = ISO8601DateFormatter().string(from: Date().addingTimeInterval(5 * 86_400 + 3_600))
        let w = try decode(shared.replacingOccurrences(of: "\"deletion_scheduled_for\":null", with: "\"deletion_scheduled_for\":\"\(when)\""))
        XCTAssertEqual(w.daysUntilDeletion, 5)
    }

    func testServerErrorsMapToWhatTheScreensDo() {
        struct E: Error, CustomStringConvertible { let description: String }
        XCTAssertEqual(WorkspaceError(E(description: "PostgrestError(message: \"space_limit\")")), .limit)
        XCTAssertEqual(WorkspaceError(E(description: "guest_not_allowed")), .guest)
        XCTAssertEqual(WorkspaceError(E(description: "timeout")), .other)
    }

    func testUnknownColourFallsBackToTheAppColour() {
        XCTAssertNotNil(WalletIcon.presetColor(named: "hijau"))
        XCTAssertEqual(WalletIcon.presetColors.count, 10)
    }
}
