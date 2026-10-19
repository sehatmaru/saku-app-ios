import XCTest

/// SAKU-72 (User Story 3 of Enhancement 1): Hapus akun offers to export data first,
/// before the confirmation field, and the export flow returns to the delete screen.
final class ExportBeforeDeleteTests: XCTestCase {
    @MainActor
    private func walkToConfirmation(_ app: XCUIApplication) {
        let editRow = app.buttons["Ubah"].firstMatch
        XCTAssertTrue(editRow.waitForExistence(timeout: 8), "row Ubah")
        editRow.tap()

        // Hapus akun moved to the Ubah Profil screen (design "Profil Revamp")
        let deleteRow = app.buttons["Hapus akun"].firstMatch
        if !deleteRow.waitForExistence(timeout: 4) { app.swipeUp() }
        XCTAssertTrue(deleteRow.waitForExistence(timeout: 6), "row Hapus akun")
        if !deleteRow.isHittable { app.swipeUp() }
        deleteRow.tap()

        let understand = app.buttons["Saya mengerti, lanjutkan"]
        XCTAssertTrue(understand.waitForExistence(timeout: 6), "step 1")
        understand.tap()
        let skip = app.buttons["Lewati"]
        XCTAssertTrue(skip.waitForExistence(timeout: 6), "step 2")
        skip.tap()
    }

    /// TC 32 / TC 33 / TC 34: offer before the field, opens the existing export page, back returns.
    /// Skipped in guest mode: Hapus akun is only offered to signed-in accounts.
    @MainActor
    func testExportOfferShowsBeforeConfirmationAndReturns() throws {
        let app = XCUIApplication()
        app.launch()
        let profil = app.tabBars.buttons["Profil"]
        XCTAssertTrue(profil.waitForExistence(timeout: 25), "tab bar at launch")
        profil.tap()
        usleep(900_000)
        if !profil.isSelected { profil.tap() }

        try XCTSkipIf(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Saku versi")).firstMatch.exists,
                      "guest account: Hapus akun is not offered")

        walkToConfirmation(app)

        let offer = app.buttons["Ekspor data dulu"]
        let field = app.textFields.firstMatch
        XCTAssertTrue(offer.waitForExistence(timeout: 6), "TC 32: the offer shows")
        XCTAssertTrue(field.waitForExistence(timeout: 4), "confirmation field")
        XCTAssertLessThan(offer.frame.minY, field.frame.minY, "TC 32: the offer sits before the confirmation field")

        offer.tap()
        XCTAssertTrue(app.staticTexts["Ekspor data"].waitForExistence(timeout: 6), "TC 33: the existing export page opens")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Konfirmasi"].waitForExistence(timeout: 5), "TC 33: back on the delete screen")
        XCTAssertTrue(app.buttons["Ekspor data dulu"].waitForExistence(timeout: 4), "TC 34: skipping is just going on")
    }
}
