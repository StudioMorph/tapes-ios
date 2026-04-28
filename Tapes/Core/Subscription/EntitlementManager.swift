import Foundation
import SwiftUI

/// Unified access-control layer for Free vs Plus.
@MainActor
final class EntitlementManager: ObservableObject {

    let subscriptionManager: SubscriptionManager

    // MARK: - Constants

    static let maxFreeSharedTapes = 5

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

    func canShareOrCollab(lifetimeSharedCount: Int) -> Bool {
        if isPremium { return true }
        return lifetimeSharedCount < Self.maxFreeSharedTapes
    }

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
