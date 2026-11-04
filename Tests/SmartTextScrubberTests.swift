import XCTest
@testable import Saku

final class SmartTextScrubberTests: XCTestCase {
    func testAccountNumberIsRemoved() {
        XCTAssertEqual(SmartTextScrubber.clean("transfer ke 1234567890 25rb"), "transfer ke ••• 25rb")
    }

    func testCardNumberWithSpacesIsRemoved() {
        XCTAssertEqual(SmartTextScrubber.clean("kartu 4111 1111 1111 1111 belanja 50rb"), "kartu ••• belanja 50rb")
    }

    func testOtpCodeIsRemoved() {
        XCTAssertEqual(SmartTextScrubber.clean("Kode OTP 482913 jangan bagikan"), "Kode OTP ••• jangan bagikan")
    }

    func testAmountsAndShortNumbersStay() {
        XCTAssertEqual(SmartTextScrubber.clean("Pembayaran Rp25.000.000 di toko 12"), "Pembayaran Rp25.000.000 di toko 12")
        XCTAssertEqual(SmartTextScrubber.clean("makan 25000000"), "makan 25000000")
    }
}
