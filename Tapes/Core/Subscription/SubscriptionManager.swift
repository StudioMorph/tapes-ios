import StoreKit
import SwiftUI

@MainActor
final class SubscriptionManager: ObservableObject {

    // MARK: - Product IDs

    enum Tier: String, CaseIterable {
        case plus
    }

    enum BillingCycle: String, CaseIterable {
        case monthly
        case annually
    }

    static let plusMonthlyID = "com.tapes.plus.monthly"
    static let plusAnnualID  = "com.tapes.plus.annual"

    static let allProductIDs: Set<String> = [
        plusMonthlyID, plusAnnualID
    ]

    // MARK: - Published State

    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var activeTier: Tier?
    @Published private(set) var isLoading = false
    @Published var purchaseError: String?

    /// Per-product introductory-offer eligibility for the current Apple ID.
    /// `true` means the user has not yet used their intro / free trial for
    /// the product's subscription group and the trial copy on the paywall
    /// should be shown. Refreshed whenever products are loaded.
    @Published private(set) var introOfferEligibility: [String: Bool] = [:]

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

    func product(for cycle: BillingCycle) -> Product? {
        products[Self.productID(cycle: cycle)]
    }

    static func productID(cycle: BillingCycle) -> String {
        switch cycle {
        case .monthly:  return plusMonthlyID
        case .annually: return plusAnnualID
        }
    }

    var isSubscribed: Bool { activeTier != nil }

    /// Whether the current Apple ID is still eligible for the intro / free
    /// trial offer on the given billing cycle. Drives whether the paywall
    /// renders the "7 days Free Trial" line on each card.
    func isEligibleForTrial(cycle: BillingCycle) -> Bool {
        introOfferEligibility[Self.productID(cycle: cycle)] ?? false
    }

    // MARK: - Load Products

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: Self.allProductIDs)
            #if DEBUG
            print("[SubscriptionManager] Requested IDs: \(Self.allProductIDs)")
            print("[SubscriptionManager] Loaded \(loaded.count) products: \(loaded.map { $0.id })")
            #endif
            var map: [String: Product] = [:]
            for p in loaded { map[p.id] = p }
            products = map
            await refreshIntroOfferEligibility()
        } catch {
            #if DEBUG
            print("[SubscriptionManager] Failed to load products: \(error)")
            #endif
            purchaseError = "Failed to load subscriptions: \(error.localizedDescription)"
        }
    }

    /// Asks StoreKit which products the current Apple ID is still eligible
    /// for an introductory offer on. Eligibility is per *subscription
    /// group*, not per product, but StoreKit exposes it on each product —
    /// returning the same answer for every product in the same group.
    private func refreshIntroOfferEligibility() async {
        var map: [String: Bool] = [:]
        for (id, product) in products {
            guard let subscription = product.subscription else { continue }
            map[id] = await subscription.isEligibleForIntroOffer
        }
        introOfferEligibility = map
    }

    // MARK: - Purchase

    func purchase(cycle: BillingCycle) async {
        let id = Self.productID(cycle: cycle)
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

    func purchase() async {
        await purchase(cycle: .monthly)
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

            if transaction.productID == Self.plusMonthlyID ||
               transaction.productID == Self.plusAnnualID {
                resolved = .plus
                break
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
