import SwiftUI
import os

@MainActor
final class NavigationCoordinator: ObservableObject {

    @Published var selectedTab: MainTabView.AppTab = .myTapes
    @Published var pendingSharedTapeId: String?
    @Published var isResolvingDeepLink = false
    @Published var deepLinkError: String?

    private let log = Logger(subsystem: "com.studiomorph.tapes", category: "Navigation")

    func handleShareLink(shareId: String, api: TapesAPIClient) {
        isResolvingDeepLink = true
        deepLinkError = nil

        Task {
            do {
                let resolution = try await api.resolveShare(shareId: shareId)
                log.info("Resolved share \(shareId) → tape \(resolution.tapeId)")

                pendingSharedTapeId = resolution.tapeId
                selectedTab = .shared
                isResolvingDeepLink = false
            } catch {
                log.error("Failed to resolve share \(shareId): \(error.localizedDescription)")
                deepLinkError = error.localizedDescription
                isResolvingDeepLink = false
            }
        }
    }

    func clearPendingTape() {
        pendingSharedTapeId = nil
    }
}
