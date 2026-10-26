import StoreKit
import StoreKitTest
import XCTest
@testable import Saku

@MainActor
final class PlusProductsTests: XCTestCase {
    func testBothPlansLoadFromTheStoreWithTheTrial() async throws {
        let session = try SKTestSession(configurationFileNamed: "Saku")
        session.disableDialogs = true
        session.clearTransactions()
        // the first request after the session starts can come back empty
        _ = try await Product.products(for: [Entitlement.yearlyProductID])
        await PlusPurchases.shared.loadProducts()
        let products = PlusPurchases.shared.products
        XCTAssertEqual(products[.yearly]?.id, Entitlement.yearlyProductID)
        XCTAssertEqual(products[.monthly]?.id, Entitlement.monthlyProductID)
        XCTAssertEqual(products[.yearly]?.subscription?.introductoryOffer?.paymentMode, .freeTrial)
        XCTAssertEqual(products[.yearly]?.subscription?.subscriptionPeriod.unit, .year)
    }
}
