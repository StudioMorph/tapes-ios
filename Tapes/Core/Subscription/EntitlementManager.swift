import Combine
import Foundation
import SwiftUI

/// Unified access-control layer for Free vs Plus.
///
/// Owns:
///   - The derived `accessLevel` (mirrors `SubscriptionManager.activeTier`).
///   - The free-tier activation set: a per-install record of every tape that
///     has been "activated" by being shared OR turned into a collab tape.
///     Free users are capped at `freeShareCollabCap` activations across the
///     whole app. The set is used (not just a count) so the same tape can't
///     double-count and so existing-tape grandfathering survives reinstall
///     of the cap logic itself.
///   - Feature-level gates (AI prompt, library track cap).
///
/// Storage: UserDefaults — wiped on app uninstall, which is the intended
/// per-install scope. Server-side persistence will replace this when accounts
/// can carry monetisation state.
@MainActor
final class EntitlementManager: ObservableObject {

    // MARK: - Constants

    /// Combined cap for shared + collab tapes on the Free tier.
    static let freeShareCollabCap: Int = 5

    /// Maximum library tracks visible to Free users (out of ~12,000).
    /// Currently dialled down to **100** for on-device QA — flip back to
    /// 1000 (or whatever the final ship value is) before TestFlight. The
    /// "Upgrade to unlock 12,000 tracks" toolbar copy is independent of
    /// this number; it always reads the full library size.
    static let freeLibraryTrackCap: Int = 100

    // MARK: - UserDefaults keys

    private enum Key {
        static let activatedTapeIDs = "monetisation.activatedTapeIDs.v1"
        static let didMigrate = "monetisation.didMigrateActivatedTapeIDs.v1"
    }

    let subscriptionManager: SubscriptionManager

    // MARK: - Published

    @Published private(set) var accessLevel: AccessLevel = .free
    @Published private(set) var activatedTapeIDs: Set<UUID> = []

    enum AccessLevel: Equatable {
        case free
        case plus
    }

    // MARK: - Private

    /// Holds the Combine subscription that mirrors
    /// `SubscriptionManager.activeTier` into our `accessLevel`. Without this
    /// the tier flag flipped on purchase but every consumer of
    /// `EntitlementManager` (Account screen, paywall gates, music tabs)
    /// kept reading the stale value until the next app launch.
    private var tierObservation: AnyCancellable?

    // MARK: - Lifecycle

    init(subscriptionManager: SubscriptionManager? = nil) {
        self.subscriptionManager = subscriptionManager ?? SubscriptionManager()
        loadActivatedTapeIDs()
        refresh()

        tierObservation = self.subscriptionManager.$activeTier
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
    }

    // MARK: - Tier helpers

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

    // MARK: - Activation set (share / collab cap)

    var activatedTapeCount: Int { activatedTapeIDs.count }

    /// True when a previously-uncounted tape can be activated. Plus tier
    /// always returns true; Free tier returns true while under the cap.
    func canActivateNewTape() -> Bool {
        if isPremium { return true }
        return activatedTapeIDs.count < Self.freeShareCollabCap
    }

    func isTapeAlreadyActivated(_ id: UUID) -> Bool {
        activatedTapeIDs.contains(id)
    }

    /// Records that a tape has been activated. Idempotent — repeat calls
    /// for the same ID are no-ops. Persists immediately so the count
    /// survives a crash mid-flow.
    func markTapeActivated(_ id: UUID) {
        guard !activatedTapeIDs.contains(id) else { return }
        activatedTapeIDs.insert(id)
        persistActivatedTapeIDs()
    }

    /// One-time grandfathering pass run from `TapesApp` on first launch
    /// after this code ships. Seeds the set with every tape currently
    /// shared or marked collab, so existing test tapes don't break.
    func migrateActivatedTapeIDs(from tapes: [Tape]) {
        let didMigrate = UserDefaults.standard.bool(forKey: Key.didMigrate)
        guard !didMigrate else { return }

        var seeded = activatedTapeIDs
        for tape in tapes where tape.isShared || tape.isCollabTape {
            seeded.insert(tape.id)
        }
        if seeded != activatedTapeIDs {
            activatedTapeIDs = seeded
            persistActivatedTapeIDs()
        }
        UserDefaults.standard.set(true, forKey: Key.didMigrate)
    }

    // MARK: - Feature gates

    /// AI Prompt music tab is Plus-only.
    var canUseAIPrompt: Bool { isPremium }

    /// Library track cap. `nil` for Plus (unlimited), `freeLibraryTrackCap`
    /// for Free.
    var libraryTrackCap: Int? {
        isPremium ? nil : Self.freeLibraryTrackCap
    }

    // MARK: - Persistence

    private func loadActivatedTapeIDs() {
        guard let raw = UserDefaults.standard.array(forKey: Key.activatedTapeIDs) as? [String] else {
            return
        }
        activatedTapeIDs = Set(raw.compactMap(UUID.init(uuidString:)))
    }

    private func persistActivatedTapeIDs() {
        let strings = activatedTapeIDs.map { $0.uuidString }
        UserDefaults.standard.set(strings, forKey: Key.activatedTapeIDs)
    }
}
