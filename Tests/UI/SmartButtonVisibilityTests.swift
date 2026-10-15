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
}
