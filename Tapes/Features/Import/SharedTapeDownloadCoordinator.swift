import Foundation
import os

@MainActor
public class SharedTapeDownloadCoordinator: ObservableObject {

    @Published var isDownloading = false
    @Published var totalCount = 0
    @Published var completedCount = 0
    @Published var failedCount = 0
    @Published var downloadError: String?

    private var downloadTask: Task<Void, Never>?
    @Published private(set) var resultTape: Tape?
    private let log = Logger(subsystem: "com.studiomorph.tapes", category: "SharedDownload")

    var processedCount: Int { completedCount + failedCount }

    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(processedCount) / Double(totalCount)
    }

    var progressLabel: String {
        "Downloading \(processedCount)/\(totalCount)"
    }

    func startDownload(
        shareId: String,
        api: TapesAPIClient,
        tapeStore: TapesStore
    ) {
        guard !isDownloading else { return }

        isDownloading = true
        totalCount = 0
        completedCount = 0
        failedCount = 0
        downloadError = nil
        resultTape = nil

        downloadTask = Task { [weak self] in
            guard let self else { return }

            do {
                let resolution = try await api.resolveShare(shareId: shareId)
                let manifest = try await api.getManifest(tapeId: resolution.tapeId)

                let uploadedClips = manifest.clips.filter { $0.cloudUrl != nil }
                self.totalCount = uploadedClips.count

                if uploadedClips.isEmpty {
                    self.downloadError = "This tape has no clips yet."
                    self.isDownloading = false
                    return
                }

                let tapeId = resolution.tapeId
                var clips: [Clip] = []
                let session = URLSession.shared

                for manifestClip in uploadedClips {
                    guard !Task.isCancelled else { break }

                    do {
                        let clip = try await self.downloadClip(
                            manifestClip,
                            tapeId: tapeId,
                            session: session,
                            api: api
                        )
                        clips.append(clip)
                        self.completedCount += 1
                    } catch {
                        self.log.error("Failed to download clip \(manifestClip.clipId): \(error.localizedDescription)")
                        self.failedCount += 1
                    }
                }

                guard !Task.isCancelled, !clips.isEmpty else {
                    if clips.isEmpty {
                        self.downloadError = "All clips failed to download."
                    }
                    self.isDownloading = false
                    return
                }

                let tape = Self.buildTape(
                    from: manifest,
                    clips: clips,
                    shareId: shareId,
                    ownerName: resolution.ownerName
                )

                tapeStore.addSharedTape(tape)
                self.resultTape = tape
                self.isDownloading = false

            } catch {
                self.log.error("Share resolution failed: \(error.localizedDescription)")
                self.downloadError = error.localizedDescription
                self.isDownloading = false
            }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        reset()
    }

    func consumeResult() -> Tape? {
        let tape = resultTape
        resultTape = nil
        return tape
    }

    func reset() {
        isDownloading = false
        totalCount = 0
        completedCount = 0
        failedCount = 0
        downloadError = nil
        resultTape = nil
        downloadTask = nil
    }

    // MARK: - Single Clip Download

    private func downloadClip(
        _ manifestClip: ManifestClip,
        tapeId: String,
        session: URLSession,
        api: TapesAPIClient
    ) async throws -> Clip {
        let cachedURL = CloudDownloadManager.cacheURL(
            tapeId: tapeId,
            clipId: manifestClip.clipId,
            type: manifestClip.type
        )

        if !FileManager.default.fileExists(atPath: cachedURL.path) {
            guard let cloudUrl = manifestClip.cloudUrl, let downloadURL = URL(string: cloudUrl) else {
                throw APIError.validation("Invalid download URL.")
            }

            let (tempURL, response) = try await session.download(for: URLRequest(url: downloadURL))
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw APIError.server("Download failed (HTTP \(code)).")
            }

            let cacheDir = cachedURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: cachedURL.path) {
                try FileManager.default.removeItem(at: cachedURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: cachedURL)
        }

        // Download thumbnail
        var thumbData: Data?
        if let thumbUrlStr = manifestClip.thumbnailUrl, let thumbURL = URL(string: thumbUrlStr) {
            let thumbCacheURL = CloudDownloadManager.thumbnailCacheURL(tapeId: tapeId, clipId: manifestClip.clipId)
            if FileManager.default.fileExists(atPath: thumbCacheURL.path) {
                thumbData = try? Data(contentsOf: thumbCacheURL)
            } else {
                if let (thumbTemp, thumbResp) = try? await session.download(for: URLRequest(url: thumbURL)),
                   let thumbHttp = thumbResp as? HTTPURLResponse, (200...299).contains(thumbHttp.statusCode) {
                    try? FileManager.default.createDirectory(at: thumbCacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? FileManager.default.moveItem(at: thumbTemp, to: thumbCacheURL)
                    thumbData = try? Data(contentsOf: thumbCacheURL)
                }
            }
        }

        // Confirm download with server
        Task {
            try? await api.confirmDownload(tapeId: tapeId, clipId: manifestClip.clipId)
        }

        let clipType: ClipType = (manifestClip.type == "photo" || manifestClip.type == "image") ? .image : .video
        var imageData: Data?
        if clipType == .image {
            imageData = try? Data(contentsOf: cachedURL)
        }

        let motion: MotionStyle = {
            if let raw = manifestClip.motionStyle, let style = MotionStyle(rawValue: raw) {
                return style
            }
            return .kenBurns
        }()

        let scaleMode: ScaleMode? = {
            if let raw = manifestClip.overrideScaleMode {
                return ScaleMode(rawValue: raw)
            }
            return nil
        }()

        return Clip(
            id: UUID(uuidString: manifestClip.clipId) ?? UUID(),
            localURL: clipType == .video ? cachedURL : nil,
            imageData: imageData,
            clipType: clipType,
            duration: Double(manifestClip.durationMs) / 1000.0,
            thumbnail: thumbData,
            rotateQuarterTurns: manifestClip.rotateQuarterTurns ?? 0,
            overrideScaleMode: scaleMode,
            trimStart: Double(manifestClip.trimStartMs ?? 0) / 1000.0,
            trimEnd: Double(manifestClip.trimEndMs ?? 0) / 1000.0,
            motionStyle: motion,
            imageDuration: manifestClip.imageDurationMs.map { Double($0) / 1000.0 } ?? 4.0,
            volume: manifestClip.audioLevel,
            isSynced: true
        )
    }

    // MARK: - Build Tape

    private static func buildTape(
        from manifest: TapeManifest,
        clips: [Clip],
        shareId: String,
        ownerName: String?
    ) -> Tape {
        let transitionType: TransitionType
        if let t = manifest.tapeSettings.transition?.type {
            transitionType = TransitionType(rawValue: t) ?? .none
        } else {
            transitionType = .none
        }

        let transitionDuration: Double
        if let ms = manifest.tapeSettings.transition?.durationMs {
            transitionDuration = Double(ms) / 1000.0
        } else {
            transitionDuration = 0.5
        }

        var expiresAt: Date?
        if let expiryStr = manifest.expiresAt {
            expiresAt = ISO8601DateFormatter().date(from: expiryStr)
        }

        let info = ShareInfo(
            shareId: shareId,
            ownerName: ownerName ?? manifest.ownerName,
            mode: manifest.mode,
            expiresAt: expiresAt,
            remoteTapeId: manifest.tapeId
        )

        return Tape(
            title: manifest.title,
            transition: transitionType,
            transitionDuration: transitionDuration,
            clips: clips,
            hasReceivedFirstContent: true,
            shareInfo: info
        )
    }
}
