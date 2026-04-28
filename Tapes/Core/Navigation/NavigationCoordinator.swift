import SwiftUI
import os

@MainActor
final class NavigationCoordinator: ObservableObject {

    @Published var selectedTab: MainTabView.AppTab = .myTapes
    @Published var pendingSharedTapeId: String?
    @Published var pendingCollabShareId: String?
    @Published var pendingResetToken: String?
    @Published var isResolvingDeepLink = false
    @Published var deepLinkError: String?

    var apiClient: TapesAPIClient?

    private let log = Logger(subsystem: "com.studiomorph.tapes", category: "Navigation")

    /// Resolves the share mode via the API, then navigates directly to the
    /// correct tab with the share ID ready for download. One API call, no
    /// tab-hopping, no throwaway coordinator.
    func handleShareLink(shareId: String) {
        guard let api = apiClient else {
            log.warning("handleShareLink: no apiClient, falling back to Shared tab")
            pendingSharedTapeId = shareId
            selectedTab = .shared
            return
        }

        guard !isResolvingDeepLink else {
            log.info("handleShareLink: already resolving, ignoring \(shareId)")
            return
        }

        log.info("Resolving share link: \(shareId)")
        isResolvingDeepLink = true

        Task {
            do {
                let resolution = try await api.resolveShare(shareId: shareId)
                let isCollab = resolution.accessMode == "collaborate"
                    || (resolution.accessMode == nil && resolution.mode == "collaborative")

                if isCollab {
                    log.info("Share \(shareId) resolved as collaborative → Collab tab")
                    pendingCollabShareId = shareId
                    selectedTab = .collab
                } else {
                    log.info("Share \(shareId) resolved as view-only → Shared tab")
                    pendingSharedTapeId = shareId
                    selectedTab = .shared
                }
            } catch {
                log.error("resolveShare failed: \(error.localizedDescription) — falling back to Shared tab")
                pendingSharedTapeId = shareId
                selectedTab = .shared
            }

            isResolvingDeepLink = false
        }
    }

    func clearPendingTape() {
        pendingSharedTapeId = nil
    }
}
