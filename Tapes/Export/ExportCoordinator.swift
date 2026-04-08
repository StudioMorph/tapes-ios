import Foundation
import SwiftUI
import Photos
import UserNotifications
import AudioToolbox
import BackgroundTasks

@MainActor
public class ExportCoordinator: ObservableObject {

    // MARK: - Published State

    @Published var isExporting = false
    @Published var progress: Double = 0.0
    @Published var showProgressDialog = false
    @Published var showCompletionDialog = false
    @Published var exportError: String?

    // MARK: - Internal State

    private(set) var completedAssetIdentifier: String?
    private var exportSession: TapeExportSession?
    private var exportTask: Task<Void, Never>?
    private var progressTimer: Timer?
    private var exportStartTime: Date?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    private let albumService: TapeAlbumServicing

    private static let notificationPermissionKey = "hasRequestedExportNotificationPermission"

    private var hasRequestedNotificationPermission: Bool {
        get { UserDefaults.standard.bool(forKey: Self.notificationPermissionKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.notificationPermissionKey) }
    }

    // MARK: - BGContinuedProcessingTask (iOS 26+)

    static let bgTaskIdentifier = "StudioMorph.Tapes.export"
    static weak var current: ExportCoordinator?

    /// Type-erased storage; actual type is BGContinuedProcessingTask on iOS 26+.
    private var _continuedTask: AnyObject?

    @available(iOS 26, *)
    private var continuedTask: BGContinuedProcessingTask? {
        get { _continuedTask as? BGContinuedProcessingTask }
        set { _continuedTask = newValue }
    }

    init(albumService: TapeAlbumServicing = TapeAlbumService()) {
        self.albumService = albumService
        Self.current = self
    }

    // MARK: - Handler Registration (called once at app launch)

    @available(iOS 26, *)
    static func registerBackgroundExportHandler() {
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

    // MARK: - ETA

    var estimatedTimeRemaining: TimeInterval? {
        guard let startTime = exportStartTime, progress > 0.05 else { return nil }
        let elapsed = Date().timeIntervalSince(startTime)
        let estimatedTotal = elapsed / progress
        let remaining = estimatedTotal - elapsed
        return remaining > 1 ? remaining : nil
    }

    var formattedTimeRemaining: String? {
        guard let remaining = estimatedTimeRemaining else { return nil }
        if remaining < 60 {
            return "Less than a minute remaining"
        }
        let minutes = Int(ceil(remaining / 60))
        return "~\(minutes) min remaining"
    }

    // MARK: - Export

    func exportTape(_ tape: Tape, albumUpdateHandler: @escaping (String) -> Void = { _ in }) {
        guard !isExporting else { return }

        if let staleSession = exportSession {
            staleSession.cancel()
            TapeExportSession.cleanUpStaleExportFiles()
        }
        exportSession = nil
        exportTask = nil

        isExporting = true
        progress = 0.0
        exportError = nil
        completedAssetIdentifier = nil
        showProgressDialog = true
        exportStartTime = Date()

        let session = TapeExportSession()
        self.exportSession = session

        if #available(iOS 26, *) {
            submitContinuedProcessingTask()
        }

        startProgressPolling()

        exportTask = Task { [weak self] in
            guard let self else {
                TapesLog.export.error("exportTask: self deallocated")
                return
            }

            let granted = await self.requestPhotoLibraryPermission()
            guard granted else {
                TapesLog.export.error("exportTask: photo library permission denied")
                self.finishExport(success: false)
                self.exportError = "Photo library access is required to save videos."
                return
            }

            do {
                let result = try await session.run(tape: tape)
                session.cancel()

                TapesLog.export.info("exportTask: success, showing completion dialog")
                self.finishExport(success: true)
                self.progress = 1.0
                self.completedAssetIdentifier = result.assetIdentifier

                if UIApplication.shared.applicationState == .active {
                    self.playCompletionFeedback()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.showCompletionDialog = true
                    }
                } else {
                    if #unavailable(iOS 26) {
                        self.sendCompletionNotification()
                    }
                    self.showCompletionDialog = true
                }

                self.associateExportedAsset(
                    tape: tape,
                    assetIdentifier: result.assetIdentifier,
                    albumUpdateHandler: albumUpdateHandler
                )

                try? FileManager.default.removeItem(at: result.url)
            } catch {
                TapesLog.export.error("exportTask: failed — \(error.localizedDescription, privacy: .public), isCancelled=\(session.isCancelled)")
                session.cancel()
                TapeExportSession.cleanUpStaleExportFiles()
                self.finishExport(success: false)

                if session.isCancelled {
                    self.progress = 0
                } else {
                    self.exportError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Cancellation

    func cancelExport() {
        exportSession?.cancel()
        exportTask?.cancel()
        exportTask = nil
        TapeExportSession.cleanUpStaleExportFiles()
        finishExport(success: false)
        progress = 0
    }

    // MARK: - Dialog Actions

    func dismissProgressDialog() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showProgressDialog = false
        }
        if #unavailable(iOS 26) {
            requestNotificationPermissionIfNeeded()
        }
    }

    func dismissCompletionDialog() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showCompletionDialog = false
        }
    }

    func showInPhotos() {
        showCompletionDialog = false
        if let url = URL(string: "photos-redirect://") {
            UIApplication.shared.open(url)
        }
    }

    func showProgressDialogAgain() {
        guard isExporting else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            showProgressDialog = true
        }
    }

    func clearError() {
        exportError = nil
    }

    // MARK: - Private Helpers

    private func finishExport(success: Bool) {
        stopProgressPolling()
        isExporting = false
        showProgressDialog = false
        exportSession = nil
        endBackgroundExportTask()

        if #available(iOS 26, *) {
            completeContinuedTask(success: success)
        }
    }

    // MARK: - BGContinuedProcessingTask Lifecycle

    @available(iOS 26, *)
    private func submitContinuedProcessingTask() {
        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.bgTaskIdentifier,
            title: "Exporting Tape",
            subtitle: "Starting…"
        )
        request.strategy = .fail
        if BGTaskScheduler.supportedResources.contains(.gpu) {
            request.requiredResources = .gpu
        }

        do {
            try BGTaskScheduler.shared.submit(request)
            TapesLog.export.info("BGContinuedProcessingTask submitted successfully")
        } catch {
            TapesLog.export.error("BGContinuedProcessingTask submit FAILED: \(error.localizedDescription, privacy: .public)")
            beginBackgroundExportTask()
        }
    }

    @available(iOS 26, *)
    private func completeContinuedTask(success: Bool) {
        guard let task = continuedTask else { return }
        task.progress.completedUnitCount = 100
        task.setTaskCompleted(success: success)
        self.continuedTask = nil
        TapesLog.export.info("BGContinuedProcessingTask completed: success=\(success)")
    }

    private func handleBackgroundTaskExpiration() {
        TapesLog.export.warning("BGContinuedProcessingTask expired — export continues without background protection")
        if #available(iOS 26, *) {
            continuedTask?.setTaskCompleted(success: false)
            continuedTask = nil
        }
        beginBackgroundExportTask()
    }

    // MARK: - Progress Polling

    private func startProgressPolling() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateProgress()
            }
        }
    }

    private func stopProgressPolling() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func updateProgress() {
        guard let session = exportSession, isExporting else { return }
        let p = Double(session.sessionProgress)
        progress = min(p * 0.95, 0.95)

        if #available(iOS 26, *) {
            updateContinuedTaskProgress(fraction: p)
        }
    }

    @available(iOS 26, *)
    private func updateContinuedTaskProgress(fraction: Double) {
        guard let task = continuedTask else { return }
        task.progress.completedUnitCount = Int64(fraction * 100)

        let subtitle = formattedTimeRemaining ?? "Processing…"
        task.updateTitle("Exporting Tape", subtitle: subtitle)
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

    // MARK: - Scene Phase

    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background:
            if isExporting {
                beginBackgroundExportTask()
            }
        case .active:
            break
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    // MARK: - Background Task (basic fallback for all iOS versions)

    private func beginBackgroundExportTask() {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundExportTask()
        }
    }

    private func endBackgroundExportTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    // MARK: - Notifications

    private func requestNotificationPermissionIfNeeded() {
        guard !hasRequestedNotificationPermission else { return }
        hasRequestedNotificationPermission = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendCompletionNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Tape Ready"
        content.body = "Your tape has been merged and saved to Photos."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let id = "export-complete-\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Photo Library Permission

    private func requestPhotoLibraryPermission() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)

        switch status {
        case .authorized, .limited:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            let newStatus = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                    continuation.resume(returning: newStatus)
                }
            }
            return newStatus == .authorized || newStatus == .limited
        @unknown default:
            return false
        }
    }

    // MARK: - Album Association

    private func associateExportedAsset(
        tape: Tape,
        assetIdentifier: String?,
        albumUpdateHandler: @escaping (String) -> Void
    ) {
        guard let assetIdentifier, !assetIdentifier.isEmpty else {
            TapesLog.photos.warning("Export succeeded but no asset identifier returned for tape \(tape.id.uuidString, privacy: .public)")
            return
        }
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                let association = try await self.albumService.ensureAlbum(for: tape)
                if tape.albumLocalIdentifier != association.albumLocalIdentifier {
                    await MainActor.run {
                        albumUpdateHandler(association.albumLocalIdentifier)
                    }
                }
                try await self.albumService.addAssets(
                    withIdentifiers: [assetIdentifier],
                    to: association.albumLocalIdentifier
                )
            } catch {
                TapesLog.photos.error("Failed to associate exported asset: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
