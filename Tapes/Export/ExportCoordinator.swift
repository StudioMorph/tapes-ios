import Foundation
import SwiftUI
import Photos
import AVFoundation

// MARK: - Export Coordinator

@MainActor
public class ExportCoordinator: ObservableObject {
    @Published public var isExporting: Bool = false
    @Published public var exportProgress: Double = 0.0
    @Published public var showCompletionToast: Bool = false
    @Published public var exportError: String?

    private let albumService: TapeAlbumServicing
    private var exportTask: Task<Void, Never>?

    init(albumService: TapeAlbumServicing = TapeAlbumService()) {
        self.albumService = albumService
    }

    // MARK: - Export Methods

    public func exportTape(_ tape: Tape, albumUpdateHandler: @escaping (String) -> Void = { _ in }) {
        guard !isExporting else { return }

        isExporting = true
        exportProgress = 0.0
        exportError = nil

        exportTask = Task { [weak self] in
            guard let self else { return }

            let granted = await self.requestPhotoLibraryPermission()
            guard granted else {
                self.isExporting = false
                self.exportError = "Photo library access is required to save videos"
                return
            }

            do {
                let result = try await iOSExporterBridge.export(tape: tape)

                self.isExporting = false
                self.exportProgress = 1.0
                self.showCompletionToast = true

                self.associateExportedAsset(
                    tape: tape,
                    assetIdentifier: result.assetIdentifier,
                    albumUpdateHandler: albumUpdateHandler
                )

                try? FileManager.default.removeItem(at: result.url)
            } catch {
                self.isExporting = false
                self.exportError = error.localizedDescription
            }
        }
    }

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

    public func dismissCompletionToast() {
        showCompletionToast = false
    }

    public func clearError() {
        exportError = nil
    }

    private func associateExportedAsset(tape: Tape, assetIdentifier: String?, albumUpdateHandler: @escaping (String) -> Void) {
        guard let assetIdentifier, !assetIdentifier.isEmpty else {
            TapesLog.photos.warning("Export succeeded but no asset identifier was returned for tape \(tape.id.uuidString, privacy: .public)")
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
                try await self.albumService.addAssets(withIdentifiers: [assetIdentifier], to: association.albumLocalIdentifier)
            } catch {
                TapesLog.photos.error("Failed to associate exported asset with album: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

// MARK: - Export Progress Overlay

public struct ExportProgressOverlay: View {
    @ObservedObject var coordinator: ExportCoordinator
    
    public init(coordinator: ExportCoordinator) {
        self.coordinator = coordinator
    }
    
    public var body: some View {
        if coordinator.isExporting {
            ZStack {
                // Background
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                
                // Progress Card
                VStack(spacing: Tokens.Spacing.l) {
                    // Progress Indicator
                    ZStack {
                        Circle()
                            .stroke(Tokens.Colors.muted.opacity(0.3), lineWidth: 4)
                            .frame(width: 60, height: 60)
                        
                        Circle()
                            .trim(from: 0, to: coordinator.exportProgress)
                            .stroke(Tokens.Colors.red, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .frame(width: 60, height: 60)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.3), value: coordinator.exportProgress)
                        
                        if coordinator.exportProgress < 1.0 {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(Tokens.Colors.red)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(Tokens.Colors.red)
                        }
                    }
                    
                    // Progress Text
                    VStack(spacing: Tokens.Spacing.s) {
                        Text("Exporting Video")
                            .font(Tokens.Typography.title)
                            .foregroundColor(Tokens.Colors.onSurface)
                            .fontWeight(.medium)
                        
                        Text("Creating 1080p MP4 with transitions...")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(Tokens.Colors.muted)
                            .multilineTextAlignment(.center)
                        
                        if coordinator.exportProgress > 0 {
                            Text("\(Int(coordinator.exportProgress * 100))%")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(Tokens.Colors.muted)
                        }
                    }
                }
                .padding(Tokens.Spacing.l)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.card)
                        .fill(Tokens.Colors.card)
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
                )
                .padding(.horizontal, Tokens.Spacing.l)
            }
        }
    }
}

// MARK: - Completion Toast

public struct CompletionToast: View {
    @ObservedObject var coordinator: ExportCoordinator
    @State private var isVisible: Bool = false
    
    public init(coordinator: ExportCoordinator) {
        self.coordinator = coordinator
    }
    
    public var body: some View {
        if coordinator.showCompletionToast {
            VStack {
                Spacer()
                
                HStack(spacing: Tokens.Spacing.m) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                    
                    VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
                        Text("Export Complete")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.white)
                            .fontWeight(.medium)
                        
                        Text("Video saved to Photos in 'Tapes' album")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, Tokens.Spacing.m)
                .padding(.vertical, Tokens.Spacing.m)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.thumb)
                        .fill(Tokens.Colors.red)
                )
                .padding(.horizontal, Tokens.Spacing.l)
                .padding(.bottom, Tokens.Spacing.l)
                .opacity(isVisible ? 1.0 : 0.0)
                .scaleEffect(isVisible ? 1.0 : 0.8)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isVisible)
                .onAppear {
                    isVisible = true
                    
                    // Auto-dismiss after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        coordinator.dismissCompletionToast()
                    }
                }
                .onTapGesture {
                    coordinator.dismissCompletionToast()
                }
            }
        }
    }
}

// MARK: - Error Alert

public struct ExportErrorAlert: View {
    @ObservedObject var coordinator: ExportCoordinator
    
    public init(coordinator: ExportCoordinator) {
        self.coordinator = coordinator
    }
    
    public var body: some View {
        EmptyView()
            .alert("Export Failed", isPresented: .constant(coordinator.exportError != nil)) {
                Button("OK") {
                    coordinator.clearError()
                }
            } message: {
                if let error = coordinator.exportError {
                    Text(error)
                }
            }
    }
}
