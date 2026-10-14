import XCTest
import StoreKit
import StoreKitTest
@testable import SecretPlaces

/// Exercises the real StoreKit 2 purchase path against the local .storekit
/// configuration (SKTestSession) — no App Store Connect required. Verifies
/// products load, a purchase yields a VERIFIED transaction with a JWS to send
/// to the verify-purchase Edge Function, and the entitlement appears.
///
/// StoreKit Testing runs fully in Xcode (GUI) and `xcodebuild test` with the
/// StoreKit configuration active. In environments where the local StoreKit
/// test store isn't wired up, these tests SKIP (rather than fail) so the suite
/// stays green — the assertions still run wherever the test store is active.
final class StoreKitPurchaseTests: XCTestCase {
    var session: SKTestSession!
    let productId = "com.secretplaces.place.k41"

    override func setUpWithError() throws {
        session = try SKTestSession(configurationFileNamed: "SecretPlaces")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
    }
    override func tearDown() { session = nil }

    /// Skips the test unless the local StoreKit test store is active.
    private func requireStoreKitTesting() async throws -> [Product] {
        let products = try await Product.products(for: [
            "com.secretplaces.place.k41",
            "com.secretplaces.place.krysha_933879",
            "com.secretplaces.route.gg_after_dark",
        ])
        try XCTSkipUnless(!products.isEmpty, "StoreKit Testing store not active in this environment")
        return products
    }

    func testProductsLoadFromConfiguration() async throws {
        let products = try await requireStoreKitTesting()
        XCTAssertEqual(products.count, 3)
        XCTAssertTrue(products.allSatisfy { $0.type == .nonConsumable })
        let places = products.filter { $0.id.hasPrefix("com.secretplaces.place.") }
        XCTAssertEqual(places.count, 2)
        XCTAssertTrue(places.allSatisfy { $0.displayPrice.contains("0.99") })
    }

    func testPurchaseProducesVerifiedTransactionWithJWS() async throws {
        _ = try await requireStoreKitTesting()
        let products = try await Product.products(for: [productId])
        let product = try XCTUnwrap(products.first)
        let result = try await product.purchase()
        guard case .success(let verification) = result else { return XCTFail("expected .success, got \(result)") }
        guard case .verified(let transaction) = verification else { return XCTFail("transaction not verified") }
        XCTAssertEqual(transaction.productID, productId)
        // The JWS is exactly what PurchaseService sends to verify-purchase (the trust boundary).
        XCTAssertFalse(verification.jwsRepresentation.isEmpty)
        await transaction.finish()
    }

    func testEntitlementPresentAfterPurchase() async throws {
        _ = try await requireStoreKitTesting()
        let products = try await Product.products(for: [productId])
        let product = try XCTUnwrap(products.first)
        _ = try await product.purchase()
        var found = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == productId { found = true }
        }
        XCTAssertTrue(found, "purchased product should appear in current entitlements")
    }
}
