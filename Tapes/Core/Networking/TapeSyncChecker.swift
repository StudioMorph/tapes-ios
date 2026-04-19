import Foundation
import os

/// Checks server manifests for shared/collab tapes and computes
/// how many new clips are available to download.
///
/// Upload counts are computed reactively from the tape model
/// (see `Tape.pendingUploadCount` and `Clip.isSynced`).
@MainActor
public class TapeSyncChecker: ObservableObject {

    /// Maps tape ID → number of clips available to download.
    @Published var pendingDownloads: [UUID: Int] = [:]

    private var lastCheckDate: Date?

    /// Minimum interval between automatic checks.
    static var checkInterval: TimeInterval = 60

    private let log = Logger(subsystem: "com.studiomorph.tapes", category: "SyncChecker")

    /// Runs a lightweight manifest check for all shared tapes.
    /// Respects the `checkInterval` cooldown to avoid excessive network calls.
    func checkAll(tapes: [Tape], api: TapesAPIClient) {
        if let last = lastCheckDate, Date().timeIntervalSince(last) < Self.checkInterval {
            return
        }
        lastCheckDate = Date()

        Task {
            await checkDownloads(tapes: tapes, api: api)
        }
    }

    /// Force-refresh (ignores cooldown). Use after a download/upload completes.
    func refresh(tapes: [Tape], api: TapesAPIClient) {
        lastCheckDate = nil
        checkAll(tapes: tapes, api: api)
    }

    func clearDownload(for tapeId: UUID) {
        pendingDownloads.removeValue(forKey: tapeId)
    }

    // MARK: - Downloads (shared tapes with new server clips)

    private func checkDownloads(tapes: [Tape], api: TapesAPIClient) async {
        let sharedTapes = tapes.filter { $0.shareInfo != nil }

        for tape in sharedTapes {
            guard let remoteTapeId = tape.shareInfo?.remoteTapeId else { continue }

            do {
                let manifest = try await api.getManifest(tapeId: remoteTapeId)
                let serverClipIds = Set(manifest.clips.filter { $0.cloudUrl != nil }.map { $0.clipId.lowercased() })
                let localClipIds = Set(tape.clips.map { $0.id.uuidString.lowercased() })
                let missing = serverClipIds.subtracting(localClipIds)
                let newCount = missing.count

                log.info("[SyncCheck] tape=\(tape.id) remote=\(remoteTapeId) server=\(serverClipIds.count) local=\(localClipIds.count) missing=\(newCount)")
                if newCount > 0 {
                    for clipId in missing {
                        log.info("[SyncCheck]   missing clip: \(clipId)")
                    }
                    pendingDownloads[tape.id] = newCount
                } else {
                    pendingDownloads.removeValue(forKey: tape.id)
                }
            } catch {
                log.warning("Manifest check failed for \(remoteTapeId): \(error.localizedDescription)")
            }
        }
    }
}
