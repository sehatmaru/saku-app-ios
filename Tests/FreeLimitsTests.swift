import XCTest
@testable import Saku

final class FreeLimitsTests: XCTestCase {
    private func category(_ id: String, _ type: CategoryType, key: String? = nil) -> Saku.Category {
        Category(id: id, name: id, icon: nil, color: nil, type: type, systemKey: key)
    }

    func testLimitsPerType() {
        XCTAssertEqual(FreeLimits.categories(.expense), 7)
        XCTAssertEqual(FreeLimits.categories(.income), 5)
        XCTAssertEqual(FreeLimits.budgets, 7)
    }

    func testActiveCountIgnoresOtherTypeAndBalanceCorrection() {
        let shown = [category("a", .expense), category("b", .expense), category("adj", .expense, key: "adjustment"), category("c", .income)]
        XCTAssertEqual(FreeLimits.activeCount(shown, type: .expense), 2)
        XCTAssertEqual(FreeLimits.activeCount(shown, type: .income), 1)
    }

    func testServerRefusalBecomesReadableMessage() {
        struct Raw: Error, CustomStringConvertible { let description: String }
        XCTAssertEqual(FreeLimits.friendly(Raw(description: "category_limit_expense")).localizedDescription, FreeLimits.categoryMessage(.expense))
        XCTAssertEqual(FreeLimits.friendly(Raw(description: "budget_limit")).localizedDescription, FreeLimits.budgetMessage())
        XCTAssertTrue(FreeLimits.friendly(Raw(description: "network down")) is Raw)
    }
}
