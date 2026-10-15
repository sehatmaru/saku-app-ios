import XCTest
@testable import Saku

@MainActor
final class ProfileViewModelTests: XCTestCase {
    func testEmptyOrBlankNameIsRejectedBeforeAnySave() async {
        for name in ["", "   ", "\n"] {
            let model = ProfileViewModel()
            model.displayName = name
            let saved = await model.saveProfile(user: nil, photo: nil)
            XCTAssertNil(saved)
            XCTAssertEqual(model.errorMessage, L("Nama tidak boleh kosong"))
        }
    }
}
