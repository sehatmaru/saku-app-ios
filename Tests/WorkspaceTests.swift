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
        {"id":"6f0f3b9e-8b7e-4b8e-9d5c-1f2a3b4c5d6e","kind":"personal","name":null,"icon":null,"color":null,"role":"owner",
         "owner_id":null,"owner_name":null,"member_count":1,"is_read_only":false,"is_default":true,
         "default_reset":false,"deletion_scheduled_for":null,"payday_day":null}
        """)
        XCTAssertTrue(w.isPersonal)
        XCTAssertTrue(w.isOwner)
        XCTAssertEqual(w.displayName, L("Workspace Pribadi"))
    }

    func testDaysUntilDeletionRoundsUp() throws {
        let when = ISO8601DateFormatter().string(from: Date().addingTimeInterval(4 * 86_400 + 3_600))
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

final class InviteTests: XCTestCase {
    func testCodeIsNormalizedFromAnyTyping() {
        XCTAssertEqual(InviteCode.normalized("abcd-efgh"), "ABCDEFGH")
        XCTAssertEqual(InviteCode.normalized(" a b c d e f g h "), "ABCDEFGH")
        XCTAssertEqual(InviteCode.normalized("ABCDEFGH9999"), "ABCDEFGH")
        XCTAssertEqual(InviteCode.normalized("é💡ab"), "AB")
    }

    func testCodeIsGroupedInFours() {
        XCTAssertEqual(InviteCode.grouped("abcdefgh"), "ABCD EFGH")
        XCTAssertEqual(InviteCode.grouped("abc"), "ABC")
        XCTAssertEqual(InviteCode.grouped("abcde"), "ABCD E")
        XCTAssertTrue(InviteCode.isComplete("abcd efgh"))
        XCTAssertFalse(InviteCode.isComplete("abcd efg"))
    }

    func testEveryRefusedStatusHasAMessageAndGoodOnesDoNot() {
        for status in [InviteStatus.invalid, .expired, .revoked, .full, .rateLimited, .closed, .alreadyMember] {
            XCTAssertNotNil(status.problem, "\(status)")
        }
        XCTAssertNil(InviteStatus.ok.problem)
        XCTAssertNil(InviteStatus.joined.problem)
    }

    func testDecodesPreviewJoinAndMembers() throws {
        let preview = try JSONDecoder().decode([InvitePreview].self, from: Data("""
        [{"status":"ok","space_id":"6f0f3b9e-8b7e-4b8e-9d5c-1f2a3b4c5d6e","name":"Rumah","icon":"house","color":"hijau","owner_name":"Ruth","member_count":2}]
        """.utf8))
        XCTAssertEqual(preview.first?.status, .ok)
        XCTAssertEqual(preview.first?.memberCount, 2)
        let refused = try JSONDecoder().decode([JoinOutcome].self, from: Data(#"[{"status":"rate_limited","space_id":null}]"#.utf8))
        XCTAssertEqual(refused.first?.status, .rateLimited)
        XCTAssertNil(refused.first?.spaceId)
        let members = try JSONDecoder().decode([WorkspaceMember].self, from: Data("""
        [{"profile_id":"6f0f3b9e-8b7e-4b8e-9d5c-1f2a3b4c5d6e","display_name":"Ruth","avatar_url":null,"role":"owner","joined_at":"2026-11-17T10:00:00+00:00","left_at":null,"is_me":true},
         {"profile_id":"2f0f3b9e-8b7e-4b8e-9d5c-1f2a3b4c5d6e","display_name":null,"avatar_url":null,"role":"member","joined_at":"2026-11-17T10:00:00+00:00","left_at":"2026-11-18T10:00:00+00:00","is_me":false}]
        """.utf8))
        XCTAssertTrue(members[0].isOwner && members[0].isMe && !members[0].isFormer)
        XCTAssertTrue(members[1].isFormer)
        XCTAssertEqual(members[0].initial, "R")
    }

    func testServerErrorsOfStage3() {
        struct E: Error, CustomStringConvertible { let description: String }
        XCTAssertEqual(WorkspaceError(E(description: "space_owner_deleting")), .ownerDeleting)
    }
}

final class DeletionTests: XCTestCase {
    private func space(scheduled: String?, readOnly: Bool = false) throws -> Workspace {
        let json = """
        {"id":"6f0f3b9e-8b7e-4b8e-9d5c-1f2a3b4c5d6e","kind":"shared","name":"Rumah","icon":"house","color":"hijau","role":"owner","owner_id":null,"owner_name":null,
         "member_count":2,"is_read_only":\(readOnly),"is_default":false,"default_reset":false,"deletion_scheduled_for":\(scheduled.map { "\"\($0)\"" } ?? "null"),"payday_day":25}
        """
        return try JSONDecoder().decode(Workspace.self, from: Data(json.utf8))
    }

    func testDaysUntilDeletion() throws {
        XCTAssertNil(try space(scheduled: nil).daysUntilDeletion)
        let in3 = ISO8601DateFormatter().string(from: Date().addingTimeInterval(2 * 86400 + 600))
        XCTAssertEqual(try space(scheduled: in3).daysUntilDeletion, 3)
    }

    func testServerErrorsOfStage6() {
        struct E: Error, CustomStringConvertible { let description: String }
        XCTAssertEqual(WorkspaceError(E(description: "space_owner_must_transfer")), .ownerMustTransfer)
        XCTAssertEqual(WorkspaceError(E(description: "wallet_limit_money")), .walletLimit)
        XCTAssertEqual(WorkspaceError(E(description: "account_card_not_movable")), .notMovable)
        XCTAssertEqual(WorkspaceError(E(description: "space_read_only")), .readOnly)
    }
}

final class AttributionTests: XCTestCase {
    private func tx(_ json: String) throws -> Transaction {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Transaction.self, from: Data(json.utf8))
    }

    func testTransactionReadsRecorderAndEditor() throws {
        let t = try tx("""
        {"id":"t1","primary_account_id":"a","counterparty_account_id":null,"category_id":null,"amount":1000,"transaction_type":"expense",
         "description":null,"note":null,"occurred_at":"2026-11-17T03:00:00+00:00","delta":null,
         "user_id":"6f0f3b9e-8b7e-4b8e-9d5c-1f2a3b4c5d6e","updated_by":"2f0f3b9e-8b7e-4b8e-9d5c-1f2a3b4c5d6e","updated_at":"2026-11-18T03:00:00+00:00"}
        """)
        XCTAssertEqual(t.recorderId, "6f0f3b9e-8b7e-4b8e-9d5c-1f2a3b4c5d6e")
        XCTAssertNotEqual(t.updatedBy, t.recorderId)
        XCTAssertNotNil(Workspace.parseTimestamp(t.updatedAtRaw ?? ""))
    }

    func testRecorderFilterCountsAsActiveAndResets() {
        var f = TransactionFilter()
        XCTAssertFalse(f.hasActiveFilters)
        f.recorderId = "x"
        XCTAssertTrue(f.hasActiveFilters)
        XCTAssertEqual(f.activeFilterCount, 1)
        f.reset()
        XCTAssertNil(f.recorderId)
    }
}
