import Foundation
import os

/// Server-authoritative sync checker.
///
/// **Primary:** Push notifications trigger an immediate check when clips are added.
/// **Fallback:** A 5-minute timer calls `checkAll` in case pushes are missed.
///
/// Uses the lightweight `POST /sync/status` endpoint — one request returns
/// pending download counts for all tapes, replacing per-tape manifest polling.
///
/// Upload counts remain reactive from the local model
/// (see `Tape.pendingUploadCount` and `Clip.isSynced`).
@MainActor
public class TapeSyncChecker: ObservableObject {

    /// Maps local tape ID → number of clips available to download.
    @Published var pendingDownloads: [UUID: Int] = [:]

    private var lastCheckDate: Date?

    /// Minimum interval between automatic checks (fallback timer).
    static let checkInterval: TimeInterval = 300

    private let log = Logger(subsystem: "com.studiomorph.tapes", category: "SyncChecker")

    // MARK: - Public API

    /// Lightweight sync check using `POST /sync/status`.
    /// Respects the cooldown to avoid redundant calls.
    func checkAll(tapes: [Tape], api: TapesAPIClient) {
        if let last = lastCheckDate, Date().timeIntervalSince(last) < Self.checkInterval {
            return
        }
        lastCheckDate = Date()

        Task {
            await checkViaStatus(tapes: tapes, api: api)
        }
    }

    /// Force-refresh (ignores cooldown). Use after a download/upload completes
    /// or when a push notification arrives.
    func refresh(tapes: [Tape], api: TapesAPIClient) {
        lastCheckDate = nil
        Task {
            await checkViaStatus(tapes: tapes, api: api)
        }
    }

    /// Awaitable refresh for callers that need to know when the check finishes
    /// (e.g. background push handlers that must defer their completionHandler).
    func refreshAndWait(tapes: [Tape], api: TapesAPIClient) async {
        lastCheckDate = nil
        await checkViaStatus(tapes: tapes, api: api)
    }

    /// Instant badge update from a push notification payload.
    /// Falls back to a full status check if the tape can't be matched locally.
    func updateFromPush(remoteTapeId: String, tapes: [Tape], api: TapesAPIClient) {
        if let tape = tapes.first(where: { $0.shareInfo?.remoteTapeId == remoteTapeId }) {
            let current = pendingDownloads[tape.id] ?? 0
            pendingDownloads[tape.id] = current + 1
            log.info("[SyncPush] bumped pending for tape=\(tape.id) remote=\(remoteTapeId) to \(current + 1)")
        }
        refresh(tapes: tapes, api: api)
    }

    /// Awaitable variant for background push handlers.
    func updateFromPushAndWait(remoteTapeId: String, tapes: [Tape], api: TapesAPIClient) async {
        if let tape = tapes.first(where: { $0.shareInfo?.remoteTapeId == remoteTapeId }) {
            let current = pendingDownloads[tape.id] ?? 0
            pendingDownloads[tape.id] = current + 1
            log.info("[SyncPush] bumped pending for tape=\(tape.id) remote=\(remoteTapeId) to \(current + 1)")
        }
        await refreshAndWait(tapes: tapes, api: api)
    }

    func clearDownload(for tapeId: UUID) {
        pendingDownloads.removeValue(forKey: tapeId)
    }

    // MARK: - Server-authoritative check

    private func checkViaStatus(tapes: [Tape], api: TapesAPIClient) async {
        let sharedTapes = tapes.filter { $0.shareInfo != nil }
        guard !sharedTapes.isEmpty else { return }

        let remoteTapeIds = sharedTapes.compactMap { $0.shareInfo?.remoteTapeId }
        guard !remoteTapeIds.isEmpty else { return }

        do {
            let serverPending = try await api.syncStatus(tapeIds: remoteTapeIds)

            for tape in sharedTapes {
                guard let remoteId = tape.shareInfo?.remoteTapeId else { continue }

                if let pending = serverPending[remoteId], pending > 0 {
                    pendingDownloads[tape.id] = pending
                    log.info("[SyncCheck] tape=\(tape.id) remote=\(remoteId) pending=\(pending)")
                } else {
                    pendingDownloads.removeValue(forKey: tape.id)
                }
            }
        } catch {
            log.warning("[SyncCheck] status check failed: \(error.localizedDescription)")
        }
    }
}
