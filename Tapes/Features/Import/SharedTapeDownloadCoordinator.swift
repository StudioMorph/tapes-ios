import Foundation
import Photos
import SwiftUI
import BackgroundTasks
import AudioToolbox
import UserNotifications
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
    @Published private(set) var resolvedMode: String?
    private let log = Logger(subsystem: "com.studiomorph.tapes", category: "SharedDownload")

    

    /// When `true`, an external coordinator (e.g. `CollabSyncCoordinator`)
    /// owns the UI lifecycle. Dialog flags, completion feedback, and
    /// `BGContinuedProcessingTask` submission are suppressed.
    var isManagedBySync = false

    // MARK: - Background Task Support

    static let bgTaskIdentifier = "StudioMorph.Tapes.download"
    static weak var current: SharedTapeDownloadCoordinator?

    private var _continuedTask: AnyObject?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var downloadStartTime: Date?

    @available(iOS 26, *)
    private var continuedTask: BGContinuedProcessingTask? {
        get { _continuedTask as? BGContinuedProcessingTask }
        set { _continuedTask = newValue }
    }

    init() {
        Self.current = self
    }

    @available(iOS 26, *)
    static func registerBackgroundDownloadHandler() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: bgTaskIdentifier,
            using: .main
        ) { task in
            guard let task = task as? BGContinuedProcessingTask else { return }
            task.progress.totalUnitCount = 100

            current?._continuedTask = task
            task.expirationHandler = {
                Task { @MainActor in
                    current?.handleBackgroundTaskExpiration()
                }
            }
        }
    }

    var processedCount: Int { completedCount + failedCount }

    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(processedCount) / Double(totalCount)
    }

    var progressLabel: String {
        if completedCount == 0 && failedCount == 0 {
            return "Preparing…"
        }
        return "Downloading \(processedCount)/\(totalCount)"
    }

    var formattedTimeRemaining: String? {
        guard let startTime = downloadStartTime, progress > 0.05 else { return nil }
        let elapsed = Date().timeIntervalSince(startTime)
        let estimatedTotal = elapsed / progress
        let remaining = estimatedTotal - elapsed
        guard remaining > 0 && remaining < 3600 else { return nil }

        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s remaining"
        }
        return "\(seconds)s remaining"
    }

    func startDownload(
        shareId: String,
        api: TapesAPIClient,
        tapeStore: TapesStore
    ) {
        guard !isDownloading else { return }

        isDownloading = true
        if !isManagedBySync { showProgressDialog = true }
        totalCount = 0
        completedCount = 0
        failedCount = 0
        downloadError = nil
        resultTape = nil
        resolvedMode = nil
        downloadStartTime = Date()

        if !isManagedBySync, #available(iOS 26, *) {
            submitContinuedProcessingTask()
        }

        downloadTask = Task { [weak self] in
            guard let self else { return }

            do {
                let resolution = try await api.resolveShare(shareId: shareId)

                let earlyMode: String? = {
                    if let access = resolution.accessMode {
                        return access == "collaborate" ? "collaborative" : "view_only"
                    }
                    return nil
                }()
                self.resolvedMode = earlyMode

                let manifest = try await api.getManifest(tapeId: resolution.tapeId)
                if earlyMode == nil {
                    self.resolvedMode = manifest.mode
                }

                let uploadedClips = manifest.clips.filter { $0.cloudUrl != nil }

                let tapeId = resolution.tapeId

                let existingTape = tapeStore.sharedTape(forRemoteId: tapeId)
                let isReturning = existingTape != nil

                self.log.info("[Download] shareId=\(shareId) tapeId=\(tapeId) manifestTotal=\(manifest.clips.count) withCloudUrl=\(uploadedClips.count) isReturning=\(isReturning)")

                if uploadedClips.isEmpty {
                    self.log.info("[Download] ABORT: uploadedClips is empty")
                    self.downloadError = isReturning
                        ? "Tape has no updates.\nAsk the Tapes owner to update tape and try again."
                        : "This tape is empty.\nAsk the Tapes owner to add content and try again."
                    self.finishDownload(success: false)
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
                    self.finishDownload(success: false)
                    self.showProgressDialog = false
                    return
                }

                for clip in clipsToDownload {
                    self.log.info("[Download] will download: \(clip.clipId) type=\(clip.type) hasUrl=\(clip.cloudUrl != nil)")
                }

                self.totalCount = clipsToDownload.count

                // Download all clips concurrently — each downloadClip call creates
                // a background URLSession task immediately. All tasks are queued with
                // the OS daemon before any of them complete.
                var clips: [Clip] = []

                await withTaskGroup(of: (ManifestClip, Result<Clip, Error>).self) { group in
                    for manifestClip in clipsToDownload {
                        group.addTask { [weak self] in
                            guard let self else {
                                return (manifestClip, .failure(APIError.validation("Coordinator deallocated")))
                            }
                            do {
                                let clip = try await self.downloadClip(manifestClip, tapeId: tapeId, api: api)
                                return (manifestClip, .success(clip))
                            } catch {
                                return (manifestClip, .failure(error))
                            }
                        }
                    }

                    for await (manifestClip, result) in group {
                        switch result {
                        case .success(let clip):
                            clips.append(clip)
                            self.completedCount += 1
                        case .failure(let error):
                            self.log.error("Failed to download clip \(manifestClip.clipId): \(error.localizedDescription)")
                            self.failedCount += 1
                        }

                        if #available(iOS 26, *) {
                            self.updateContinuedTaskProgress()
                        }
                    }
                }

                self.log.info("[Download] done: succeeded=\(clips.count) failed=\(self.failedCount) cancelled=\(Task.isCancelled)")

                guard !Task.isCancelled, !clips.isEmpty else {
                    self.log.info("[Download] ABORT after process: clips empty, failed=\(self.failedCount)")
                    if self.failedCount > 0 {
                        self.downloadError = "\(self.failedCount) clip(s) failed to download.\nPlease try again later."
                    } else {
                        self.downloadError = isReturning
                            ? "Tape has no updates.\nAsk the Tapes owner to update tape and try again."
                            : "This tape is empty.\nAsk the Tapes owner to add content and try again."
                    }
                    self.finishDownload(success: false)
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

                self.finishDownload(success: true)

            } catch {
                self.log.error("Share resolution failed: \(error.localizedDescription)")
                self.downloadError = error.localizedDescription
                self.finishDownload(success: false)
            }
        }
    }

    private func finishDownload(success: Bool) {
        isDownloading = false
        endBackgroundTask()

        if !isManagedBySync, #available(iOS 26, *) {
            completeContinuedTask(success: success)
        }

        if success && !isManagedBySync {
            playCompletionFeedback()
            if UIApplication.shared.applicationState != .active {
                sendCompletionNotification()
            }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        BackgroundTransferManager.shared.cancelAllTasks()
        finishDownload(success: false)
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
        api: TapesAPIClient
    ) async throws -> Clip {
        guard let cloudUrl = manifestClip.cloudUrl, let downloadURL = URL(string: cloudUrl) else {
            throw APIError.validation("Invalid download URL.")
        }

        let bgTempURL = try await BackgroundTransferManager.shared.downloadFile(from: downloadURL)

        let isLivePhoto = manifestClip.isLivePhoto
        let clipType: ClipType = isLivePhoto ? .image : ((manifestClip.type == "photo" || manifestClip.type == "image") ? .image : .video)

        let imageExt: String
        if isLivePhoto {
            imageExt = Self.detectImageExtension(at: bgTempURL)
        } else {
            imageExt = clipType == .video ? "mp4" : "jpg"
        }

        let stableURL = Self.stableTempURL(clipId: manifestClip.clipId, ext: imageExt)
        let stableDir = stableURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: stableDir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: stableURL.path) {
            try FileManager.default.removeItem(at: stableURL)
        }
        try FileManager.default.moveItem(at: bgTempURL, to: stableURL)

        var movieStableURL: URL?
        if isLivePhoto, let movieUrlStr = manifestClip.livePhotoMovieUrl, let movieURL = URL(string: movieUrlStr) {
            let movieBgTemp = try await BackgroundTransferManager.shared.downloadFile(from: movieURL)
            let movieDest = Self.stableTempURL(clipId: manifestClip.clipId, ext: "mov")
            if FileManager.default.fileExists(atPath: movieDest.path) {
                try FileManager.default.removeItem(at: movieDest)
            }
            try FileManager.default.moveItem(at: movieBgTemp, to: movieDest)
            movieStableURL = movieDest
        }

        let assetLocalId: String
        if isLivePhoto, let movieURL = movieStableURL {
            do {
                assetLocalId = try await Self.saveLivePhotoToLibrary(imageURL: stableURL, movieURL: movieURL)
            } catch {
                assetLocalId = try await Self.saveToPhotosLibrary(fileURL: stableURL, clipType: .image)
            }
            try? FileManager.default.removeItem(at: movieURL)
        } else {
            assetLocalId = try await Self.saveToPhotosLibrary(fileURL: stableURL, clipType: clipType)
        }

        try? FileManager.default.removeItem(at: stableURL)

        Task {
            try? await api.confirmDownload(tapeId: tapeId, clipId: manifestClip.clipId)
        }

        var thumbData: Data?
        if clipType == .image, let image = await Self.loadImageFromPhotos(assetLocalId: assetLocalId) {
            thumbData = image.preparingThumbnail(of: CGSize(width: 480, height: 480))?.jpegData(compressionQuality: 0.8)
        } else if let thumbUrlStr = manifestClip.thumbnailUrl, let thumbURL = URL(string: thumbUrlStr) {
            if let thumbTemp = try? await BackgroundTransferManager.shared.downloadFile(from: thumbURL),
               let data = try? Data(contentsOf: thumbTemp) {
                thumbData = data
                try? FileManager.default.removeItem(at: thumbTemp)
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

    private static func loadImageFromPhotos(assetLocalId: String) async -> UIImage? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetLocalId], options: nil)
        guard let asset = fetch.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 480, height: 480),
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !isDegraded else { return }
                continuation.resume(returning: image)
            }
        }
    }

    // MARK: - Scene Phase

    func handleScenePhaseChange(_ phase: ScenePhase) {
        if phase == .background && isDownloading {
            beginBackgroundTask()
        }
    }

    // MARK: - BGContinuedProcessingTask Lifecycle

    @available(iOS 26, *)
    private func submitContinuedProcessingTask() {
        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.bgTaskIdentifier,
            title: "Downloading Tape",
            subtitle: "Starting…"
        )
        request.strategy = .fail

        do {
            try BGTaskScheduler.shared.submit(request)
            log.info("BGContinuedProcessingTask submitted for download")
        } catch {
            log.error("BGContinuedProcessingTask submit failed: \(error.localizedDescription)")
            beginBackgroundTask()
        }
    }

    @available(iOS 26, *)
    private func completeContinuedTask(success: Bool) {
        guard let task = continuedTask else { return }
        task.progress.completedUnitCount = 100
        task.setTaskCompleted(success: success)
        self.continuedTask = nil
    }

    @available(iOS 26, *)
    private func updateContinuedTaskProgress() {
        guard let task = continuedTask else { return }
        task.progress.completedUnitCount = Int64(progress * 100)
        let subtitle = formattedTimeRemaining ?? progressLabel
        task.updateTitle("Downloading Tape", subtitle: subtitle)
    }

    private func handleBackgroundTaskExpiration() {
        if #available(iOS 26, *) {
            continuedTask?.updateTitle("Downloading Tape", subtitle: "Continuing in background…")
            continuedTask?.setTaskCompleted(success: true)
            continuedTask = nil
        }
        beginBackgroundTask()
    }

    // MARK: - Background Task (fallback)

    private func beginBackgroundTask() {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            Task { @MainActor in self?.endBackgroundTask() }
        }
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    // MARK: - Completion Feedback

    private func playCompletionFeedback() {
        AudioServicesPlaySystemSound(1007)
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.prepare()
        gen.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            gen.impactOccurred()
        }
    }

    private func sendCompletionNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Tape Downloaded"
        content.body = "Your shared tape has been downloaded successfully."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let id = "download-complete-\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
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
