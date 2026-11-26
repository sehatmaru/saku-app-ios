import XCTest

/// Temporary capture helper for marketing screenshots. Not part of the suite.
final class ZZSakuIntroTests: XCTestCase {
    @MainActor
    private func snap(_ name: String) {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: dir.appendingPathComponent(name + ".png"))
    }

    @MainActor
    private func tap(_ e: XCUIElement) { e.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }

    @MainActor
    func testIntroAndSetupDump() throws {
        let app = XCUIApplication()
        app.launch()
        sleep(6)
        snap("01-intro-1")
        if app.buttons["Lanjut"].exists { tap(app.buttons["Lanjut"]); sleep(2) }
        snap("02-intro-2")
        if app.buttons["Lanjut"].exists { tap(app.buttons["Lanjut"]); sleep(2) }
        snap("03-intro-3")
        let masuk = app.buttons["Yuk, masuk"]
        if masuk.exists { tap(masuk); sleep(3) }
        snap("04-masuk")

        let guest = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'tamu'")).firstMatch
        if guest.waitForExistence(timeout: 8) { tap(guest); sleep(3) }
        if app.textFields["Nama panggilan"].exists {
            tap(app.textFields["Nama panggilan"]); app.typeText("Rani"); sleep(1)
        }
        snap("05-nama")
        if app.buttons["Lanjut"].exists { tap(app.buttons["Lanjut"]); sleep(3) }
        snap("06-dompet-pilih")

        for name in ["BCA", "Dompet tunai"] {
            let b = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", name)).firstMatch
            if b.exists { tap(b); sleep(1) }
        }
        snap("07-dompet-dipilih")
        if app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Lanjut'")).firstMatch.exists {
            tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Lanjut'")).firstMatch); sleep(3)
        }
        snap("08-saldo")
        print("=== SALDO TREE ===")
        print(app.debugDescription)
        for t in app.textFields.allElementsBoundByIndex where t.exists { print("TF", t.label, t.placeholderValue ?? "", t.frame) }
        for b in app.buttons.allElementsBoundByIndex where b.exists { print("BTN", b.label, b.frame) }
    }
}
