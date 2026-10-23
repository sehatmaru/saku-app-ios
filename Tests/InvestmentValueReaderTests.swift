import XCTest
@testable import Saku

final class InvestmentValueReaderTests: XCTestCase {
    func testLabelledTotalOnTheSameLine() {
        let c = InvestmentValueReader.candidates(lines: ["Portofolio", "Total nilai  Rp52.340.000", "Untung Rp4.340.000"])
        XCTAssertEqual(c, [.init(label: "Total nilai", amount: 52_340_000)])
    }

    func testAmountOnTheLineUnderTheLabel() {
        let c = InvestmentValueReader.candidates(lines: ["Nilai portofolio", "Rp 12.500.000", "Hari ini +1,2%"])
        XCTAssertEqual(c.first?.amount, 12_500_000)
    }

    func testSeveralCandidatesStartWithTheTotal() {
        let c = InvestmentValueReader.candidates(lines: ["Dana tersedia Rp440.000", "Saldo Rp51.900.000", "Total nilai Rp52.340.000"])
        XCTAssertEqual(c.map(\.label), ["Total nilai", "Saldo", "Dana tersedia"])
        XCTAssertEqual(c.map(\.amount), [52_340_000, 51_900_000, 440_000])
    }

    func testTheSameAmountIsListedOnce() {
        let c = InvestmentValueReader.candidates(lines: ["Total nilai Rp1.000.000", "Saldo Rp1.000.000"])
        XCTAssertEqual(c.count, 1)
    }

    func testNothingLabelledMeansNothingFound() {
        XCTAssertTrue(InvestmentValueReader.candidates(lines: ["Selamat datang", "Rp25.000", ""]).isEmpty)
        XCTAssertTrue(InvestmentValueReader.candidates(lines: []).isEmpty)
    }
}
