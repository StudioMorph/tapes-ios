import Foundation
import SwiftUI

/// Unified access-control layer for Free vs Plus.
///
/// Currently only exposes the binary access level (`free` / `plus`)
/// derived from `SubscriptionManager.activeTier`. All previous
/// "free-tier limit" helpers have been removed pending the new paywall
/// design — re-introduce gates here when the new limits are decided.
@MainActor
final class EntitlementManager: ObservableObject {

    let subscriptionManager: SubscriptionManager

    // MARK: - Published

    @Published private(set) var accessLevel: AccessLevel = .free

    enum AccessLevel: Equatable {
        case free
        case plus
    }

    // MARK: - Lifecycle

    init(subscriptionManager: SubscriptionManager? = nil) {
        self.subscriptionManager = subscriptionManager ?? SubscriptionManager()
        refresh()
    }

    // MARK: - Derived Helpers

    var isPremium: Bool { accessLevel == .plus }
    var isFreeUser: Bool { accessLevel == .free }

    // MARK: - Refresh

    func refresh() {
        if subscriptionManager.activeTier != nil {
            accessLevel = .plus
        } else {
            accessLevel = .free
        }
    }

    func refreshAsync() async {
        await subscriptionManager.refreshSubscriptionStatus()
        refresh()
    }
}
