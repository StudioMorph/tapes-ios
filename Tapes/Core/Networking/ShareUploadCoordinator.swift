import Foundation
import SwiftUI
import Photos
import AVFoundation
import UserNotifications
import AudioToolbox
import BackgroundTasks
import os

/// Coordinates background uploads for the share flow.
///
/// Upload semantics (4-link model):
///   • A tape only needs to be uploaded once. Any share action (copy link,
///     share sheet, send first invite) on a tape whose clips have not yet
///     been uploaded triggers `ensureTapeUploaded`.
///   • `ensureTapeUploaded` is idempotent: if the server reports
///     `clips_uploaded == true`, we just cache the response and return.
///   • `contributeClips` uploads unsynced clips on a shared-collab tape.
@MainActor
public class ShareUploadCoordinator: ObservableObject {

    // MARK: - Published State

    @Published var isUploading = false
    @Published var totalClips = 0
    @Published var completedClips = 0
    @Published var failedClipIndices: Set<Int> = []
    @Published var statusMessage = ""
    @Published var showProgressDialog = false
    @Published var showCompletionDialog = false
    @Published var uploadError: String?

    // MARK: - Result (available after success)

    /// Whether the most recent upload was for a collaborative share.
    @Published var resultMode: ShareMode = .viewing
    @Published var resultRemoteTapeId: String?
    @Published var resultCreateResponse: TapesAPIClient.CreateTapeResponse?
    /// Count of local (non-placeholder) clips after the last successful upload.
    @Published var lastUploadedClipCount: Int?
    /// IDs of local clips that are confirmed present on the server after the
    /// last successful upload. Observers (TapesListView, CollabTapesView) mark
    /// each one `isSynced = true` on the local tape, so subsequent contribute
    /// flows don't try to re-upload already-synced clips.
    @Published var lastSyncedClipIds: [UUID] = []

    /// Set when the user dismisses the share modal while an upload is in
    /// progress. The upload continues in the background; when it finishes
    /// this triggers the post-upload "Link ready to share" dialog instead
    /// of opening the share sheet inside the (now-closed) modal.
    @Published var userDismissedModal = false

    /// Share URL available after a successful upload for the post-modal
    /// completion dialog. Set by the `onCompleted` callback when the modal
    /// was dismissed mid-upload.
    @Published var completedShareURL: URL?

    /// Show the post-modal "Link ready to share" dialog on the main view.
    @Published var showPostUploadDialog = false

    /// When `true`, an external coordinator (e.g. `CollabSyncCoordinator`)
    /// owns the UI lifecycle. Dialog flags, completion feedback, and
    /// `BGContinuedProcessingTask` submission are suppressed.
    var isManagedBySync = false

    // MARK: - Internal State

    private var uploadTask: Task<Void, Never>?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var uploadStartTime: Date?

    private var pendingTapeId: String?
    private var pendingCreateResponse: TapesAPIClient.CreateTapeResponse?
    private(set) var sourceTape: Tape?

    enum ShareMode: String {
        case viewing, collaborating
    }

    // MARK: - BGContinuedProcessingTask (iOS 26+)

    static let bgTaskIdentifier = "StudioMorph.Tapes.upload"
    static weak var current: ShareUploadCoordinator?

    private var _continuedTask: AnyObject?

    @available(iOS 26, *)
    private var continuedTask: BGContinuedProcessingTask? {
        get { _continuedTask as? BGContinuedProcessingTask }
        set { _continuedTask = newValue }
    }

    init() {
        Self.current = self
    }

    @available(iOS 26, *)
    static func registerBackgroundUploadHandler() {
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

    // MARK: - Progress

    var progress: Double {
        guard totalClips > 0 else { return 0 }
        return Double(completedClips + failedClipIndices.count) / Double(totalClips)
    }

    var progressLabel: String {
        if completedClips == 0 && failedClipIndices.isEmpty {
            return statusMessage.isEmpty ? "Preparing…" : statusMessage
        }
        return "Uploading \(completedClips)/\(totalClips)"
    }

    var formattedTimeRemaining: String? {
        guard let startTime = uploadStartTime, progress > 0.05 else { return nil }
        let elapsed = Date().timeIntervalSince(startTime)
        let estimatedTotal = elapsed / progress
        let remaining = estimatedTotal - elapsed
        if remaining < 60 { return "Less than a minute remaining" }
        return "~\(Int(ceil(remaining / 60))) min remaining"
    }

    // MARK: - Ensure Tape Uploaded

    /// Guarantees the tape + all its real clips exist on the server.
    /// Calls `onCompleted` on the main actor with the create response
    /// (which carries all 4 share IDs) once the tape is fully uploaded.
    ///
    /// - Parameters:
    ///   - tape: The local tape the user is sharing.
    ///   - intendedForCollaboration: If `true`, creates the server tape in
    ///     collaborative mode and skips delta-deletes.
    ///   - api: Authenticated API client.
    ///   - onCompleted: Called on success with the server's response.
    func ensureTapeUploaded(
        tape: Tape,
        intendedForCollaboration: Bool,
        api: TapesAPIClient,
        onCompleted: ((TapesAPIClient.CreateTapeResponse) -> Void)? = nil
    ) {
        guard !isUploading else { return }

        isUploading = true
        totalClips = 0
        completedClips = 0
        failedClipIndices = []
        statusMessage = "Preparing tape…"
        uploadError = nil
        resultRemoteTapeId = nil
        resultCreateResponse = nil
        if intendedForCollaboration { resultMode = .collaborating }
        showProgressDialog = false
        showCompletionDialog = false
        showPostUploadDialog = false
        userDismissedModal = false
        completedShareURL = nil
        uploadStartTime = Date()
        sourceTape = tape

        uploadTask = Task { [weak self] in
            guard let self else { return }

            let tapeId = tape.id.uuidString.lowercased()
            let apiMode = intendedForCollaboration ? "collaborative" : "view_only"
            self.pendingTapeId = tapeId

            do {
                // 1. Ensure the tape record exists on the server (with silent retries)
                let response: TapesAPIClient.CreateTapeResponse
                if let cached = self.pendingCreateResponse, cached.tapeId.lowercased() == tapeId {
                    response = cached
                } else {
                    let tapeSettings: [String: Any] = [
                        "default_audio_level": 1.0,
                        "transition": [
                            "type": tape.transition.rawValue,
                            "duration_ms": Int(tape.transitionDuration * 1000)
                        ] as [String: Any],
                        "merge_settings": [
                            "orientation": tape.exportOrientation.rawValue,
                            "background_blur": tape.blurExportBackground
                        ] as [String: Any]
                    ]

                    response = try await Self.withRetry(maxAttempts: 3) {
                        try await api.createTape(
                            tapeId: tapeId,
                            title: tape.title,
                            mode: apiMode,
                            expiresAt: nil,
                            tapeSettings: tapeSettings
                        )
                    }
                }

                // 1b. If the owner has a local track and the server doesn't yet
                // have music for this tape, upload the mp3 once. Music is
                // write-once on the server; subsequent shares (and any
                // contribution path) skip this entirely. Best-effort — never
                // fails the share if music upload itself fails.
                await Self.uploadBackgroundMusicIfNeeded(
                    tape: tape,
                    response: response,
                    api: api
                )

                // 2. Compute delta: compare local clips vs server clips
                let localClips = tape.clips.filter { !$0.isPlaceholder }
                let localClipIds = Set(localClips.map { $0.id.uuidString.lowercased() })

                var serverClipIds: Set<String> = []
                if response.clipsUploaded == true {
                    do {
                        let manifest = try await Self.withRetry(maxAttempts: 3) {
                            try await api.getManifest(tapeId: tapeId)
                        }
                        serverClipIds = Set(manifest.clips.map { $0.clipId.lowercased() })
                    } catch {
                        TapesLog.upload.warning("Could not fetch manifest for delta; uploading all clips: \(error.localizedDescription)")
                    }
                }

                let clipsToUpload = localClips.filter { !serverClipIds.contains($0.id.uuidString.lowercased()) }
                let clipIdsToDelete = intendedForCollaboration ? Set<String>() : serverClipIds.subtracting(localClipIds)

                let hasWork = !clipsToUpload.isEmpty || !clipIdsToDelete.isEmpty

                if hasWork {
                    self.totalClips = clipsToUpload.count + clipIdsToDelete.count
                    if !self.isManagedBySync { self.showProgressDialog = true }

                    if !self.isManagedBySync, #available(iOS 26, *) {
                        self.submitContinuedProcessingTask()
                    }

                    if !clipsToUpload.isEmpty {
                        let batchType = (response.clipsUploaded == true) ? "update" : "invite"
                        _ = try? await api.declareUploadBatch(
                            tapeId: tapeId,
                            clipCount: clipsToUpload.count,
                            batchType: batchType,
                            mode: apiMode
                        )
                    }

                    // 3a. Upload new clips with extract-ahead pipelining:
                    // extraction of clip N+1 runs in parallel with the network
                    // upload of clip N, so CPU/disk and network overlap.
                    var newFailures: Set<Int> = []
                    var prefetch: Task<PreparedClip, Error>? = clipsToUpload.first.map { first in
                        Task.detached(priority: .userInitiated) {
                            try await Self.prepareClip(first)
                        }
                    }

                    for (index, clip) in clipsToUpload.enumerated() {
                        guard !Task.isCancelled else { break }

                        self.statusMessage = "Uploading clip \(index + 1) of \(clipsToUpload.count)…"

                        if #available(iOS 26, *) {
                            self.updateContinuedTaskProgress()
                        }

                        let currentPrefetch = prefetch
                        if index + 1 < clipsToUpload.count {
                            let nextClip = clipsToUpload[index + 1]
                            prefetch = Task.detached(priority: .userInitiated) {
                                try await Self.prepareClip(nextClip)
                            }
                        } else {
                            prefetch = nil
                        }

                        do {
                            guard let currentPrefetch else {
                                throw APIError.validation("Missing clip preparation task.")
                            }
                            let prepared = try await currentPrefetch.value
                            do {
                                try await Self.withRetry(maxAttempts: 3) {
                                    try await Self.uploadPrepared(clip, prepared: prepared, tapeId: tapeId, api: api)
                                }
                                Self.cleanupTempFiles(prepared.tempFiles)
                            } catch {
                                Self.cleanupTempFiles(prepared.tempFiles)
                                throw error
                            }
                            self.completedClips += 1
                        } catch {
                            TapesLog.upload.error("Clip \(index) failed: \(error.localizedDescription)")
                            newFailures.insert(index)
                        }
                    }

                    if let orphan = prefetch {
                        orphan.cancel()
                        if let prepared = try? await orphan.value {
                            Self.cleanupTempFiles(prepared.tempFiles)
                        }
                    }

                    // 3b. Delete removed clips from server + R2
                    for clipId in clipIdsToDelete {
                        guard !Task.isCancelled else { break }

                        self.statusMessage = "Syncing removed clips…"

                        do {
                            try await api.deleteClip(tapeId: tapeId, clipId: clipId)
                            self.completedClips += 1
                        } catch {
                            TapesLog.upload.error("Failed to delete server clip \(clipId): \(error.localizedDescription)")
                        }
                    }

                    self.failedClipIndices = newFailures

                    if !newFailures.isEmpty {
                        self.uploadError = "\(newFailures.count) clip(s) failed to upload."
                        self.pendingCreateResponse = nil
                        self.finishUpload(success: false)
                        return
                    }
                }

                // Update cached response
                self.pendingCreateResponse = TapesAPIClient.CreateTapeResponse(
                    tapeId: response.tapeId,
                    shareId: response.shareId,
                    shareIdCollab: response.shareIdCollab,
                    shareIdViewProtected: response.shareIdViewProtected,
                    shareIdCollabProtected: response.shareIdCollabProtected,
                    shareUrl: response.shareUrl,
                    deepLink: response.deepLink,
                    createdAt: response.createdAt,
                    clipsUploaded: true,
                    hasBackgroundMusic: response.hasBackgroundMusic
                )

                let finalResponse = self.pendingCreateResponse ?? response
                self.resultCreateResponse = finalResponse
                self.resultRemoteTapeId = tapeId
                self.lastUploadedClipCount = localClips.count
                // After a successful ensureTapeUploaded run, every local clip
                // is confirmed present on the server (either just uploaded or
                // already there from a prior run). Broadcast the full set so
                // observers can clear `isSynced = false` on all of them.
                self.lastSyncedClipIds = localClips.map(\.id)

                self.finishUpload(success: true)

                if hasWork && !self.isManagedBySync {
                    try? await Task.sleep(nanoseconds: 500_000_000)

                    if UIApplication.shared.applicationState == .active {
                        self.playCompletionFeedback()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            self.showCompletionDialog = true
                        }
                    } else {
                        self.sendCompletionNotification()
                        self.showCompletionDialog = true
                    }
                }

                onCompleted?(finalResponse)

            } catch {
                TapesLog.upload.error("Ensure upload failed: \(error.localizedDescription)")
                self.uploadError = error.localizedDescription
                self.pendingCreateResponse = nil
                self.finishUpload(success: false)
            }
        }
    }

    /// Cached create-response for the given local tape, if the server has
    /// already confirmed it. The share section uses this as its source of
    /// truth for the 4 share IDs once upload finishes.
    func cachedCreateResponse(for tape: Tape) -> TapesAPIClient.CreateTapeResponse? {
        guard let cached = pendingCreateResponse ?? resultCreateResponse else { return nil }
        guard cached.tapeId.lowercased() == tape.id.uuidString.lowercased() else { return nil }
        return cached
    }

    /// Primes the coordinator with a server-known response (e.g. from
    /// `GET /tapes/:id` when the modal opens on a previously-shared tape).
    /// Only sets `resultCreateResponse` (for URL display), NOT
    /// `pendingCreateResponse`, so `ensureTapeUploaded` always verifies
    /// upload status with the server instead of trusting the bootstrap.
    func seedCreateResponse(_ response: TapesAPIClient.CreateTapeResponse, for tape: Tape) {
        guard response.tapeId.lowercased() == tape.id.uuidString.lowercased() else { return }
        resultCreateResponse = response
        resultRemoteTapeId = response.tapeId
    }

    // MARK: - Retry Failed Clips

    func retryUpload(tape: Tape, api: TapesAPIClient) {
        let intendedForCollab = resultMode == .collaborating
        ensureTapeUploaded(tape: tape, intendedForCollaboration: intendedForCollab, api: api)
    }

    // MARK: - Contribute (upload unsynced clips on collaborative tapes)

    func contributeClips(tape: Tape, api: TapesAPIClient, markSynced: @escaping ([UUID]) -> Void) {
        guard !isUploading else { return }

        let unsyncedClips = tape.clips.filter { !$0.isPlaceholder && !$0.isSynced }
        guard !unsyncedClips.isEmpty else { return }

        guard let remoteTapeId = tape.shareInfo?.remoteTapeId else { return }

        sourceTape = tape
        isUploading = true
        totalClips = unsyncedClips.count
        completedClips = 0
        failedClipIndices = []
        statusMessage = "Contributing clips…"
        uploadError = nil
        if !isManagedBySync { showProgressDialog = true }
        showCompletionDialog = false
        uploadStartTime = Date()
        resultMode = .collaborating

        if !isManagedBySync, #available(iOS 26, *) {
            submitContinuedProcessingTask()
        }

        uploadTask = Task { [weak self] in
            guard let self else { return }

            _ = try? await api.declareUploadBatch(
                tapeId: remoteTapeId,
                clipCount: unsyncedClips.count,
                batchType: "update",
                mode: "collaborative"
            )

            var newFailures: Set<Int> = []
            var prefetch: Task<PreparedClip, Error>? = unsyncedClips.first.map { first in
                Task.detached(priority: .userInitiated) {
                    try await Self.prepareClip(first)
                }
            }

            for (index, clip) in unsyncedClips.enumerated() {
                guard !Task.isCancelled else { break }

                self.statusMessage = "Uploading clip \(index + 1) of \(unsyncedClips.count)…"

                if #available(iOS 26, *) {
                    self.updateContinuedTaskProgress()
                }

                let currentPrefetch = prefetch
                if index + 1 < unsyncedClips.count {
                    let nextClip = unsyncedClips[index + 1]
                    prefetch = Task.detached(priority: .userInitiated) {
                        try await Self.prepareClip(nextClip)
                    }
                } else {
                    prefetch = nil
                }

                do {
                    guard let currentPrefetch else {
                        throw APIError.validation("Missing clip preparation task.")
                    }
                    let prepared = try await currentPrefetch.value
                    do {
                        try await Self.withRetry(maxAttempts: 3) {
                            try await Self.uploadPrepared(clip, prepared: prepared, tapeId: remoteTapeId, api: api)
                        }
                        Self.cleanupTempFiles(prepared.tempFiles)
                    } catch {
                        Self.cleanupTempFiles(prepared.tempFiles)
                        throw error
                    }
                    self.completedClips += 1
                    await MainActor.run { markSynced([clip.id]) }
                } catch {
                    TapesLog.upload.error("Contribute clip \(index) failed: \(error.localizedDescription)")
                    newFailures.insert(index)
                }
            }

            if let orphan = prefetch {
                orphan.cancel()
                if let prepared = try? await orphan.value {
                    Self.cleanupTempFiles(prepared.tempFiles)
                }
            }

            self.failedClipIndices = newFailures

            if !newFailures.isEmpty {
                self.uploadError = "\(newFailures.count) clip(s) failed to upload."
                self.finishUpload(success: false)
                return
            }

            self.finishUpload(success: true)

            if !self.isManagedBySync {
                try? await Task.sleep(nanoseconds: 500_000_000)

                if UIApplication.shared.applicationState == .active {
                    self.playCompletionFeedback()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.showCompletionDialog = true
                    }
                } else {
                    self.sendContributionNotification()
                    self.showCompletionDialog = true
                }
            }
        }
    }

    private func sendContributionNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Clips Contributed"
        content.body = "Your clips have been uploaded to the shared tape."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let id = "contribute-complete-\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Cancellation

    func cancelUpload() {
        uploadTask?.cancel()
        uploadTask = nil
        finishUpload(success: false)
        statusMessage = ""
        totalClips = 0
        completedClips = 0
        failedClipIndices = []
        pendingCreateResponse = nil
    }

    // MARK: - Dialog Actions

    func dismissProgressDialog() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showProgressDialog = false
        }
    }

    /// Dismiss the progress dialog AND signal that the share modal should
    /// close. The upload continues in the background; when it completes the
    /// post-upload dialog will appear on the main view instead.
    func dismissToBackground() {
        userDismissedModal = true
        withAnimation(.easeInOut(duration: 0.2)) {
            showProgressDialog = false
        }
    }

    func dismissCompletionDialog() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showCompletionDialog = false
        }
    }

    func dismissPostUploadDialog() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showPostUploadDialog = false
            completedShareURL = nil
        }
    }

    func showProgressDialogAgain() {
        guard isUploading else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            showProgressDialog = true
        }
    }

    func clearError() {
        uploadError = nil
    }

    // MARK: - Scene Phase

    func handleScenePhaseChange(_ phase: ScenePhase) {
        if phase == .background && isUploading {
            beginBackgroundTask()
        }
    }

    // MARK: - Private Helpers

    private func finishUpload(success: Bool) {
        isUploading = false
        showProgressDialog = false
        endBackgroundTask()

        if #available(iOS 26, *) {
            completeContinuedTask(success: success)
        }

        if success {
            Self.flushUploadSession()
        }
    }

    /// Release URLSession connection pool and caches after upload so iOS
    /// can reclaim resources before the share sheet launches.
    private static func flushUploadSession() {
        uploadSession.reset {}
    }

    // MARK: - Clip Upload (static so it doesn't capture self)

    private nonisolated static let uploadSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config)
    }()

    /// Holds extracted media ready to upload. Extraction happens off-main via
    /// `prepareClip`; the upload step then reads only the already-resolved
    /// payload.
    ///
    /// `.file(URL)` is the default for anything backed by a real file
    /// (sandbox imports, PhotoKit videos, Live Photo resources). The R2
    /// upload then streams directly from disk via
    /// `URLSession.upload(for:fromFile:)` — bytes flow off disk straight into
    /// the TLS socket with no Data buffer in between, so memory stays flat
    /// even for multi-hundred-megabyte videos and the network can start
    /// sending after the first read instead of waiting for the whole file to
    /// land in RAM. `.data(Data)` is reserved for in-memory buffers we
    /// already own (still photos resolved by PhotoKit, thumbnail data),
    /// where a disk round-trip would be pure overhead.
    ///
    /// `tempFiles` lists files the caller owns and must delete after upload.
    /// Live Photo resources and export-session videos belong here. Files
    /// owned by another subsystem (the Photos library cache, the app's
    /// persistent imports store) must NOT be added to `tempFiles`.
    private struct PreparedClip: @unchecked Sendable {
        enum PrimarySource {
            case data(Data)
            case file(URL)
        }
        let primary: PrimarySource
        let primaryContentType: String
        let livePhotoMovieFileURL: URL?
        let tempFiles: [URL]
    }

    /// Off-main extraction. Returns a `PreparedClip` that the upload loop can
    /// hand to `uploadPrepared`. The caller owns `tempFiles` and must delete
    /// them after the upload finishes (success or failure).
    ///
    /// Streaming policy:
    ///   • Sandboxed `clip.localURL` files → `.file(url)`, **not** owned (no
    ///     cleanup) — the file is part of the app's persistent imports store.
    ///   • PhotoKit videos → `.file(url)`. For local unedited videos the URL
    ///     points directly into the Photos library cache and we do not own
    ///     it. For iCloud / edited videos the export session writes a temp
    ///     `.mp4` we own and clean up.
    ///   • Live Photos → `.file` for both the still and the paired movie,
    ///     written via `PHAssetResourceManager` (one PHAsset fetch, two
    ///     resource writes).
    ///   • Stills (image data, image PHAsset) → `.data`. Photos are small;
    ///     keeping them in memory avoids an unnecessary disk round-trip.
    private nonisolated static func prepareClip(_ clip: Clip) async throws -> PreparedClip {
        if clip.isLivePhoto, let assetId = clip.assetLocalId {
            let phAsset = try await fetchPHAssetWithRetry(identifier: assetId)
            let resources = PHAssetResource.assetResources(for: phAsset)
            guard let photoResource = resources.first(where: { $0.type == .photo }) else {
                throw APIError.validation("Live Photo has no photo resource.")
            }
            guard let pairedVideo = resources.first(where: { $0.type == .pairedVideo }) else {
                throw APIError.validation("Live Photo has no paired video resource.")
            }

            let photoExt = photoResource.originalFilename.split(separator: ".").last.map(String.init) ?? "jpg"
            let photoURL = livePhotoTempDir.appendingPathComponent("\(UUID().uuidString).\(photoExt)")
            let movieURL = livePhotoTempDir.appendingPathComponent("\(UUID().uuidString).mov")

            try await writeAssetResource(photoResource, to: photoURL)
            try await writeAssetResource(pairedVideo, to: movieURL)

            return PreparedClip(
                primary: .file(photoURL),
                primaryContentType: contentTypeForExtension(photoURL.pathExtension, default: "image/jpeg"),
                livePhotoMovieFileURL: movieURL,
                tempFiles: [photoURL, movieURL]
            )
        }

        if let url = clip.localURL, FileManager.default.fileExists(atPath: url.path) {
            return PreparedClip(
                primary: .file(url),
                primaryContentType: clip.clipType == .video ? "video/mp4" : "image/jpeg",
                livePhotoMovieFileURL: nil,
                tempFiles: []
            )
        }

        if clip.clipType == .image, let imageData = clip.resolvedImageData {
            return PreparedClip(
                primary: .data(imageData),
                primaryContentType: "image/jpeg",
                livePhotoMovieFileURL: nil,
                tempFiles: []
            )
        }

        if let assetId = clip.assetLocalId {
            let phAsset = try await fetchPHAssetWithRetry(identifier: assetId)
            if clip.clipType == .video {
                let (videoURL, ownedTempFiles) = try await exportVideoToFile(phAsset: phAsset)
                return PreparedClip(
                    primary: .file(videoURL),
                    primaryContentType: "video/mp4",
                    livePhotoMovieFileURL: nil,
                    tempFiles: ownedTempFiles
                )
            } else {
                let data = try await exportImageData(phAsset: phAsset)
                return PreparedClip(
                    primary: .data(data),
                    primaryContentType: "image/jpeg",
                    livePhotoMovieFileURL: nil,
                    tempFiles: []
                )
            }
        }

        throw APIError.validation("Clip has no media to upload.")
    }

    private nonisolated static func uploadPrepared(
        _ clip: Clip,
        prepared: PreparedClip,
        tapeId: String,
        api: TapesAPIClient
    ) async throws {
        let clipId = clip.id.uuidString.lowercased()
        let durationMs = Int(clip.duration * 1000)

        let clipType: String
        if clip.isLivePhoto {
            clipType = "live_photo"
        } else if clip.clipType == .video {
            clipType = "video"
        } else {
            clipType = "photo"
        }

        let createResponse = try await api.createClip(
            tapeId: tapeId,
            clipId: clipId,
            type: clipType,
            durationMs: durationMs,
            trimStartMs: clip.trimStart > 0 ? Int(clip.trimStart * 1000) : nil,
            trimEndMs: clip.trimEnd > 0 ? Int(clip.trimEnd * 1000) : nil,
            audioLevel: clip.volume,
            motionStyle: clip.motionStyle.rawValue,
            imageDurationMs: clip.clipType == .image ? Int(clip.imageDuration * 1000) : nil,
            rotateQuarterTurns: clip.rotateQuarterTurns != 0 ? clip.rotateQuarterTurns : nil,
            overrideScaleMode: clip.overrideScaleMode?.rawValue,
            livePhotoAsVideo: clip.isLivePhoto ? (clip.livePhotoAsVideo ?? false) : nil,
            livePhotoSound: clip.isLivePhoto ? !(clip.livePhotoMuted ?? false) : nil
        )

        // Run the three R2 PUTs concurrently. They write to independent
        // signed URLs (primary, paired Live Photo movie, thumbnail) and
        // share no server-side ordering. The clip is finished when the
        // slowest of them finishes, instead of the sum of all three —
        // which roughly halves wall-clock upload time for Live Photos
        // (where photo + paired video are both significant) and is a
        // negligible win for everything else.
        //
        // Any throw cancels the still-in-flight peers (structured
        // concurrency); the whole `uploadPrepared` call then fails and
        // `withRetry` re-runs the clip end-to-end, exactly as today.
        async let primaryUpload: Void = {
            switch prepared.primary {
            case .data(let data):
                try await Self.uploadToR2(
                    url: createResponse.uploadUrl,
                    data: data,
                    contentType: prepared.primaryContentType
                )
            case .file(let fileURL):
                try await Self.uploadToR2(
                    url: createResponse.uploadUrl,
                    fileURL: fileURL,
                    contentType: prepared.primaryContentType
                )
            }
        }()

        async let movieUpload: Void = {
            guard clip.isLivePhoto,
                  let movieUploadUrl = createResponse.livePhotoMovieUploadUrl,
                  let movieFileURL = prepared.livePhotoMovieFileURL else { return }
            try await Self.uploadToR2(
                url: movieUploadUrl,
                fileURL: movieFileURL,
                contentType: "video/quicktime"
            )
        }()

        async let thumbnailUpload: Void = {
            guard let thumbData = clip.thumbnail else { return }
            try await Self.uploadToR2(
                url: createResponse.thumbnailUploadUrl,
                data: thumbData,
                contentType: "image/jpeg"
            )
        }()

        try await primaryUpload
        try await movieUpload
        try await thumbnailUpload

        let baseUploadUrl = createResponse.uploadUrl.components(separatedBy: "?").first ?? createResponse.uploadUrl
        let baseThumbUrl = createResponse.thumbnailUploadUrl.components(separatedBy: "?").first ?? createResponse.thumbnailUploadUrl
        var baseMovieUrl: String?
        if let movieUrl = createResponse.livePhotoMovieUploadUrl {
            baseMovieUrl = movieUrl.components(separatedBy: "?").first ?? movieUrl
        }

        _ = try await api.confirmUpload(
            tapeId: tapeId,
            clipId: clipId,
            cloudUrl: baseUploadUrl,
            thumbnailUrl: baseThumbUrl,
            livePhotoMovieUrl: baseMovieUrl
        )
    }

    private nonisolated static func cleanupTempFiles(_ urls: [URL]) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Extraction Helpers

    private nonisolated static func fetchPHAssetWithRetry(identifier: String) async throws -> PHAsset {
        for attempt in 0..<3 {
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
            if let asset = fetchResult.firstObject {
                return asset
            }
            if attempt < 2 {
                try await Task.sleep(nanoseconds: UInt64((attempt + 1)) * 500_000_000)
            }
        }
        throw APIError.validation("Photo library asset not found.")
    }

    private nonisolated static let livePhotoTempDir: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("LivePhotoExport", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Writes a single `PHAssetResource` to disk via
    /// `PHAssetResourceManager.writeData`. Preserves the content identifier
    /// and other metadata needed for Live Photo reconstruction on the receiver.
    private nonisolated static func writeAssetResource(_ resource: PHAssetResource, to dest: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            PHAssetResourceManager.default().writeData(for: resource, toFile: dest, options: options) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Loads image data via `PHImageManager.requestImageDataAndOrientation` —
    /// Apple's standard UI-oriented path that returns right-sized HEIC/JPEG
    /// data suitable for upload (not the raw original).
    private nonisolated static func exportImageData(phAsset: PHAsset) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            PHImageManager.default().requestImageDataAndOrientation(for: phAsset, options: options) { data, _, _, _ in
                if let data {
                    cont.resume(returning: data)
                } else {
                    cont.resume(throwing: APIError.validation("Could not access image data."))
                }
            }
        }
    }

    /// Resolves a video PHAsset to a file URL ready for streamed upload.
    /// Returns the URL plus a list of files the caller owns and must delete.
    ///
    /// Fast path: `requestAVAsset` — local unedited videos come back as an
    /// `AVURLAsset` whose `.url` points into the Photos library cache. We
    /// hand that URL straight to URLSession; ownership stays with PhotoKit
    /// (no cleanup).
    ///
    /// Fallback: `requestExportSession` passthrough for iCloud or edited
    /// videos. The session writes a `.mp4` into our temp directory which we
    /// own and clean up after upload.
    private nonisolated static func exportVideoToFile(phAsset: PHAsset) async throws -> (url: URL, ownedTempFiles: [URL]) {
        if let directURL = try? await readVideoFileDirect(phAsset: phAsset) {
            return (directURL, [])
        }
        let tempURL = try await exportVideoViaSessionToFile(phAsset: phAsset)
        return (tempURL, [tempURL])
    }

    private nonisolated static func readVideoFileDirect(phAsset: PHAsset) async throws -> URL {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            let options = PHVideoRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { avAsset, _, _ in
                if let urlAsset = avAsset as? AVURLAsset {
                    cont.resume(returning: urlAsset.url)
                } else {
                    cont.resume(throwing: APIError.validation("AVURLAsset unavailable."))
                }
            }
        }
    }

    private nonisolated static func exportVideoViaSessionToFile(phAsset: PHAsset) async throws -> URL {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            let options = PHVideoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.version = .current
            PHImageManager.default().requestExportSession(
                forVideo: phAsset,
                options: options,
                exportPreset: AVAssetExportPresetPassthrough
            ) { session, _ in
                guard let session else {
                    cont.resume(throwing: APIError.validation("Could not export video."))
                    return
                }

                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + ".mp4")
                Task {
                    do {
                        try await session.export(to: tempURL, as: .mp4)
                        cont.resume(returning: tempURL)
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
        }
    }

    private nonisolated static func contentTypeForExtension(_ ext: String, default fallback: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "heic": return "image/heic"
        case "png": return "image/png"
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        default: return fallback
        }
    }

    // MARK: - R2 Upload

    private nonisolated static func uploadToR2(url: String, data: Data, contentType: String, maxRetries: Int = 3) async throws {
        guard let uploadURL = URL(string: url) else {
            throw APIError.validation("Invalid upload URL.")
        }

        var lastError: Error = APIError.server("Upload failed.")

        for attempt in 0..<maxRetries {
            if attempt > 0 {
                let delay = pow(2.0, Double(attempt))
                try await Task.sleep(for: .seconds(delay))
            }

            do {
                var request = URLRequest(url: uploadURL)
                request.httpMethod = "PUT"
                request.setValue(contentType, forHTTPHeaderField: "Content-Type")
                request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")

                let (_, response) = try await uploadSession.upload(for: request, from: data)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    lastError = APIError.server("Upload failed (HTTP \(code)).")
                    continue
                }
                return
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    /// File-streamed R2 upload. Used for Live Photo components, which the
    /// extraction step has already written to disk — uploading via
    /// `upload(for:fromFile:)` avoids an additional file→Data round trip and
    /// keeps memory near zero for large photo/paired-video bodies.
    private nonisolated static func uploadToR2(url: String, fileURL: URL, contentType: String, maxRetries: Int = 3) async throws {
        guard let uploadURL = URL(string: url) else {
            throw APIError.validation("Invalid upload URL.")
        }

        var lastError: Error = APIError.server("Upload failed.")

        for attempt in 0..<maxRetries {
            if attempt > 0 {
                let delay = pow(2.0, Double(attempt))
                try await Task.sleep(for: .seconds(delay))
            }

            do {
                var request = URLRequest(url: uploadURL)
                request.httpMethod = "PUT"
                request.setValue(contentType, forHTTPHeaderField: "Content-Type")

                let (_, response) = try await uploadSession.upload(for: request, fromFile: fileURL)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    lastError = APIError.server("Upload failed (HTTP \(code)).")
                    continue
                }
                return
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    // MARK: - Background Music Share

    /// First-share music attachment. Owner-only via server enforcement
    /// (403 → silent skip). Write-once per tape: if the server already
    /// has music (`response.hasBackgroundMusic == true`), this is a
    /// no-op. Best-effort throughout — never throws back into the
    /// share flow.
    private nonisolated static func uploadBackgroundMusicIfNeeded(
        tape: Tape,
        response: TapesAPIClient.CreateTapeResponse,
        api: TapesAPIClient
    ) async {
        guard response.hasBackgroundMusic != true else {
            TapesLog.upload.info("Music already attached server-side; skipping upload.")
            return
        }
        guard tape.hasBackgroundMusic, let mood = tape.backgroundMusicMood, !mood.isEmpty else {
            return
        }
        guard let mp3 = await MubertAPIClient.shared.cachedTrackURL(for: tape.id) else {
            TapesLog.upload.warning("Tape has music selection but no local mp3; skipping share upload.")
            return
        }

        let tapeId = tape.id.uuidString.lowercased()
        let prompt = tape.backgroundMusicPrompt
        let level = Double(tape.backgroundMusicVolume ?? 0.3)

        let type: String
        if let p = prompt, !p.isEmpty {
            type = "prompt"
        } else if let m = MubertAPIClient.Mood(rawValue: mood), m != .none {
            type = "mood"
        } else {
            type = "library"
        }

        do {
            let prep = try await api.prepareBackgroundMusicUpload(tapeId: tapeId)
            try await uploadToR2(url: prep.uploadUrl, fileURL: mp3, contentType: "audio/mpeg")
            try await api.confirmBackgroundMusic(
                tapeId: tapeId,
                type: type,
                mood: mood,
                prompt: prompt,
                publicUrl: prep.publicUrl,
                level: level
            )
            TapesLog.upload.info("Background music attached to shared tape (type=\(type, privacy: .public)).")
        } catch APIError.musicAlreadySet {
            TapesLog.upload.info("Music attach lost the race; server already has it. OK.")
        } catch {
            TapesLog.upload.warning("Background music share upload failed (non-fatal): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Retry Helper

    private static func withRetry<T>(
        maxAttempts: Int = 3,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error!
        for attempt in 0..<maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                if attempt < maxAttempts - 1 {
                    let delay = pow(2.0, Double(attempt))
                    try? await Task.sleep(for: .seconds(delay))
                }
            }
        }
        throw lastError
    }

    // MARK: - BGContinuedProcessingTask Lifecycle

    @available(iOS 26, *)
    private func submitContinuedProcessingTask() {
        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.bgTaskIdentifier,
            title: "Sharing Tape",
            subtitle: "Starting…"
        )
        request.strategy = .fail

        do {
            try BGTaskScheduler.shared.submit(request)
            TapesLog.upload.info("BGContinuedProcessingTask submitted for upload")
        } catch {
            TapesLog.upload.error("BGContinuedProcessingTask submit failed: \(error.localizedDescription)")
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
        let subtitle = formattedTimeRemaining ?? statusMessage
        task.updateTitle("Sharing Tape", subtitle: subtitle)
    }

    private func handleBackgroundTaskExpiration() {
        if #available(iOS 26, *) {
            continuedTask?.setTaskCompleted(success: false)
            continuedTask = nil
        }
        beginBackgroundTask()
    }

    // MARK: - Background Task (fallback)

    /// iOS contract: the expiration handler MUST call `endBackgroundTask`
    /// synchronously before it returns. Hopping into a `Task { @MainActor … }`
    /// to do it later trips the
    /// `Background task still not ended after expiration handlers were called`
    /// warning and risks process termination. Capture the identifier in a
    /// local, end it inline, and clear our stored property via
    /// `MainActor.assumeIsolated` (the closure already runs on the main
    /// thread; this is just bookkeeping that satisfies the compiler).
    private func beginBackgroundTask() {
        guard backgroundTaskID == .invalid else { return }
        var taskID: UIBackgroundTaskIdentifier = .invalid
        taskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            UIApplication.shared.endBackgroundTask(taskID)
            MainActor.assumeIsolated {
                self?.backgroundTaskID = .invalid
            }
        }
        backgroundTaskID = taskID
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
        content.title = "Tape Shared"
        content.body = "Your tape has been uploaded and shared successfully."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let id = "share-complete-\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
