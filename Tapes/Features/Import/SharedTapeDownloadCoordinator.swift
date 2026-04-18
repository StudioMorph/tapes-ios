import Foundation
import Photos
import UIKit
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

                if resolution.userRole == "owner" {
                    self.downloadError = "This is your tape.\nIt already exists on your device."
                    self.isDownloading = false
                    return
                }

                let manifest = try await api.getManifest(tapeId: resolution.tapeId)

                let uploadedClips = manifest.clips.filter { $0.cloudUrl != nil }

                let tapeId = resolution.tapeId
                let session = URLSession.shared

                let existingTape = tapeStore.sharedTape(forRemoteId: tapeId)
                let isReturning = existingTape != nil

                if uploadedClips.isEmpty {
                    self.downloadError = isReturning
                        ? "Tape has no updates.\nAsk the Tapes owner to update tape and try again."
                        : "This tape is empty.\nAsk the Tapes owner to add content and try again."
                    self.isDownloading = false
                    return
                }

                let existingClipIds: Set<String>
                if let existing = existingTape {
                    existingClipIds = Set(existing.clips.map { $0.id.uuidString.lowercased() })
                } else {
                    existingClipIds = []
                }

                let clipsToDownload = uploadedClips.filter { !existingClipIds.contains($0.clipId.lowercased()) }

                if clipsToDownload.isEmpty && isReturning {
                    self.downloadError = "Tape has no updates.\nAsk the Tapes owner to update tape and try again."
                    self.isDownloading = false
                    return
                }

                self.totalCount = clipsToDownload.count
                var clips: [Clip] = []

                for manifestClip in clipsToDownload {
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
                    self.downloadError = isReturning
                        ? "Tape has no updates.\nAsk the Tapes owner to update tape and try again."
                        : "This tape is empty.\nAsk the Tapes owner to add content and try again."
                    self.isDownloading = false
                    return
                }

                if existingTape != nil {
                    tapeStore.mergeClipsIntoSharedTape(remoteTapeId: tapeId, newClips: clips)
                    if let updated = tapeStore.sharedTape(forRemoteId: tapeId) {
                        tapeStore.associateClipsWithAlbum(tapeID: updated.id, clips: clips)
                        self.resultTape = updated
                    }
                } else {
                    // The link's role (view vs collaborate) takes precedence
                    // over the tape-level mode so view-only links to a
                    // collaborative tape still land the recipient in the
                    // Viewing segment.
                    let resolvedMode: String = {
                        if let access = resolution.accessMode {
                            return access == "collaborate" ? "collaborative" : "view_only"
                        }
                        return manifest.mode
                    }()

                    let tape = Self.buildTape(
                        from: manifest,
                        clips: clips,
                        shareId: shareId,
                        ownerName: resolution.ownerName,
                        mode: resolvedMode
                    )
                    tapeStore.addSharedTape(tape)
                    tapeStore.associateClipsWithAlbum(tapeID: tape.id, clips: clips)
                    self.resultTape = tape
                }

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
        guard let cloudUrl = manifestClip.cloudUrl, let downloadURL = URL(string: cloudUrl) else {
            throw APIError.validation("Invalid download URL.")
        }

        let (tempURL, response) = try await session.download(for: URLRequest(url: downloadURL))
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIError.server("Download failed (HTTP \(code)).")
        }

        let isLivePhoto = manifestClip.isLivePhoto
        let clipType: ClipType = isLivePhoto ? .image : ((manifestClip.type == "photo" || manifestClip.type == "image") ? .image : .video)

        let stableURL = Self.stableTempURL(clipId: manifestClip.clipId, ext: isLivePhoto ? "jpg" : (clipType == .video ? "mp4" : "jpg"))
        let stableDir = stableURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: stableDir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: stableURL.path) {
            try FileManager.default.removeItem(at: stableURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: stableURL)

        var movieStableURL: URL?
        if isLivePhoto, let movieUrlStr = manifestClip.livePhotoMovieUrl, let movieURL = URL(string: movieUrlStr) {
            let (movieTempURL, movieResp) = try await session.download(for: URLRequest(url: movieURL))
            guard let movieHttp = movieResp as? HTTPURLResponse, (200...299).contains(movieHttp.statusCode) else {
                let code = (movieResp as? HTTPURLResponse)?.statusCode ?? 0
                throw APIError.server("Live Photo movie download failed (HTTP \(code)).")
            }
            let movieDest = Self.stableTempURL(clipId: manifestClip.clipId, ext: "mov")
            if FileManager.default.fileExists(atPath: movieDest.path) {
                try FileManager.default.removeItem(at: movieDest)
            }
            try FileManager.default.moveItem(at: movieTempURL, to: movieDest)
            movieStableURL = movieDest
        }

        let assetLocalId: String
        if isLivePhoto, let movieURL = movieStableURL {
            assetLocalId = try await Self.saveLivePhotoToLibrary(imageURL: stableURL, movieURL: movieURL)
            try? FileManager.default.removeItem(at: movieURL)
        } else {
            assetLocalId = try await Self.saveToPhotosLibrary(fileURL: stableURL, clipType: clipType)
        }

        try? FileManager.default.removeItem(at: stableURL)

        Task {
            try? await api.confirmDownload(tapeId: tapeId, clipId: manifestClip.clipId)
        }

        var thumbData: Data?
        if clipType == .image, let image = Self.loadImageFromPhotos(assetLocalId: assetLocalId) {
            thumbData = image.preparingThumbnail(of: CGSize(width: 480, height: 480))?.jpegData(compressionQuality: 0.8)
        } else if let thumbUrlStr = manifestClip.thumbnailUrl, let thumbURL = URL(string: thumbUrlStr) {
            if let (thumbTemp, thumbResp) = try? await session.download(for: URLRequest(url: thumbURL)),
               let thumbHttp = thumbResp as? HTTPURLResponse, (200...299).contains(thumbHttp.statusCode),
               let data = try? Data(contentsOf: thumbTemp) {
                thumbData = data
            }
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
            assetLocalId: assetLocalId,
            clipType: clipType,
            duration: Double(manifestClip.durationMs) / 1000.0,
            thumbnail: thumbData,
            rotateQuarterTurns: manifestClip.rotateQuarterTurns ?? 0,
            overrideScaleMode: scaleMode,
            trimStart: Double(manifestClip.trimStartMs ?? 0) / 1000.0,
            trimEnd: Double(manifestClip.trimEndMs ?? 0) / 1000.0,
            motionStyle: motion,
            imageDuration: manifestClip.imageDurationMs.map { Double($0) / 1000.0 } ?? 4.0,
            isLivePhoto: isLivePhoto,
            livePhotoAsVideo: manifestClip.livePhotoAsVideo,
            livePhotoMuted: isLivePhoto ? !(manifestClip.livePhotoSound ?? true) : nil,
            volume: manifestClip.audioLevel,
            isSynced: true
        )
    }

    // MARK: - Photos Library

    private static func stableTempURL(clipId: String, ext: String) -> URL {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("shared_downloads", isDirectory: true)
        return tmp.appendingPathComponent("\(clipId).\(ext)")
    }

    private static func saveToPhotosLibrary(fileURL: URL, clipType: ClipType) async throws -> String {
        var placeholderId: String?

        try await PHPhotoLibrary.shared().performChanges {
            let request: PHAssetChangeRequest?
            if clipType == .video {
                request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            } else {
                guard let image = UIImage(contentsOfFile: fileURL.path) else {
                    return
                }
                request = PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            placeholderId = request?.placeholderForCreatedAsset?.localIdentifier
        }

        guard let assetId = placeholderId else {
            throw APIError.server("Failed to save media to Photos library.")
        }
        return assetId
    }

    private static func saveLivePhotoToLibrary(imageURL: URL, movieURL: URL) async throws -> String {
        var placeholderId: String?

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()

            let imageData = try? Data(contentsOf: imageURL)
            if let imageData {
                request.addResource(with: .photo, data: imageData, options: nil)
            }

            let movieOptions = PHAssetResourceCreationOptions()
            movieOptions.shouldMoveFile = false
            request.addResource(with: .pairedVideo, fileURL: movieURL, options: movieOptions)

            placeholderId = request.placeholderForCreatedAsset?.localIdentifier
        }

        guard let assetId = placeholderId else {
            throw APIError.server("Failed to save Live Photo to Photos library.")
        }
        return assetId
    }

    private static func loadImageFromPhotos(assetLocalId: String) -> UIImage? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetLocalId], options: nil)
        guard let asset = fetch.firstObject else { return nil }

        var result: UIImage?
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 480, height: 480),
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            result = image
        }
        return result
    }

    // MARK: - Build Tape

    private static func buildTape(
        from manifest: TapeManifest,
        clips: [Clip],
        shareId: String,
        ownerName: String?,
        mode: String? = nil
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
            mode: mode ?? manifest.mode,
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
