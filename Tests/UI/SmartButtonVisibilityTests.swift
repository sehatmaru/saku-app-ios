import XCTest

/// BUG-30: the sparkle button belongs to the pages of the tab bar only. A page pushed
/// over a tab (e.g. Profil > Ubah Profil) must not show it, and coming back must restore it.
final class SmartButtonVisibilityTests: XCTestCase {
    @MainActor
    func testSparkleButtonHidesOnPushedPageAndReturnsOnTab() throws {
        let app = XCUIApplication()
        app.launch()

        let fab = app.buttons["smartTrackerFab"]
        XCTAssertTrue(fab.waitForExistence(timeout: 25), "tombol ✦ harus tampil di Beranda")

        // Every tab root keeps the button (commit 873d0e3).
        let profil = app.tabBars.buttons["Profil"]
        if profil.waitForExistence(timeout: 3) {
            profil.tap()
        } else {
            app.tabBars.buttons.element(boundBy: 3).tap()
        }
        XCTAssertTrue(fab.waitForExistence(timeout: 5), "tombol ✦ harus tampil di root tab Profil")

        // A pushed page is not a tab root: the button goes away with the tab bar.
        app.buttons["Ubah"].tap()
        XCTAssertTrue(app.navigationBars["Ubah Profil"].waitForExistence(timeout: 5))
        XCTAssertTrue(fab.waitForNonExistence(timeout: 5), "tombol ✦ harus tersembunyi di halaman detail")

        // Back to the tab: the button is back.
        app.navigationBars["Ubah Profil"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(fab.waitForExistence(timeout: 5), "tombol ✦ kembali setelah balik ke tab")
    }

    /// BUG-35: a pushed page hides the tab bar, the same way it hides the smart tracker button.
    @MainActor
    func testTabBarHidesOnPushedPages() throws {
        let app = XCUIApplication()
        app.launch()
        let profil = app.tabBars.buttons["Profil"]
        XCTAssertTrue(profil.waitForExistence(timeout: 25), "tab bar at launch")
        profil.tap()
        usleep(900_000)
        if !profil.isSelected { profil.tap() } // a first tap can be eaten by an overlay

        let exportRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Ekspor data")).firstMatch
        XCTAssertTrue(exportRow.waitForExistence(timeout: 8), "row Ekspor data")
        exportRow.tap()
        XCTAssertTrue(app.staticTexts["Ekspor data"].waitForExistence(timeout: 5), "page Ekspor data")

        XCTAssertTrue(app.tabBars.firstMatch.waitForNonExistence(timeout: 5), "tab bar hides on the pushed page")
        XCTAssertTrue(app.buttons["smartTrackerFab"].waitForNonExistence(timeout: 3), "the ✦ button hides too")
    }
}
