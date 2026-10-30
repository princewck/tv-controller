import XCTest
import StoreKit
import StoreKitTest
@testable import FamilyTV

final class SubscriptionTests: XCTestCase {
    @MainActor func testMonthlyProductPurchaseAndExpirationUsingLocalStoreKit() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "FamilyTV", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }
        let subscription = SubscriptionStore()
        await subscription.load()
        let product = try XCTUnwrap(subscription.product, subscription.message ?? "Product not loaded")
        XCTAssertEqual(product.id, SubscriptionStore.productID)
        XCTAssertEqual(product.price, Decimal(string: "9.90"))
        XCTAssertEqual(product.subscription?.subscriptionPeriod.unit, .month)
        XCTAssertFalse(subscription.entitled)
        let account = UUID()
        let transaction = try await session.buyProduct(identifier: SubscriptionStore.productID, options: [.appAccountToken(account)])
        XCTAssertEqual(transaction.appAccountToken, account)
        await subscription.refreshEntitlements()
        XCTAssertTrue(subscription.entitled)
        XCTAssertTrue(subscription.hasAccess(for: account.uuidString))
        let replacement = UUID()
        XCTAssertFalse(subscription.hasAccess(for: replacement.uuidString))
        XCTAssertTrue(subscription.receipts(for: replacement).isEmpty)
        let latestResult = await Transaction.latest(for: SubscriptionStore.productID)
        guard let latestResult, case let .verified(latest) = latestResult else { XCTFail("Missing verified local transaction"); return }
        XCTAssertEqual(subscription.receipts(for: replacement, ownedOriginalIDs: [String(latest.originalID)]).count, 1)
        XCTAssertTrue(subscription.receipts(for: replacement, ownedOriginalIDs: ["unrelated"]).isEmpty)
        try session.disableAutoRenewForTransaction(identifier: UInt(transaction.id))
        try session.expireSubscription(productIdentifier: SubscriptionStore.productID)
        for _ in 0..<10 {
            await subscription.refreshEntitlements()
            if !subscription.entitled { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        XCTAssertFalse(subscription.entitled)
    }
}
