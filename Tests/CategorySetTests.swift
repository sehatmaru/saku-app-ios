import XCTest
@testable import Saku

final class CategorySetTests: XCTestCase {
    func testNewAccountsGetSevenExpenseAndFourIncomeCategories() {
        XCTAssertEqual(OnboardingCategory.expense.count, 7)
        XCTAssertEqual(OnboardingCategory.income.count, 4)
        XCTAssertEqual(Set(OnboardingCategory.all.map(\.key)).count, 11)
    }

    func testRetiredCategoriesAreNotOffered() {
        let keys = Set(OnboardingCategory.all.map(\.key))
        for old in ["expense_restaurant_mall", "expense_personal_spending", "expense_entertainment",
                    "expense_social_donation", "expense_sport_fitness", "expense_care_health"] {
            XCTAssertFalse(keys.contains(old), old)
        }
        XCTAssertTrue(keys.contains("expense_bills_subscriptions"))
        XCTAssertTrue(keys.contains("expense_health_sport"))
    }
}
