//
//  EntitlementManager.swift
//  Tapes
//
//  Created by AI Assistant on 26/01/2026.
//

import Foundation
import SwiftUI

/// Unified access-control layer combining subscription + trial state.
@MainActor
final class EntitlementManager: ObservableObject {

    let subscriptionManager: SubscriptionManager
    let trialManager: TrialManager

    // MARK: - Published

    @Published private(set) var accessLevel: AccessLevel = .freeTrial

    enum AccessLevel: Equatable {
        case freeTrial
        case trialExpired
        case premium
    }

    // MARK: - Lifecycle

    init(subscriptionManager: SubscriptionManager? = nil,
         trialManager: TrialManager? = nil) {
        self.subscriptionManager = subscriptionManager ?? SubscriptionManager()
        self.trialManager = trialManager ?? TrialManager()
        refresh()
    }

    // MARK: - Derived Helpers

    var isPremium: Bool { accessLevel == .premium }
    var canUseFully: Bool { accessLevel == .freeTrial || accessLevel == .premium }
    var shouldShowPaywall: Bool { accessLevel == .trialExpired }

    func canCreateTape(currentCount: Int) -> Bool {
        if isPremium { return true }
        return trialManager.canCreateTape(currentCount: currentCount)
    }

    // MARK: - Refresh

    func refresh() {
        if subscriptionManager.isSubscribed {
            accessLevel = .premium
        } else {
            trialManager.refreshTrialState()
            accessLevel = trialManager.isTrialExpired ? .trialExpired : .freeTrial
        }
    }

    func refreshAsync() async {
        await subscriptionManager.refreshSubscriptionStatus()
        refresh()
    }
}
