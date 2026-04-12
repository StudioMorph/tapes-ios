import Foundation
import SwiftUI

/// Unified access-control layer combining subscription + trial state.
@MainActor
final class EntitlementManager: ObservableObject {

    let subscriptionManager: SubscriptionManager
    let trialManager: TrialManager

    // MARK: - Published

    @Published private(set) var accessLevel: AccessLevel = .free

    enum AccessLevel: Equatable {
        case free
        case plus
        case together
    }

    // MARK: - Lifecycle

    init(subscriptionManager: SubscriptionManager? = nil,
         trialManager: TrialManager? = nil) {
        self.subscriptionManager = subscriptionManager ?? SubscriptionManager()
        self.trialManager = trialManager ?? TrialManager()
        refresh()
    }

    // MARK: - Derived Helpers

    var isPremium: Bool { accessLevel == .plus || accessLevel == .together }
    var isTogether: Bool { accessLevel == .together }
    var canUseFully: Bool { isPremium || trialManager.isTrialActive }
    var shouldShowPaywall: Bool { !isPremium && trialManager.isTrialExpired }

    func canCreateTape(currentCount: Int) -> Bool {
        if isPremium { return true }
        return trialManager.canCreateTape(currentCount: currentCount)
    }

    // MARK: - Refresh

    func refresh() {
        if let tier = subscriptionManager.activeTier {
            switch tier {
            case .plus:     accessLevel = .plus
            case .together: accessLevel = .together
            }
        } else {
            trialManager.refreshTrialState()
            accessLevel = .free
        }
    }

    func refreshAsync() async {
        await subscriptionManager.refreshSubscriptionStatus()
        refresh()
    }
}
