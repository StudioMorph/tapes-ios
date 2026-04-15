import Foundation
import SwiftUI
import Photos
import AVFoundation
import UserNotifications
import AudioToolbox
import BackgroundTasks
import os

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

    @Published var resultShareId: String?
    @Published var resultShareUrl: String?
    @Published var resultMode: ShareMode = .viewing
    @Published var resultRemoteTapeId: String?

    // MARK: - Internal State

    private var uploadTask: Task<Void, Never>?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var uploadStartTime: Date?

    private var pendingTapeId: String?
    private var pendingCreateResponse: TapesAPIClient.CreateTapeResponse?
    private var pendingInvites: [String] = []
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

    // MARK: - Start Upload & Share

    func startShare(
        tape: Tape,
        mode: ShareMode,
        inviteEmails: [String],
        api: TapesAPIClient
    ) {
        guard !isUploading else { return }

        isUploading = true
        totalClips = 0
        completedClips = 0
        failedClipIndices = []
        statusMessage = "Creating tape…"
        uploadError = nil
        resultShareId = nil
        resultShareUrl = nil
        resultRemoteTapeId = nil
        resultMode = mode
        showProgressDialog = true
        showCompletionDialog = false
        uploadStartTime = Date()
        pendingInvites = inviteEmails
        sourceTape = tape

        if #available(iOS 26, *) {
            submitContinuedProcessingTask()
        }

        uploadTask = Task { [weak self] in
            guard let self else { return }

            let tapeId = tape.id.uuidString.lowercased()
            let apiMode = mode == .viewing ? "view_only" : "collaborative"
            self.pendingTapeId = tapeId

            do {
                let response: TapesAPIClient.CreateTapeResponse
                if let cached = self.pendingCreateResponse {
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

                    response = try await api.createTape(
                        tapeId: tapeId,
                        title: tape.title,
                        mode: apiMode,
                        expiresAt: nil,
                        tapeSettings: tapeSettings
                    )
                    self.pendingCreateResponse = response
                }

                let skipUpload = response.clipsUploaded == true

                if !skipUpload {
                    let realClips = tape.clips.filter { !$0.isPlaceholder }
                    let clipsToUpload: [(index: Int, clip: Clip)]

                    if self.failedClipIndices.isEmpty {
                        clipsToUpload = realClips.enumerated().map { ($0.offset, $0.element) }
                    } else {
                        clipsToUpload = self.failedClipIndices.sorted().compactMap { idx in
                            guard idx < realClips.count else { return nil }
                            return (idx, realClips[idx])
                        }
                    }

                    self.totalClips = realClips.count
                    var newFailures: Set<Int> = []

                    for (index, clip) in clipsToUpload {
                        guard !Task.isCancelled else { break }

                        self.statusMessage = "Uploading clip \(index + 1) of \(realClips.count)…"

                        if #available(iOS 26, *) {
                            self.updateContinuedTaskProgress()
                        }

                        do {
                            try await Self.uploadClip(clip, tapeId: tapeId, api: api)
                            self.completedClips += 1
                        } catch {
                            TapesLog.upload.error("Clip \(index) failed: \(error.localizedDescription)")
                            newFailures.insert(index)
                        }
                    }

                    self.failedClipIndices = newFailures

                    if !newFailures.isEmpty {
                        self.uploadError = "\(newFailures.count) clip(s) failed to upload."
                        self.finishUpload(success: false)
                        return
                    }
                }

                // Upload complete — send invites
                self.statusMessage = "Sending invites…"
                let shareId = response.shareId
                let shareUrl = response.shareUrl
                let accessMode = mode == .viewing ? "view" : "collaborate"

                for email in self.pendingInvites {
                    do {
                        try await api.inviteCollaborator(
                            tapeId: tapeId,
                            email: email,
                            accessMode: accessMode
                        )
                    } catch {
                        TapesLog.upload.error("Invite failed for \(email): \(error.localizedDescription)")
                    }
                }

                self.resultShareId = shareId
                self.resultShareUrl = shareUrl
                self.resultRemoteTapeId = tapeId
                self.pendingCreateResponse = nil
                self.pendingInvites = []

                self.finishUpload(success: true)

                if UIApplication.shared.applicationState == .active {
                    self.playCompletionFeedback()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.showCompletionDialog = true
                    }
                } else {
                    self.sendCompletionNotification()
                    self.showCompletionDialog = true
                }

            } catch {
                TapesLog.upload.error("Share failed: \(error.localizedDescription)")
                self.uploadError = error.localizedDescription
                self.finishUpload(success: false)
            }
        }
    }

    // MARK: - Retry Failed Clips

    func retryUpload(tape: Tape, api: TapesAPIClient) {
        let mode = resultMode
        startShare(tape: tape, mode: mode, inviteEmails: pendingInvites, api: api)
    }

    // MARK: - Contribute (upload unsynced clips on collaborative tapes)

    func contributeClips(tape: Tape, api: TapesAPIClient, markSynced: @escaping ([UUID]) -> Void) {
        guard !isUploading else { return }

        let unsyncedClips = tape.clips.filter { !$0.isPlaceholder && !$0.isSynced }
        guard !unsyncedClips.isEmpty else { return }

        guard let remoteTapeId = tape.shareInfo?.remoteTapeId else { return }

        isUploading = true
        totalClips = unsyncedClips.count
        completedClips = 0
        failedClipIndices = []
        statusMessage = "Contributing clips…"
        uploadError = nil
        showProgressDialog = true
        showCompletionDialog = false
        uploadStartTime = Date()
        resultMode = .collaborating

        if #available(iOS 26, *) {
            submitContinuedProcessingTask()
        }

        uploadTask = Task { [weak self] in
            guard let self else { return }

            var syncedIds: [UUID] = []
            var newFailures: Set<Int> = []

            for (index, clip) in unsyncedClips.enumerated() {
                guard !Task.isCancelled else { break }

                self.statusMessage = "Uploading clip \(index + 1) of \(unsyncedClips.count)…"

                if #available(iOS 26, *) {
                    self.updateContinuedTaskProgress()
                }

                do {
                    try await Self.uploadClip(clip, tapeId: remoteTapeId, api: api)
                    self.completedClips += 1
                    syncedIds.append(clip.id)
                } catch {
                    TapesLog.upload.error("Contribute clip \(index) failed: \(error.localizedDescription)")
                    newFailures.insert(index)
                }
            }

            self.failedClipIndices = newFailures

            if !newFailures.isEmpty {
                self.uploadError = "\(newFailures.count) clip(s) failed to upload."
                self.finishUpload(success: false)
                return
            }

            await MainActor.run {
                markSynced(syncedIds)
            }

            self.finishUpload(success: true)

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

    func dismissCompletionDialog() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showCompletionDialog = false
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

    // MARK: - Clip Upload (static so it doesn't capture self)

    private static let uploadSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config)
    }()

    private static func uploadClip(_ clip: Clip, tapeId: String, api: TapesAPIClient) async throws {
        let clipId = clip.id.uuidString.lowercased()
        let clipType = clip.clipType == .video ? "video" : "photo"
        let durationMs = Int(clip.duration * 1000)

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
            overrideScaleMode: clip.overrideScaleMode?.rawValue
        )

        let fileData = try await resolveClipData(clip)

        try await uploadToR2(
            url: createResponse.uploadUrl,
            data: fileData,
            contentType: clip.clipType == .video ? "video/mp4" : "image/jpeg"
        )

        if let thumbData = clip.thumbnail {
            try await uploadToR2(
                url: createResponse.thumbnailUploadUrl,
                data: thumbData,
                contentType: "image/jpeg"
            )
        }

        let baseUploadUrl = createResponse.uploadUrl.components(separatedBy: "?").first ?? createResponse.uploadUrl
        let baseThumbUrl = createResponse.thumbnailUploadUrl.components(separatedBy: "?").first ?? createResponse.thumbnailUploadUrl
        _ = try await api.confirmUpload(
            tapeId: tapeId,
            clipId: clipId,
            cloudUrl: baseUploadUrl,
            thumbnailUrl: baseThumbUrl
        )
    }

    private static func resolveClipData(_ clip: Clip) async throws -> Data {
        if let url = clip.localURL {
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

    private static func exportPHAssetData(identifier: String, isVideo: Bool) async throws -> Data {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let phAsset = fetchResult.firstObject else {
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
                    session.outputURL = tempURL
                    session.outputFileType = .mp4
                    session.exportAsynchronously {
                        switch session.status {
                        case .completed:
                            do {
                                let data = try Data(contentsOf: tempURL)
                                try? FileManager.default.removeItem(at: tempURL)
                                cont.resume(returning: data)
                            } catch {
                                cont.resume(throwing: error)
                            }
                        default:
                            let msg = session.error?.localizedDescription ?? "Export failed."
                            cont.resume(throwing: APIError.validation(msg))
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

    private static func uploadToR2(url: String, data: Data, contentType: String, maxRetries: Int = 3) async throws {
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

    private func beginBackgroundTask() {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
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
