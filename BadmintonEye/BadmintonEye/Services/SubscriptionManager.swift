import Foundation
import StoreKit

/// Manages StoreKit 2 subscription lifecycle and premium entitlement checking.
/// Singleton accessed via `SubscriptionManager.shared`.
@Observable
final class SubscriptionManager: @unchecked Sendable {

    static let shared = SubscriptionManager()

    // MARK: - Public State

    var isPremium: Bool = false
    var currentSubscription: Product.SubscriptionInfo.Status?
    var availableProducts: [Product] = []
    /// Whether the current Apple ID has not yet redeemed the introductory offer on the yearly plan.
    var isEligibleForTrial: Bool = false

    // MARK: - Private

    private let productIDs = ["hawkeye_monthly", "hawkeye_yearly"]
    private var updateListenerTask: Task<Void, Error>?

    private init() {
        if AppMode.freeAppleIDMode {
            // Free Apple IDs cannot use StoreKit IAP. Treat the user as
            // premium so the MVP exercises the Hawk Eye / auto-suggest flow
            // without a paywall, and skip every StoreKit call.
            isPremium = true
            return
        }
        updateListenerTask = listenForTransactions()
        Task {
            await loadProducts()
            await updateSubscriptionStatus()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Load Products

    /// Fetches subscription products from the App Store.
    func loadProducts() async {
        if AppMode.freeAppleIDMode { return }
        do {
            let products = try await Product.products(for: productIDs)
            await MainActor.run {
                availableProducts = products.sorted { $0.price < $1.price }
            }
        } catch {
            print("[SubscriptionManager] Failed to load products: \(error)")
        }
    }

    // MARK: - Purchase

    /// Initiates a purchase for the given product.
    /// - Returns: The verified transaction on success, nil if cancelled or pending.
    func purchase(_ product: Product) async throws -> Transaction? {
        if AppMode.freeAppleIDMode { return nil }
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await updateSubscriptionStatus()
            return transaction

        case .userCancelled:
            return nil

        case .pending:
            return nil

        @unknown default:
            return nil
        }
    }

    // MARK: - Restore

    /// Syncs with the App Store and refreshes subscription status.
    func restorePurchases() async {
        if AppMode.freeAppleIDMode { return }
        do {
            try await AppStore.sync()
        } catch {
            print("[SubscriptionManager] Restore failed: \(error)")
        }
        await updateSubscriptionStatus()
    }

    // MARK: - Subscription Status

    /// Checks current entitlements to determine premium status.
    func updateSubscriptionStatus() async {
        if AppMode.freeAppleIDMode { return }
        var foundActive = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                continue
            }

            if productIDs.contains(transaction.productID) {
                if transaction.revocationDate == nil {
                    foundActive = true
                }
            }
        }

        await MainActor.run {
            isPremium = foundActive
        }
    }

    // MARK: - Transaction Listener

    /// Listens for transaction updates (renewals, revocations, etc).
    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if let transaction = try? self.checkVerified(result) {
                    await transaction.finish()
                    await self.updateSubscriptionStatus()
                }
            }
        }
    }

    // MARK: - Verification

    /// Unwraps a verified result or throws for unverified.
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }
}
