import XCTest
@testable import Saku

/// Fitur 2 (Referral): what the app does with the server's answers (TC 26-36).
final class ReferralTests: XCTestCase {
    private let json = """
    {"code":"K7M2QX","monthly_limit":4,"per_friend":5,"this_month":2,"bonus":10,
     "friends":[
      {"id":"1","name":"Dimas","status":"done","joined_at":"2026-10-03T08:00:00.123456+00:00","first_transaction_at":"2026-10-14T09:30:00+00:00","counts":true},
      {"id":"2","name":null,"status":"done","joined_at":"2026-10-04T08:00:00+00:00","first_transaction_at":"2026-10-15T09:30:00+00:00","counts":false},
      {"id":"3","name":null,"status":"waiting","joined_at":"2026-10-20T08:00:00+00:00","first_transaction_at":null,"counts":false}]}
    """

    func testSummaryReadsCodeProgressAndFriends() throws {
        let summary = try ReferralSummary.decode(Data(json.utf8))
        XCTAssertEqual(summary.code, "K7M2QX")
        XCTAssertEqual(summary.thisMonth, 2); XCTAssertEqual(summary.reward, 10)
        XCTAssertEqual(summary.friends.count, 3); XCTAssertEqual(summary.waiting, 1)
        XCTAssertEqual(summary.friends[0].name, "Dimas")
        XCTAssertEqual(summary.friends[1].name, L("Teman"), "a name nobody allowed stays hidden")
        XCTAssertNil(summary.friends[2].joined, "still waiting for the first transaction")
        XCTAssertFalse(summary.friends[1].counts, "over the month's cap: listed, adds nothing")
        XCTAssertFalse(summary.isMaxed)
    }

    func testInviteMessageCarriesTheCodeInTheLink() throws {
        let summary = try ReferralSummary.decode(Data(json.utf8))
        XCTAssertTrue(summary.inviteLink.hasSuffix("/K7M2QX"))
        XCTAssertTrue(summary.inviteLink.hasPrefix(ReferralSummary.inviteLinkBase))
    }

    func testAGuestHasNoSummary() {
        XCTAssertThrowsError(try ReferralSummary.decode(Data(#"{"code":null,"this_month":0,"bonus":0,"friends":[]}"#.utf8)))
    }

    func testTheRewardNoticeAnnouncesOnlyNewFriendsOnce() {
        // the very first look only remembers
        var step = ReferralSummary.rewardDelta(thisMonth: 2, monthKey: "2026-10", stored: nil)
        XCTAssertEqual(step.newFriends, 0); XCTAssertEqual(step.stored, "2026-10:2")
        // a friend's first transaction later in the month
        step = ReferralSummary.rewardDelta(thisMonth: 3, monthKey: "2026-10", stored: step.stored)
        XCTAssertEqual(step.newFriends, 1)
        // looking again does not announce it again
        step = ReferralSummary.rewardDelta(thisMonth: 3, monthKey: "2026-10", stored: step.stored)
        XCTAssertEqual(step.newFriends, 0)
        // a new month starts from zero: what arrived before the first look counts as new
        step = ReferralSummary.rewardDelta(thisMonth: 1, monthKey: "2026-11", stored: step.stored)
        XCTAssertEqual(step.newFriends, 1); XCTAssertEqual(step.stored, "2026-11:1")
    }

    func testRefusedCodesGetPlainMessages() {
        struct Fake: Error, CustomStringConvertible { let description: String }
        for (code, expected) in [("referral_invalid_code", "tidak ditemukan"), ("referral_own_code", "sendiri"),
                                 ("referral_already_used", "satu kode"), ("referral_too_late", "akun baru"), ("referral_guest", "tamu")] {
            XCTAssertTrue(ReferralFailure.message(for: Fake(description: "PostgrestError(message: \(code))")).contains(expected), code)
        }
        XCTAssertTrue(ReferralFailure.message(for: Fake(description: "offline")).contains("koneksi"))
    }
}
