import XCTest
@testable import Saku

/// Enhancement 5 - Revamp intro: the fixed sample behind the demo on slide 1.
final class IntroSampleTests: XCTestCase {
    func testThreeSentencesAsInThePrd() {
        XCTAssertEqual(IntroSample.all.map(\.sentence), ["kopi 25rb gopay", "bensin 50rb", "gajian 5jt"])
    }

    func testSalaryIsIncomeAndTheRestAreExpenses() {
        XCTAssertEqual(IntroSample.all.map(\.isIncome), [false, false, true])
        XCTAssertEqual(IntroSample.all.map(\.amount), [25_000, 50_000, 5_000_000])
    }
}
