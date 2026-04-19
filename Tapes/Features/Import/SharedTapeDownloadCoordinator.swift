import Foundation
import Photos
import SwiftUI
import os

@MainActor
public class SharedTapeDownloadCoordinator: ObservableObject {

    @Published var isDownloading = false
    @Published var showProgressDialog = false
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
        showProgressDialog = true
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

                let tapeId = resolution.tapeId
                let session = URLSession.shared

                let existingTape = tapeStore.sharedTape(forRemoteId: tapeId)
                let isReturning = existingTape != nil

                self.log.info("[Download] shareId=\(shareId) tapeId=\(tapeId) manifestTotal=\(manifest.clips.count) withCloudUrl=\(uploadedClips.count) isReturning=\(isReturning)")

                if uploadedClips.isEmpty {
                    self.log.info("[Download] ABORT: uploadedClips is empty")
                    self.downloadError = isReturning
                        ? "Tape has no updates.\nAsk the Tapes owner to update tape and try again."
                        : "This tape is empty.\nAsk the Tapes owner to add content and try again."
                    self.isDownloading = false
                    self.showProgressDialog = false
                    return
                }

                let existingClipIds: Set<String>
                if let existing = existingTape {
                    existingClipIds = Set(existing.clips.map { $0.id.uuidString.lowercased() })
                    self.log.info("[Download] localClips=\(existingClipIds.count)")
                } else {
                    existingClipIds = []
                    self.log.info("[Download] no existing tape found for remoteTapeId=\(tapeId)")
                }

                let clipsToDownload = uploadedClips.filter { !existingClipIds.contains($0.clipId.lowercased()) }
                self.log.info("[Download] clipsToDownload=\(clipsToDownload.count)")

                if clipsToDownload.isEmpty && isReturning {
                    self.log.info("[Download] ABORT: clipsToDownload empty — all \(uploadedClips.count) server clips already in local tape")
                    let serverIds = Set(uploadedClips.map { $0.clipId.lowercased() })
                    let extraLocal = existingClipIds.subtracting(serverIds)
                    if !extraLocal.isEmpty {
                        self.log.info("[Download] local has \(extraLocal.count) clip(s) NOT on server")
                    }
                    self.downloadError = "Tape has no updates.\nAsk the Tapes owner to update tape and try again."
                    self.isDownloading = false
                    self.showProgressDialog = false
                    return
                }

                for clip in clipsToDownload {
                    self.log.info("[Download] will download: \(clip.clipId) type=\(clip.type) hasUrl=\(clip.cloudUrl != nil)")
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

                self.log.info("[Download] loop done: succeeded=\(clips.count) failed=\(self.failedCount) cancelled=\(Task.isCancelled)")

                guard !Task.isCancelled, !clips.isEmpty else {
                    self.log.info("[Download] ABORT after loop: clips empty, failed=\(self.failedCount)")
                    if self.failedCount > 0 {
                        self.downloadError = "\(self.failedCount) clip(s) failed to download.\nPlease try again later."
                    } else {
                        self.downloadError = isReturning
                            ? "Tape has no updates.\nAsk the Tapes owner to update tape and try again."
                            : "This tape is empty.\nAsk the Tapes owner to add content and try again."
                    }
                    self.isDownloading = false
                    self.showProgressDialog = false
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
        showProgressDialog = false
        totalCount = 0
        completedCount = 0
        failedCount = 0
        downloadError = nil
        resultTape = nil
        downloadTask = nil
    }

    func dismissProgressDialog() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showProgressDialog = false
        }
    }

    func showProgressDialogAgain() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showProgressDialog = true
        }
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

        let imageExt: String
        if isLivePhoto {
            imageExt = Self.detectImageExtension(at: tempURL)
        } else {
            imageExt = clipType == .video ? "mp4" : "jpg"
        }

        let stableURL = Self.stableTempURL(clipId: manifestClip.clipId, ext: imageExt)
        let stableDir = stableURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: stableDir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: stableURL.path) {
            try FileManager.default.removeItem(at: stableURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: stableURL)

        if isLivePhoto {
            log.info("[DownloadClip] \(manifestClip.clipId) detected image format: .\(imageExt)")
        }

        var movieStableURL: URL?
        if isLivePhoto, let movieUrlStr = manifestClip.livePhotoMovieUrl, let movieURL = URL(string: movieUrlStr) {
            log.info("[DownloadClip] \(manifestClip.clipId) downloading movie from \(movieUrlStr)")
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

            let movieSize = (try? FileManager.default.attributesOfItem(atPath: movieDest.path)[.size] as? Int) ?? 0
            log.info("[DownloadClip] \(manifestClip.clipId) movie saved: \(movieSize) bytes")
        } else if isLivePhoto {
            log.info("[DownloadClip] \(manifestClip.clipId) is live_photo but livePhotoMovieUrl=\(manifestClip.livePhotoMovieUrl ?? "nil")")
        }

        let imageSize = (try? FileManager.default.attributesOfItem(atPath: stableURL.path)[.size] as? Int) ?? 0
        log.info("[DownloadClip] \(manifestClip.clipId) image saved: \(imageSize) bytes, exists=\(FileManager.default.fileExists(atPath: stableURL.path))")

        let assetLocalId: String
        if isLivePhoto, let movieURL = movieStableURL {
            log.info("[DownloadClip] \(manifestClip.clipId) saving Live Photo — image=\(stableURL.lastPathComponent) movie=\(movieURL.lastPathComponent)")
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

    /// Reads the first bytes of a file to detect HEIC vs JPEG format.
    private static func detectImageExtension(at url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "jpg" }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 12), header.count >= 12 else { return "jpg" }

        // HEIC/HEIF: bytes 4-11 contain "ftypheic", "ftypheis", "ftypmif1", etc.
        if header.count >= 8 {
            let ftypRange = header[4..<8]
            if ftypRange.elementsEqual("ftyp".utf8) {
                return "heic"
            }
        }

        // JPEG: starts with FF D8 FF
        if header[0] == 0xFF, header[1] == 0xD8, header[2] == 0xFF {
            return "jpg"
        }

        // PNG: starts with 89 50 4E 47
        if header[0] == 0x89, header[1] == 0x50, header[2] == 0x4E, header[3] == 0x47 {
            return "png"
        }

        return "jpg"
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
        let log = Logger(subsystem: "com.studiomorph.tapes", category: "SharedDownload")

        let imageExists = FileManager.default.fileExists(atPath: imageURL.path)
        let movieExists = FileManager.default.fileExists(atPath: movieURL.path)
        let imageBytes = (try? FileManager.default.attributesOfItem(atPath: imageURL.path)[.size] as? Int) ?? 0
        let movieBytes = (try? FileManager.default.attributesOfItem(atPath: movieURL.path)[.size] as? Int) ?? 0

        log.info("[SaveLivePhoto] imageExists=\(imageExists) imageBytes=\(imageBytes) movieExists=\(movieExists) movieBytes=\(movieBytes)")

        if imageBytes == 0 {
            log.error("[SaveLivePhoto] image file is 0 bytes at \(imageURL.path)")
        }
        if movieBytes == 0 {
            log.error("[SaveLivePhoto] movie file is 0 bytes at \(movieURL.path)")
        }

        var placeholderId: String?

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()

            let imageOptions = PHAssetResourceCreationOptions()
            imageOptions.shouldMoveFile = false
            request.addResource(with: .photo, fileURL: imageURL, options: imageOptions)

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
