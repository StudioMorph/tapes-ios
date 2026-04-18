import Foundation
import os

/// Checks server manifests for collaborative tapes and computes
/// how many new clips are available to download. Also tracks
/// how many local clips on view-only shared tapes need uploading.
@MainActor
public class TapeSyncChecker: ObservableObject {

    /// Maps tape ID → number of clips available to download.
    @Published var pendingDownloads: [UUID: Int] = [:]

    /// Maps tape ID → number of local clips not yet uploaded.
    @Published var pendingUploads: [UUID: Int] = [:]

    private var lastCheckDate: Date?
    private static let cooldown: TimeInterval = 300

    private let log = Logger(subsystem: "com.studiomorph.tapes", category: "SyncChecker")

    /// Runs a lightweight manifest check for all shared tapes.
    /// Respects a 5-minute cooldown to avoid excessive network calls.
    func checkAll(tapes: [Tape], api: TapesAPIClient) {
        if let last = lastCheckDate, Date().timeIntervalSince(last) < Self.cooldown {
            return
        }
        lastCheckDate = Date()

        Task {
            await checkDownloads(tapes: tapes, api: api)
            checkUploads(tapes: tapes)
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

    func clearUpload(for tapeId: UUID) {
        pendingUploads.removeValue(forKey: tapeId)
    }

    // MARK: - Downloads (collaborative tapes with new server clips)

    private func checkDownloads(tapes: [Tape], api: TapesAPIClient) async {
        let collabTapes = tapes.filter { $0.shareInfo?.mode == "collaborative" }

        for tape in collabTapes {
            guard let remoteTapeId = tape.shareInfo?.remoteTapeId else { continue }

            do {
                let manifest = try await api.getManifest(tapeId: remoteTapeId)
                let serverClipIds = Set(manifest.clips.filter { $0.cloudUrl != nil }.map { $0.clipId.lowercased() })
                let localClipIds = Set(tape.clips.map { $0.id.uuidString.lowercased() })
                let newCount = serverClipIds.subtracting(localClipIds).count

                if newCount > 0 {
                    pendingDownloads[tape.id] = newCount
                } else {
                    pendingDownloads.removeValue(forKey: tape.id)
                }
            } catch {
                log.warning("Manifest check failed for \(remoteTapeId): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Uploads (view-only tapes with unsynced local content)

    private func checkUploads(tapes: [Tape]) {
        let myTapes = tapes.filter { $0.shareInfo == nil }

        for tape in myTapes {
            let delta = tape.pendingUploadCount
            if delta > 0 {
                pendingUploads[tape.id] = delta
            } else {
                pendingUploads.removeValue(forKey: tape.id)
            }
        }
    }
}
