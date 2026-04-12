import StoreKit
import SwiftUI

@MainActor
final class SubscriptionManager: ObservableObject {

    // MARK: - Product IDs

    enum Tier: String, CaseIterable {
        case plus
        case together
    }

    enum BillingCycle: String, CaseIterable {
        case monthly
        case annually
    }

    static let plusMonthlyID    = "com.tapes.plus.monthly"
    static let plusAnnualID     = "com.tapes.plus.annual"
    static let togetherMonthlyID = "com.tapes.together.monthly"
    static let togetherAnnualID  = "com.tapes.together.annual"

    static let allProductIDs: Set<String> = [
        plusMonthlyID, plusAnnualID,
        togetherMonthlyID, togetherAnnualID
    ]

    // Legacy alias kept for backward compatibility
    static let monthlyProductID = plusMonthlyID

    // MARK: - Published State

    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var activeTier: Tier?
    @Published private(set) var isLoading = false
    @Published var purchaseError: String?

    // MARK: - Private

    private var transactionListener: Task<Void, Never>?

    // MARK: - Lifecycle

    init() {
        transactionListener = listenForTransactions()
        Task { await loadProducts() }
        Task { await refreshSubscriptionStatus() }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Convenience Accessors

    var monthlyProduct: Product? { products[Self.plusMonthlyID] }

    func product(for tier: Tier, cycle: BillingCycle) -> Product? {
        products[Self.productID(tier: tier, cycle: cycle)]
    }

    static func productID(tier: Tier, cycle: BillingCycle) -> String {
        switch (tier, cycle) {
        case (.plus, .monthly):    return plusMonthlyID
        case (.plus, .annually):   return plusAnnualID
        case (.together, .monthly):  return togetherMonthlyID
        case (.together, .annually): return togetherAnnualID
        }
    }

    var isSubscribed: Bool { activeTier != nil }

    // MARK: - Load Products

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: Self.allProductIDs)
            var map: [String: Product] = [:]
            for p in loaded { map[p.id] = p }
            products = map
        } catch {
            purchaseError = "Failed to load subscriptions: \(error.localizedDescription)"
        }
    }

    // MARK: - Purchase

    func purchase(tier: Tier, cycle: BillingCycle) async {
        let id = Self.productID(tier: tier, cycle: cycle)
        guard let product = products[id] else {
            purchaseError = "Product not available."
            return
        }

        isLoading = true
        purchaseError = nil

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshSubscriptionStatus()

            case .userCancelled:
                break

            case .pending:
                purchaseError = "Purchase is pending approval."

            @unknown default:
                break
            }
        } catch {
            purchaseError = "Purchase failed: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Legacy single-product purchase for backward compatibility.
    func purchase() async {
        await purchase(tier: .plus, cycle: .monthly)
    }

    // MARK: - Restore

    func restore() async {
        isLoading = true
        try? await AppStore.sync()
        await refreshSubscriptionStatus()
        isLoading = false
    }

    // MARK: - Subscription Status

    func refreshSubscriptionStatus() async {
        var resolved: Tier?

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            guard transaction.revocationDate == nil else { continue }
            if let exp = transaction.expirationDate, exp < Date() { continue }

            if transaction.productID == Self.togetherMonthlyID ||
               transaction.productID == Self.togetherAnnualID {
                resolved = .together
                break
            }
            if transaction.productID == Self.plusMonthlyID ||
               transaction.productID == Self.plusAnnualID {
                resolved = .plus
            }
        }

        activeTier = resolved
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self = self else { return }
                if let transaction = try? await self.checkVerified(result) {
                    await transaction.finish()
                    await self.refreshSubscriptionStatus()
                }
            }
        }
    }

    // MARK: - Verification

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }
}
