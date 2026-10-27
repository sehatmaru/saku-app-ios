import XCTest
@testable import Saku

final class CategoryIconsTests: XCTestCase {
    func testTheFirstIconsAreASubsetOfTheWholePool() {
        XCTAssertGreaterThanOrEqual(CategoryCatalog.featuredIcons.count, 14)
        XCTAssertTrue(Set(CategoryCatalog.featuredIcons).isSubset(of: Set(CategoryCatalog.allIcons)))
    }

    func testCollapsedShowsTheFirstSetAndExpandedShowsEverything() {
        XCTAssertEqual(CategoryCatalog.visibleIcons(expanded: false), CategoryCatalog.featuredIcons)
        XCTAssertEqual(CategoryCatalog.visibleIcons(expanded: true), CategoryCatalog.allIcons)
        XCTAssertGreaterThan(CategoryCatalog.allIcons.count, CategoryCatalog.featuredIcons.count)
    }

    func testAnIconOutsideTheFirstSetOpensTheWholeList() {
        XCTAssertFalse(CategoryCatalog.needsAllIcons(for: "fork.knife"))
        XCTAssertTrue(CategoryCatalog.needsAllIcons(for: "scissors"))
    }

    func testEveryColourIsAValidHex() {
        for hex in CategoryCatalog.colors {
            XCTAssertNotNil(UInt64(hex.dropFirst(), radix: 16), hex)
        }
    }
}
