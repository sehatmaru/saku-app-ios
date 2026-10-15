import XCTest
@testable import Saku

final class AccountDeletionTests: XCTestCase {
    func testPhraseIgnoresCaseAndEdgeSpaces() {
        XCTAssertTrue(AccountDeletion.phraseMatches("hapus akun saya"))
        XCTAssertTrue(AccountDeletion.phraseMatches("  Hapus Akun Saya \n"))
        XCTAssertTrue(AccountDeletion.phraseMatches("DELETE MY ACCOUNT"))
    }

    func testPhraseRejectsAnythingElse() {
        XCTAssertFalse(AccountDeletion.phraseMatches(""))
        XCTAssertFalse(AccountDeletion.phraseMatches("hapus akun"))
        XCTAssertFalse(AccountDeletion.phraseMatches("hapus  akun saya"))
        XCTAssertFalse(AccountDeletion.phraseMatches("hapus akun saya ya"))
    }

    func testParsesPostgresTimestamps() {
        let micro = AccountDeletion.parse("2026-11-14T06:00:00.123456+00:00")
        let plain = AccountDeletion.parse("2026-11-14T06:00:00+00:00")
        XCTAssertNotNil(micro)
        XCTAssertNotNil(plain)
        XCTAssertEqual(micro!.timeIntervalSince(plain!), 0.123, accuracy: 0.01)
        XCTAssertNil(AccountDeletion.parse("bukan tanggal"))
    }

    func testEveryReasonKeyIsOneTheServerAccepts() {
        let accepted: Set<String> = ["tidak_pakai", "pindah_aplikasi", "fitur_kurang", "privasi", "mahal", "lainnya"]
        XCTAssertEqual(Set(AccountDeletion.Reason.allCases.map(\.rawValue)), accepted)
    }
}
