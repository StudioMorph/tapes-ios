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

    /// Batch transfer state — bridges the callback-based batch completion to async/await.
    private var activeBatchContinuation: CheckedContinuation<Void, Error>?
    private var activeBatchId: String?
    private var activeBatchApi: TapesAPIClient?
    private var activeBatchTapeId: String?

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
        if let batchId = activeBatchId {
            let bp = BackgroundTransferManager.shared.batchProgress(batchId: batchId)
            if bp.total > 0 {
                return Double(bp.completed + bp.failed) / Double(bp.total)
            }
        }
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
    /// Uses the batch upload flow: all presigned URLs are requested upfront,
    /// all clip data is resolved and written to temp files, and all upload
    /// tasks are submitted to the background URLSession at once. The OS
    /// daemon handles the actual transfers even if the app is killed.
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
                // 1. Ensure the tape record exists on the server
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

                    // 3a. Delete removed clips from server + R2
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

                    // 3b. Batch upload new clips
                    if !clipsToUpload.isEmpty {
                        self.statusMessage = "Preparing clips…"

                        let batchType = (response.clipsUploaded == true) ? "update" : "invite"

                        // Build clip metadata for the batch prepare call
                        let clipMetadata: [[String: Any]] = clipsToUpload.map { clip in
                            Self.clipMetadataDict(clip)
                        }

                        // One API call to get all presigned URLs
                        let batchResponse = try await Self.withRetry(maxAttempts: 3) {
                            try await api.prepareUploadBatch(
                                tapeId: tapeId,
                                clips: clipMetadata,
                                batchType: batchType,
                                mode: apiMode
                            )
                        }

                        // Build a lookup from clip_id → presigned URLs
                        let urlLookup = Dictionary(
                            uniqueKeysWithValues: batchResponse.clips.map { ($0.clipId.lowercased(), $0) }
                        )

                        // Resolve all clip data and write to temp files
                        self.statusMessage = "Preparing media files…"
                        var batchTasks: [BackgroundTransferManager.BatchUploadTask] = []
                        var failedPrepIndices: Set<Int> = []

                        for (index, clip) in clipsToUpload.enumerated() {
                            guard !Task.isCancelled else { break }

                            let clipId = clip.id.uuidString.lowercased()
                            guard let urls = urlLookup[clipId] else {
                                TapesLog.upload.error("No presigned URLs for clip \(clipId)")
                                failedPrepIndices.insert(index)
                                continue
                            }

                            do {
                                let mediaData = try await Self.resolveClipData(clip)
                                let mediaTempFile = try Self.writeTempUploadFile(data: mediaData, name: "\(clipId)-media")
                                guard let mediaURL = URL(string: urls.uploadUrl) else {
                                    throw APIError.validation("Invalid upload URL.")
                                }
                                batchTasks.append(.init(
                                    fileURL: mediaTempFile,
                                    remoteURL: mediaURL,
                                    contentType: clip.clipType == .video ? "video/mp4" : "image/jpeg",
                                    clipId: clipId,
                                    kind: .uploadMedia
                                ))

                                if clip.isLivePhoto, let movieUrlStr = urls.livePhotoMovieUploadUrl {
                                    let movieData = try await Self.resolveLivePhotoMovieData(clip)
                                    let movieTempFile = try Self.writeTempUploadFile(data: movieData, name: "\(clipId)-movie")
                                    guard let movieURL = URL(string: movieUrlStr) else {
                                        throw APIError.validation("Invalid movie upload URL.")
                                    }
                                    batchTasks.append(.init(
                                        fileURL: movieTempFile,
                                        remoteURL: movieURL,
                                        contentType: "video/quicktime",
                                        clipId: clipId,
                                        kind: .uploadMovie
                                    ))
                                }

                                if let thumbData = clip.thumbnail {
                                    let thumbTempFile = try Self.writeTempUploadFile(data: thumbData, name: "\(clipId)-thumb")
                                    guard let thumbURL = URL(string: urls.thumbnailUploadUrl) else {
                                        throw APIError.validation("Invalid thumbnail upload URL.")
                                    }
                                    batchTasks.append(.init(
                                        fileURL: thumbTempFile,
                                        remoteURL: thumbURL,
                                        contentType: "image/jpeg",
                                        clipId: clipId,
                                        kind: .uploadThumbnail
                                    ))
                                }
                            } catch {
                                TapesLog.upload.error("Failed to prepare clip \(index): \(error.localizedDescription)")
                                failedPrepIndices.insert(index)
                            }
                        }

                        if !failedPrepIndices.isEmpty && batchTasks.isEmpty {
                            self.failedClipIndices = failedPrepIndices
                            self.uploadError = "\(failedPrepIndices.count) clip(s) failed to prepare."
                            self.pendingCreateResponse = nil
                            self.finishUpload(success: false)
                            return
                        }

                        guard !Task.isCancelled else {
                            self.finishUpload(success: false)
                            return
                        }

                        // Submit ALL upload tasks to the background session at once
                        self.statusMessage = "Uploading…"
                        let batchId = batchResponse.batchId

                        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                            self.activeBatchContinuation = continuation
                            self.activeBatchId = batchId
                            self.activeBatchApi = api
                            self.activeBatchTapeId = tapeId

                            BackgroundTransferManager.shared.submitBatchUpload(
                                batchId: batchId,
                                tapeId: tapeId,
                                tasks: batchTasks
                            ) { [weak self] completedBatchId in
                                Task { @MainActor in
                                    self?.handleBatchCompletion(batchId: completedBatchId)
                                }
                            }
                        }

                        self.failedClipIndices = failedPrepIndices
                        if !failedPrepIndices.isEmpty {
                            self.uploadError = "\(failedPrepIndices.count) clip(s) failed to prepare."
                        }
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
                    clipsUploaded: true
                )

                let finalResponse = self.pendingCreateResponse ?? response
                self.resultCreateResponse = finalResponse
                self.resultRemoteTapeId = tapeId
                self.lastUploadedClipCount = localClips.count
                self.lastSyncedClipIds = localClips.map(\.id)

                self.finishUpload(success: true)

                if hasWork && !self.isManagedBySync {
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

            do {
                self.statusMessage = "Preparing clips…"

                let clipMetadata: [[String: Any]] = unsyncedClips.map {
                    Self.clipMetadataDict($0)
                }

                let batchResponse = try await Self.withRetry(maxAttempts: 3) {
                    try await api.prepareUploadBatch(
                        tapeId: remoteTapeId,
                        clips: clipMetadata,
                        batchType: "update",
                        mode: "collaborative"
                    )
                }

                let urlLookup = Dictionary(
                    uniqueKeysWithValues: batchResponse.clips.map { ($0.clipId.lowercased(), $0) }
                )

                self.statusMessage = "Preparing media files…"
                var batchTasks: [BackgroundTransferManager.BatchUploadTask] = []
                var failedPrepIndices: Set<Int> = []

                for (index, clip) in unsyncedClips.enumerated() {
                    guard !Task.isCancelled else { break }

                    let clipId = clip.id.uuidString.lowercased()
                    guard let urls = urlLookup[clipId] else {
                        TapesLog.upload.error("No presigned URLs for contribute clip \(clipId)")
                        failedPrepIndices.insert(index)
                        continue
                    }

                    do {
                        let mediaData = try await Self.resolveClipData(clip)
                        let mediaTempFile = try Self.writeTempUploadFile(data: mediaData, name: "\(clipId)-media")
                        guard let mediaURL = URL(string: urls.uploadUrl) else {
                            throw APIError.validation("Invalid upload URL.")
                        }
                        batchTasks.append(.init(
                            fileURL: mediaTempFile,
                            remoteURL: mediaURL,
                            contentType: clip.clipType == .video ? "video/mp4" : "image/jpeg",
                            clipId: clipId,
                            kind: .uploadMedia
                        ))

                        if clip.isLivePhoto, let movieUrlStr = urls.livePhotoMovieUploadUrl {
                            let movieData = try await Self.resolveLivePhotoMovieData(clip)
                            let movieTempFile = try Self.writeTempUploadFile(data: movieData, name: "\(clipId)-movie")
                            guard let movieURL = URL(string: movieUrlStr) else {
                                throw APIError.validation("Invalid movie upload URL.")
                            }
                            batchTasks.append(.init(
                                fileURL: movieTempFile,
                                remoteURL: movieURL,
                                contentType: "video/quicktime",
                                clipId: clipId,
                                kind: .uploadMovie
                            ))
                        }

                        if let thumbData = clip.thumbnail {
                            let thumbTempFile = try Self.writeTempUploadFile(data: thumbData, name: "\(clipId)-thumb")
                            guard let thumbURL = URL(string: urls.thumbnailUploadUrl) else {
                                throw APIError.validation("Invalid thumbnail upload URL.")
                            }
                            batchTasks.append(.init(
                                fileURL: thumbTempFile,
                                remoteURL: thumbURL,
                                contentType: "image/jpeg",
                                clipId: clipId,
                                kind: .uploadThumbnail
                            ))
                        }
                    } catch {
                        TapesLog.upload.error("Failed to prepare contribute clip \(index): \(error.localizedDescription)")
                        failedPrepIndices.insert(index)
                    }
                }

                if !failedPrepIndices.isEmpty && batchTasks.isEmpty {
                    self.failedClipIndices = failedPrepIndices
                    self.uploadError = "\(failedPrepIndices.count) clip(s) failed to prepare."
                    self.finishUpload(success: false)
                    return
                }

                guard !Task.isCancelled else {
                    self.finishUpload(success: false)
                    return
                }

                self.statusMessage = "Uploading…"
                let batchId = batchResponse.batchId

                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    self.activeBatchContinuation = continuation
                    self.activeBatchId = batchId
                    self.activeBatchApi = api
                    self.activeBatchTapeId = remoteTapeId

                    BackgroundTransferManager.shared.submitBatchUpload(
                        batchId: batchId,
                        tapeId: remoteTapeId,
                        tasks: batchTasks
                    ) { [weak self] completedBatchId in
                        Task { @MainActor in
                            self?.handleBatchCompletion(batchId: completedBatchId)
                        }
                    }
                }

                // Mark all successfully uploaded clips as synced
                let manifest = BackgroundTransferManager.shared.manifest
                let completedEntries = manifest.completedEntries(forBatch: batchId)
                let syncedClipIds = Set(completedEntries.map(\.clipId))
                let syncedUUIDs = unsyncedClips.filter { syncedClipIds.contains($0.id.uuidString.lowercased()) }.map(\.id)
                markSynced(syncedUUIDs)

                self.failedClipIndices = failedPrepIndices

                if !failedPrepIndices.isEmpty {
                    self.uploadError = "\(failedPrepIndices.count) clip(s) failed to upload."
                    self.finishUpload(success: false)
                    return
                }

                self.finishUpload(success: true)

                if !self.isManagedBySync {
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
            } catch {
                TapesLog.upload.error("Contribute upload failed: \(error.localizedDescription)")
                self.uploadError = error.localizedDescription
                self.finishUpload(success: false)
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
        BackgroundTransferManager.shared.cancelAllTasks()

        if let batchId = activeBatchId {
            BackgroundTransferManager.shared.manifest.removeAll(batchId: batchId)
        }
        activeBatchContinuation?.resume(throwing: CancellationError())
        activeBatchContinuation = nil
        activeBatchId = nil
        activeBatchApi = nil
        activeBatchTapeId = nil

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
    }

    // MARK: - Batch Completion Handler

    private func handleBatchCompletion(batchId: String) {
        guard batchId == activeBatchId else { return }

        let manifest = BackgroundTransferManager.shared.manifest
        let completed = manifest.completedEntries(forBatch: batchId)
        let failed = manifest.failedEntries(forBatch: batchId)

        // Count completed clips (a clip is "done" when all its files uploaded)
        let completedClipIds = Set(completed.map(\.clipId))
        let failedClipIds = Set(failed.map(\.clipId)).subtracting(completedClipIds)

        self.completedClips = completedClipIds.count
        TapesLog.upload.info("Batch \(batchId): \(completedClipIds.count) clips uploaded, \(failedClipIds.count) failed")

        // Send batch confirm for all successfully uploaded clips
        Task { @MainActor [weak self] in
            guard let self, let api = self.activeBatchApi, let tapeId = self.activeBatchTapeId else {
                self?.activeBatchContinuation?.resume()
                self?.activeBatchContinuation = nil
                return
            }

            if !completedClipIds.isEmpty {
                // Build confirm payload from manifest entries
                var clipConfirms: [[String: String]] = []
                for clipId in completedClipIds {
                    let clipEntries = completed.filter { $0.clipId == clipId }
                    let mediaEntry = clipEntries.first { $0.kind == .uploadMedia }
                    let thumbEntry = clipEntries.first { $0.kind == .uploadThumbnail }
                    let movieEntry = clipEntries.first { $0.kind == .uploadMovie }

                    guard let cloudUrl = mediaEntry?.cloudUrl,
                          let thumbUrl = thumbEntry?.cloudUrl else { continue }

                    var entry: [String: String] = [
                        "clip_id": clipId,
                        "cloud_url": cloudUrl,
                        "thumbnail_url": thumbUrl
                    ]
                    if let movieUrl = movieEntry?.cloudUrl {
                        entry["live_photo_movie_url"] = movieUrl
                    }
                    clipConfirms.append(entry)
                }

                do {
                    _ = try await api.confirmUploadBatch(tapeId: tapeId, clips: clipConfirms)
                    TapesLog.upload.info("Batch confirm succeeded for \(clipConfirms.count) clips")
                } catch {
                    TapesLog.upload.error("Batch confirm failed: \(error.localizedDescription)")
                }
            }

            manifest.removeAll(batchId: batchId)
            self.activeBatchId = nil
            self.activeBatchApi = nil
            self.activeBatchTapeId = nil

            if failedClipIds.isEmpty {
                self.activeBatchContinuation?.resume()
            } else {
                self.activeBatchContinuation?.resume(throwing: APIError.server("\(failedClipIds.count) clip(s) failed to upload."))
            }
            self.activeBatchContinuation = nil
        }
    }

    // MARK: - Clip Metadata

    private static func clipMetadataDict(_ clip: Clip) -> [String: Any] {
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

        var dict: [String: Any] = [
            "clip_id": clipId,
            "type": clipType,
            "duration_ms": durationMs
        ]
        if clip.trimStart > 0 { dict["trim_start_ms"] = Int(clip.trimStart * 1000) }
        if clip.trimEnd > 0 { dict["trim_end_ms"] = Int(clip.trimEnd * 1000) }
        dict["audio_level"] = clip.volume
        dict["motion_style"] = clip.motionStyle.rawValue
        if clip.clipType == .image { dict["image_duration_ms"] = Int(clip.imageDuration * 1000) }
        if clip.rotateQuarterTurns != 0 { dict["rotate_quarter_turns"] = clip.rotateQuarterTurns }
        if let scaleMode = clip.overrideScaleMode { dict["override_scale_mode"] = scaleMode.rawValue }
        if clip.isLivePhoto { dict["live_photo_as_video"] = clip.livePhotoAsVideo ?? false }
        if clip.isLivePhoto { dict["live_photo_sound"] = !(clip.livePhotoMuted ?? false) }

        return dict
    }

    private static func writeTempUploadFile(data: Data, name: String) throws -> URL {
        let dir = BackgroundTransferManager.uploadTempDir
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func resolveClipData(_ clip: Clip) async throws -> Data {
        if clip.isLivePhoto, let assetId = clip.assetLocalId {
            return try await exportLivePhotoImageResource(identifier: assetId)
        }

        if let url = clip.localURL, FileManager.default.fileExists(atPath: url.path) {
            return try Data(contentsOf: url)
        }

        if clip.clipType == .image, let imageData = clip.resolvedImageData {
            return imageData
        }

        if let assetId = clip.assetLocalId {
            return try await exportPHAssetData(identifier: assetId, isVideo: clip.clipType == .video)
        }

        throw APIError.validation("Clip has no media to upload.")
    }

    private static func resolveLivePhotoMovieData(_ clip: Clip) async throws -> Data {
        guard let assetId = clip.assetLocalId else {
            throw APIError.validation("Live Photo has no asset identifier.")
        }

        guard let result = await extractLivePhotoVideo(assetIdentifier: assetId) else {
            throw APIError.validation("Could not extract Live Photo video component.")
        }

        return try Data(contentsOf: result.url)
    }

    /// Exports the photo resource of a Live Photo using PHAssetResourceManager,
    /// preserving all metadata including the content identifier needed for
    /// reconstructing Live Photos on the receiving device.
    private static func exportLivePhotoImageResource(identifier: String) async throws -> Data {
        var phAsset: PHAsset?
        for attempt in 0..<3 {
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
            if let asset = fetchResult.firstObject {
                phAsset = asset
                break
            }
            if attempt < 2 {
                try await Task.sleep(nanoseconds: UInt64((attempt + 1)) * 500_000_000)
            }
        }
        guard let phAsset else {
            throw APIError.validation("Photo library asset not found.")
        }

        let resources = PHAssetResource.assetResources(for: phAsset)
        guard let photoResource = resources.first(where: { $0.type == .photo }) else {
            throw APIError.validation("Live Photo has no photo resource.")
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("LivePhotoExport", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dest = tempDir.appendingPathComponent("\(UUID().uuidString).\(photoResource.originalFilename.split(separator: ".").last ?? "jpg")")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            PHAssetResourceManager.default().writeData(for: photoResource, toFile: dest, options: options) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        let data = try Data(contentsOf: dest)
        try? FileManager.default.removeItem(at: dest)
        return data
    }

    private static func exportPHAssetData(identifier: String, isVideo: Bool) async throws -> Data {
        var phAsset: PHAsset?
        for attempt in 0..<3 {
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
            if let asset = fetchResult.firstObject {
                phAsset = asset
                break
            }
            if attempt < 2 {
                try await Task.sleep(nanoseconds: UInt64((attempt + 1)) * 500_000_000)
            }
        }
        guard let phAsset else {
            throw APIError.validation("Photo library asset not found.")
        }

        if isVideo {
            return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
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

                    let tempDir = FileManager.default.temporaryDirectory
                    let tempURL = tempDir.appendingPathComponent(UUID().uuidString + ".mp4")
                    Task {
                        do {
                            try await session.export(to: tempURL, as: .mp4)
                            let data = try Data(contentsOf: tempURL)
                            try? FileManager.default.removeItem(at: tempURL)
                            cont.resume(returning: data)
                        } catch {
                            cont.resume(throwing: error)
                        }
                    }
                }
            }
        } else {
            return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
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
            continuedTask?.updateTitle("Sharing Tape", subtitle: "Continuing in background…")
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
        content.title = "Tape Shared"
        content.body = "Your tape has been uploaded and shared successfully."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let id = "share-complete-\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
