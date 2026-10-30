import XCTest
@testable import Saku

@MainActor
final class ExportZipTests: XCTestCase {
    func testZipHoldsEveryCsv() throws {
        let url = try XCTUnwrap(ExportViewModel().zip([("a.csv", "x,y\r\n"), ("b.csv", "z\r\n")], name: "saku-test.zip"))
        let data = try Data(contentsOf: url)
        XCTAssertEqual(Array(data.prefix(2)), [0x50, 0x4B]) // "PK"
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("a.csv") && text.contains("b.csv"))
    }
}
