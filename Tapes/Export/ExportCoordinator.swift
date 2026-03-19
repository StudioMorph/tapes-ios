import Foundation
import SwiftUI
import Photos
import UserNotifications
import AudioToolbox

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

    private let albumService: TapeAlbumServicing

    private static let notificationPermissionKey = "hasRequestedExportNotificationPermission"

    private var hasRequestedNotificationPermission: Bool {
        get { UserDefaults.standard.bool(forKey: Self.notificationPermissionKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.notificationPermissionKey) }
    }

    init(albumService: TapeAlbumServicing = TapeAlbumService()) {
        self.albumService = albumService
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

        isExporting = true
        progress = 0.0
        exportError = nil
        completedAssetIdentifier = nil
        showProgressDialog = true
        exportStartTime = Date()

        let session = TapeExportSession()
        self.exportSession = session

        startProgressPolling()

        exportTask = Task { [weak self] in
            guard let self else { return }

            let granted = await self.requestPhotoLibraryPermission()
            guard granted else {
                self.finishExport()
                self.exportError = "Photo library access is required to save videos."
                return
            }

            do {
                let result = try await session.run(tape: tape)

                self.finishExport()
                self.progress = 1.0
                self.completedAssetIdentifier = result.assetIdentifier

                if UIApplication.shared.applicationState == .active {
                    self.playCompletionFeedback()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.showCompletionDialog = true
                    }
                } else {
                    self.showCompletionDialog = true
                    self.sendCompletionNotification()
                }

                self.associateExportedAsset(
                    tape: tape,
                    assetIdentifier: result.assetIdentifier,
                    albumUpdateHandler: albumUpdateHandler
                )

                try? FileManager.default.removeItem(at: result.url)
            } catch {
                self.finishExport()

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
        finishExport()
        progress = 0
    }

    // MARK: - Dialog Actions

    func dismissProgressDialog() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showProgressDialog = false
        }
        requestNotificationPermissionIfNeeded()
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

    private func finishExport() {
        stopProgressPolling()
        isExporting = false
        showProgressDialog = false
        exportSession = nil
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
        content.userInfo = ["action": "openPhotos"]

        let request = UNNotificationRequest(
            identifier: "export-complete-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
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
