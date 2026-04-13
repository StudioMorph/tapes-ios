import SwiftUI
import os

@MainActor
final class NavigationCoordinator: ObservableObject {

    @Published var selectedTab: MainTabView.AppTab = .myTapes
    @Published var pendingSharedTapeId: String?
    @Published var isResolvingDeepLink = false
    @Published var deepLinkError: String?

    private let log = Logger(subsystem: "com.studiomorph.tapes", category: "Navigation")

    /// Navigates to the Shared tab and triggers a download via the share ID.
    func handleShareLink(shareId: String) {
        log.info("Handling share link: \(shareId)")
        pendingSharedTapeId = shareId
        selectedTab = .shared
    }

    func clearPendingTape() {
        pendingSharedTapeId = nil
    }
}
