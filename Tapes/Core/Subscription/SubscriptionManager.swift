//
//  SubscriptionManager.swift
//  Tapes
//
//  Created by AI Assistant on 26/01/2026.
//

import StoreKit
import SwiftUI

@MainActor
final class SubscriptionManager: ObservableObject {

    static let monthlyProductID = "com.tapes.premium.monthly"

    // MARK: - Published State

    @Published private(set) var monthlyProduct: Product?
    @Published private(set) var subscriptionStatus: SubscriptionStatus = .notSubscribed
    @Published private(set) var isLoading = false
    @Published var purchaseError: String?

    enum SubscriptionStatus: Equatable {
        case notSubscribed
        case subscribed
        case expired
        case revoked
    }

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

    // MARK: - Load Products

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.monthlyProductID])
            monthlyProduct = products.first
        } catch {
            purchaseError = "Failed to load subscription: \(error.localizedDescription)"
        }
    }

    // MARK: - Purchase

    func purchase() async {
        guard let product = monthlyProduct else {
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

    // MARK: - Restore

    func restore() async {
        isLoading = true
        try? await AppStore.sync()
        await refreshSubscriptionStatus()
        isLoading = false
    }

    // MARK: - Subscription Status

    var isSubscribed: Bool {
        subscriptionStatus == .subscribed
    }

    func refreshSubscriptionStatus() async {
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if transaction.productID == Self.monthlyProductID {
                if transaction.revocationDate != nil {
                    subscriptionStatus = .revoked
                } else if let expirationDate = transaction.expirationDate,
                          expirationDate < Date() {
                    subscriptionStatus = .expired
                } else {
                    subscriptionStatus = .subscribed
                    return
                }
            }
        }

        if subscriptionStatus != .subscribed {
            subscriptionStatus = .notSubscribed
        }
    }

    // MARK: - Intro Offer Eligibility

    var introOfferEligible: Bool {
        get async {
            guard let product = monthlyProduct,
                  let subscription = product.subscription else { return false }
            return await subscription.isEligibleForIntroOffer
        }
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
