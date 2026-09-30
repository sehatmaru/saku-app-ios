import XCTest
@testable import SakuQ

final class CategoryRenameTests: XCTestCase {
    private let base = Category(id: "c", name: "Makan Harian", icon: "fork.knife", color: "#FF6B6B",
                                type: .expense, systemKey: "expense_daily_meals", ownerType: "system")

    func testRenamingKeepsTheSharedNameToRestore() {
        let renamed = base.named("Makan")
        XCTAssertEqual(renamed.name, "Makan")
        XCTAssertEqual(renamed.defaultName, "Makan Harian")
        XCTAssertTrue(renamed.isBuiltIn)
        // Renaming again keeps pointing at the shared name.
        XCTAssertEqual(renamed.named("Kuliner").defaultName, "Makan Harian")
    }

    func testTypingTheSharedNameRestoresIt() {
        let back = base.named("Makan").named("Makan Harian")
        XCTAssertEqual(back.name, "Makan Harian")
        XCTAssertNil(back.defaultName)
    }
}
