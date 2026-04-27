import Foundation
import Combine
import SwiftUI
import BackgroundTasks
import AudioToolbox
import UserNotifications
import os

/// Orchestrates a unified sync for collaborative tapes that may require
/// both uploads (local → server) and downloads (server → local).
///
/// Rather than reimplementing upload/download logic, this coordinator
/// *composes* the existing `ShareUploadCoordinator` and
/// `SharedTapeDownloadCoordinator`, setting their `isManagedBySync` flag
/// to suppress individual dialogs and feedback while aggregating their
/// progress into a single continuous "Syncing…" experience.
@MainActor
public class CollabSyncCoordinator: ObservableObject {

    // MARK: - Published State

    @Published var isSyncing = false
    @Published var showProgressDialog = false
    @Published var showCompletionDialog = false
    @Published var syncError: String?

    // MARK: - Internal State

    private var cancellables = Set<AnyCancellable>()
    private weak var uploadCoord: ShareUploadCoordinator?
    private weak var downloadCoord: SharedTapeDownloadCoordinator?
    private var pendingDownloadShareId: String?
    private var pendingAPI: TapesAPIClient?
    private var pendingTapesStore: TapesStore?
    private var syncStartTime: Date?
    private let log = Logger(subsystem: "com.studiomorph.tapes", category: "CollabSync")

    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    // MARK: - BGContinuedProcessingTask (iOS 26+)

    static let bgTaskIdentifier = "StudioMorph.Tapes.collabSync"
    static weak var current: CollabSyncCoordinator?

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
    static func registerBackgroundSyncHandler() {
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

    // MARK: - Aggregated Progress

    /// Combined total across both phases.
    var totalItems: Int {
        (uploadCoord?.totalClips ?? 0) + (downloadCoord?.totalCount ?? 0)
    }

    /// Combined completed across both phases.
    var completedItems: Int {
        (uploadCoord?.completedClips ?? 0) + (downloadCoord?.completedCount ?? 0)
    }

    var progress: Double {
        guard totalItems > 0 else { return 0 }
        return Double(completedItems) / Double(totalItems)
    }

    var progressLabel: String {
        if completedItems == 0 {
            return "Preparing…"
        }
        return "Syncing \(completedItems)/\(totalItems)"
    }

    var formattedTimeRemaining: String? {
        guard let startTime = syncStartTime, progress > 0.05 else { return nil }
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

    // MARK: - Start Sync

    func startSync(
        tape: Tape,
        hasUploads: Bool,
        hasDownloads: Bool,
        uploadCoordinator: ShareUploadCoordinator,
        downloadCoordinator: SharedTapeDownloadCoordinator,
        api: TapesAPIClient,
        tapesStore: TapesStore,
        markClipsSynced: @escaping ([UUID]) -> Void
    ) {
        guard !isSyncing else { return }
        guard !uploadCoordinator.isUploading else { return }
        guard !downloadCoordinator.isDownloading else { return }

        self.uploadCoord = uploadCoordinator
        self.downloadCoord = downloadCoordinator
        self.pendingAPI = api
        self.pendingTapesStore = tapesStore
        self.pendingDownloadShareId = hasDownloads ? tape.shareInfo?.shareId : nil

        uploadCoordinator.isManagedBySync = true
        downloadCoordinator.isManagedBySync = true

        isSyncing = true
        showProgressDialog = true
        showCompletionDialog = false
        syncError = nil
        syncStartTime = Date()

        beginBackgroundTask()
        if #available(iOS 26, *) {
            submitContinuedProcessingTask()
        }

        observeProgressUpdates()

        if hasUploads {
            observeUploadCompletion(markClipsSynced: markClipsSynced)
            startUploadPhase(tape: tape, api: api, markClipsSynced: markClipsSynced)
        } else {
            startDownloadPhase()
        }
    }

    // MARK: - Upload Phase

    private func startUploadPhase(
        tape: Tape,
        api: TapesAPIClient,
        markClipsSynced: @escaping ([UUID]) -> Void
    ) {
        if tape.isCollabTape {
            uploadCoord?.ensureTapeUploaded(
                tape: tape,
                intendedForCollaboration: true,
                api: api
            )
        } else {
            uploadCoord?.contributeClips(tape: tape, api: api) { syncedIds in
                markClipsSynced(syncedIds)
            }
        }
    }

    private func observeUploadCompletion(markClipsSynced: @escaping ([UUID]) -> Void) {
        uploadCoord?.$isUploading
            .dropFirst()
            .filter { !$0 }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleUploadPhaseComplete()
            }
            .store(in: &cancellables)
    }

    private func handleUploadPhaseComplete() {
        if let error = uploadCoord?.uploadError {
            syncError = error
            finishSync(success: false)
            return
        }

        if pendingDownloadShareId != nil {
            startDownloadPhase()
        } else {
            finishSync(success: true)
        }
    }

    // MARK: - Download Phase

    private func startDownloadPhase() {
        guard let shareId = pendingDownloadShareId,
              let api = pendingAPI,
              let tapesStore = pendingTapesStore,
              let downloadCoord else {
            finishSync(success: true)
            return
        }

        observeDownloadCompletion()
        downloadCoord.startDownload(shareId: shareId, api: api, tapeStore: tapesStore)
    }

    private func observeDownloadCompletion() {
        downloadCoord?.$isDownloading
            .dropFirst()
            .filter { !$0 }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleDownloadPhaseComplete()
            }
            .store(in: &cancellables)
    }

    private func handleDownloadPhaseComplete() {
        guard let dl = downloadCoord else {
            finishSync(success: true)
            return
        }

        let hasRealFailures = dl.failedCount > 0
        if hasRealFailures {
            syncError = "\(dl.failedCount) clip(s) failed to download."
            finishSync(success: false)
        } else {
            finishSync(success: true)
        }
    }

    // MARK: - Progress Observation

    private func observeProgressUpdates() {
        let uploadProgress = uploadCoord?.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateProgress() }

        let downloadProgress = downloadCoord?.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateProgress() }

        if let u = uploadProgress { u.store(in: &cancellables) }
        if let d = downloadProgress { d.store(in: &cancellables) }
    }

    private func updateProgress() {
        objectWillChange.send()

        if #available(iOS 26, *) {
            updateContinuedTaskProgress()
        }
    }

    // MARK: - Finish

    private func finishSync(success: Bool) {
        cancellables.removeAll()

        uploadCoord?.isManagedBySync = false
        downloadCoord?.isManagedBySync = false
        pendingAPI = nil
        pendingTapesStore = nil
        pendingDownloadShareId = nil

        isSyncing = false
        endBackgroundTask()

        if #available(iOS 26, *) {
            completeContinuedTask(success: success)
        }

        if success && completedItems > 0 {
            if UIApplication.shared.applicationState == .active {
                playCompletionFeedback()
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCompletionDialog = true
                }
            } else {
                sendCompletionNotification()
                showCompletionDialog = true
            }
        }
    }

    // MARK: - Cancel

    func cancelSync() {
        uploadCoord?.cancelUpload()
        downloadCoord?.cancelDownload()
        cancellables.removeAll()

        uploadCoord?.isManagedBySync = false
        downloadCoord?.isManagedBySync = false
        pendingAPI = nil
        pendingTapesStore = nil
        pendingDownloadShareId = nil

        isSyncing = false
        showProgressDialog = false
        showCompletionDialog = false
        syncError = nil
        endBackgroundTask()

        if #available(iOS 26, *) {
            completeContinuedTask(success: false)
        }
    }

    // MARK: - Dialog Actions

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

    func dismissCompletionDialog() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showCompletionDialog = false
        }
    }

    func clearError() {
        syncError = nil
    }

    // MARK: - Scene Phase

    func handleScenePhaseChange(_ phase: ScenePhase) {
        if phase == .background && isSyncing {
            beginBackgroundTask()
        }
    }

    // MARK: - BGContinuedProcessingTask Lifecycle

    @available(iOS 26, *)
    private func submitContinuedProcessingTask() {
        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.bgTaskIdentifier,
            title: "Syncing Tape",
            subtitle: "Starting…"
        )
        request.strategy = .fail

        do {
            try BGTaskScheduler.shared.submit(request)
            log.info("BGContinuedProcessingTask submitted for collab sync")
        } catch {
            log.error("BGContinuedProcessingTask submit failed: \(error.localizedDescription)")
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
        task.updateTitle("Syncing Tape", subtitle: subtitle)
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
        content.title = "Tape Synced"
        content.body = "Your collaborative tape has been synced successfully."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let id = "sync-complete-\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
