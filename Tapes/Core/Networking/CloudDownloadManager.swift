import Foundation
import os

@MainActor
final class CloudDownloadManager: ObservableObject {

    enum DownloadState: Equatable {
        case idle
        case downloading(progress: Double)
        case completed(localURL: URL)
        case failed(String)
    }

    struct DownloadTask: Identifiable {
        let id: String
        let tapeId: String
        let clipId: String
        let cloudUrl: String
        let thumbnailUrl: String?
        let clipType: String
        var state: DownloadState = .idle
        var attempt: Int = 0
    }

    @Published private(set) var activeTasks: [DownloadTask] = []
    @Published private(set) var totalProgress: Double = 0

    private let api: TapesAPIClient
    private let log = Logger(subsystem: "com.studiomorph.tapes", category: "Download")
    private let maxRetries = 3
    private let session = URLSession.shared

    init(api: TapesAPIClient) {
        self.api = api
    }

    var hasActiveDownloads: Bool {
        activeTasks.contains { if case .downloading = $0.state { return true }; return false }
    }

    var isComplete: Bool {
        !activeTasks.isEmpty && activeTasks.allSatisfy {
            if case .completed = $0.state { return true }; return false
        }
    }

    // MARK: - Download Tape

    func downloadTape(tapeId: String, manifest: TapeManifest) {
        activeTasks.removeAll()

        for clip in manifest.clips {
            guard let cloudUrl = clip.cloudUrl else { continue }

            let task = DownloadTask(
                id: clip.clipId,
                tapeId: tapeId,
                clipId: clip.clipId,
                cloudUrl: cloudUrl,
                thumbnailUrl: clip.thumbnailUrl,
                clipType: clip.type
            )
            activeTasks.append(task)
        }

        for task in activeTasks {
            Task { await executeDownload(clipId: task.clipId) }
        }
    }

    // MARK: - Retry

    func retry(clipId: String) {
        guard let idx = activeTasks.firstIndex(where: { $0.clipId == clipId }) else { return }
        activeTasks[idx].state = .idle
        activeTasks[idx].attempt = 0
        Task { await executeDownload(clipId: clipId) }
    }

    func downloadNewClips(tapeId: String, clips: [ManifestClip]) {
        let existingIds = Set(activeTasks.map(\.clipId))
        for clip in clips {
            guard let cloudUrl = clip.cloudUrl, !existingIds.contains(clip.clipId) else { continue }
            let task = DownloadTask(
                id: clip.clipId,
                tapeId: tapeId,
                clipId: clip.clipId,
                cloudUrl: cloudUrl,
                thumbnailUrl: clip.thumbnailUrl,
                clipType: clip.type
            )
            activeTasks.append(task)
            Task { await executeDownload(clipId: task.clipId) }
        }
    }

    // MARK: - Cancel All

    func cancelAll() {
        activeTasks.removeAll()
        totalProgress = 0
    }

    // MARK: - Local URL

    func localURL(for clipId: String) -> URL? {
        guard let idx = activeTasks.firstIndex(where: { $0.clipId == clipId }),
              case .completed(let url) = activeTasks[idx].state else { return nil }
        return url
    }

    // MARK: - Execution

    private func executeDownload(clipId: String) async {
        guard let idx = activeTasks.firstIndex(where: { $0.clipId == clipId }) else { return }
        var task = activeTasks[idx]

        task.attempt += 1
        task.state = .downloading(progress: 0)
        activeTasks[idx] = task

        do {
            let cachedURL = Self.cacheURL(tapeId: task.tapeId, clipId: task.clipId, type: task.clipType)

            if FileManager.default.fileExists(atPath: cachedURL.path) {
                guard let idx = activeTasks.firstIndex(where: { $0.clipId == clipId }) else { return }
                activeTasks[idx].state = .completed(localURL: cachedURL)
                log.info("Cache hit for clip \(task.clipId)")
                confirmDownloadWithServer(tapeId: task.tapeId, clipId: task.clipId)
                updateTotalProgress()
                return
            }

            guard let downloadURL = URL(string: task.cloudUrl) else {
                throw APIError.validation("Invalid download URL.")
            }

            let request = URLRequest(url: downloadURL)
            let (tempURL, response) = try await session.download(for: request)

            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw APIError.server("Download failed with status \(code).")
            }

            let cacheDir = cachedURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: cachedURL.path) {
                try FileManager.default.removeItem(at: cachedURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: cachedURL)

            // Download thumbnail
            if let thumbUrlStr = task.thumbnailUrl, let thumbURL = URL(string: thumbUrlStr) {
                let thumbCacheURL = Self.thumbnailCacheURL(tapeId: task.tapeId, clipId: task.clipId)
                let thumbRequest = URLRequest(url: thumbURL)
                if let (thumbTemp, thumbResp) = try? await session.download(for: thumbRequest),
                   let thumbHttp = thumbResp as? HTTPURLResponse, (200...299).contains(thumbHttp.statusCode) {
                    if FileManager.default.fileExists(atPath: thumbCacheURL.path) {
                        try? FileManager.default.removeItem(at: thumbCacheURL)
                    }
                    try? FileManager.default.moveItem(at: thumbTemp, to: thumbCacheURL)
                }
            }

            guard let idx = activeTasks.firstIndex(where: { $0.clipId == clipId }) else { return }
            activeTasks[idx].state = .completed(localURL: cachedURL)
            log.info("Download complete for clip \(task.clipId)")

            confirmDownloadWithServer(tapeId: task.tapeId, clipId: task.clipId)

        } catch {
            log.error("Download failed for clip \(task.clipId): \(error.localizedDescription)")

            guard let idx = activeTasks.firstIndex(where: { $0.clipId == clipId }) else { return }

            if activeTasks[idx].attempt < maxRetries {
                let delay = pow(2.0, Double(self.activeTasks[idx].attempt))
                log.info("Retrying clip \(task.clipId) in \(delay)s (attempt \(self.activeTasks[idx].attempt + 1)/\(self.maxRetries))")
                try? await Task.sleep(for: .seconds(delay))
                await executeDownload(clipId: clipId)
            } else {
                activeTasks[idx].state = .failed(error.localizedDescription)
            }
        }

        updateTotalProgress()
    }

    private func confirmDownloadWithServer(tapeId: String, clipId: String) {
        Task {
            do {
                let _ = try await api.confirmDownload(tapeId: tapeId, clipId: clipId)
            } catch {
                log.warning("Failed to confirm download for clip \(clipId): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Cache Paths

    static func cacheDirectory(for tapeId: String) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("shared_tapes/\(tapeId)", isDirectory: true)
    }

    static func cacheURL(tapeId: String, clipId: String, type: String) -> URL {
        let ext: String
        switch type {
        case "video": ext = "mp4"
        case "live_photo": ext = "mov"
        default: ext = "jpg"
        }
        return cacheDirectory(for: tapeId).appendingPathComponent("\(clipId).\(ext)")
    }

    static func thumbnailCacheURL(tapeId: String, clipId: String) -> URL {
        cacheDirectory(for: tapeId).appendingPathComponent("\(clipId)_thumb.jpg")
    }

    static func clearCache(for tapeId: String) {
        let dir = cacheDirectory(for: tapeId)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Progress

    private func updateTotalProgress() {
        guard !activeTasks.isEmpty else {
            totalProgress = 0
            return
        }

        let sum = activeTasks.reduce(0.0) { acc, task in
            switch task.state {
            case .idle: return acc
            case .downloading(let p): return acc + p
            case .completed: return acc + 1.0
            case .failed: return acc
            }
        }
        totalProgress = sum / Double(activeTasks.count)
    }
}
