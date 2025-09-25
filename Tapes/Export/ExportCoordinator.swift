import Foundation
import SwiftUI
import Photos
import AVFoundation

// MARK: - Transition Style (iOS Exporter Compatibility)

enum TransitionStyle {
    case none
    case crossfade
    case slideLR
    case slideRL
    case randomise
}

// MARK: - Export Coordinator

@MainActor
public class ExportCoordinator: ObservableObject {
    @Published public var isExporting: Bool = false
    @Published public var exportProgress: Double = 0.0
    @Published public var showCompletionToast: Bool = false
    @Published public var exportError: String?
    
    private var exportSession: AVAssetExportSession?
    
    public init() {}
    
    // MARK: - Export Methods
    
    public func exportTape(_ tape: Tape) {
        guard !isExporting else { return }
        
        isExporting = true
        exportProgress = 0.0
        exportError = nil
        
        // Request photo library permission
        requestPhotoLibraryPermission { [weak self] granted in
            guard granted else {
                DispatchQueue.main.async {
                    self?.isExporting = false
                    self?.exportError = "Photo library access is required to save videos"
                }
                return
            }
            
            // Start export
            self?.startExport(tape)
        }
    }
    
    private func startExport(_ tape: Tape) {
        // Use the iOS TapeExporter via bridge
        iOSExporterBridge.export(tape: tape) { [weak self] url in
            DispatchQueue.main.async {
                self?.isExporting = false
                
                if let url = url {
                    self?.exportProgress = 1.0
                    self?.showCompletionToast = true
                    
                    // Clean up temporary file
                    try? FileManager.default.removeItem(at: url)
                } else {
                    self?.exportError = "Export failed. Please try again."
                }
            }
        }
    }
    
    private func requestPhotoLibraryPermission(completion: @escaping (Bool) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        
        switch status {
        case .authorized, .limited:
            completion(true)
        case .denied, .restricted:
            completion(false)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                completion(newStatus == .authorized || newStatus == .limited)
            }
        @unknown default:
            completion(false)
        }
    }
    
    public func dismissCompletionToast() {
        showCompletionToast = false
    }
    
    public func clearError() {
        exportError = nil
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
                VStack(spacing: DesignTokens.Spacing.s20) {
                    // Progress Indicator
                    ZStack {
                        Circle()
                            .stroke(DesignTokens.Colors.muted(30), lineWidth: 4)
                            .frame(width: 60, height: 60)
                        
                        Circle()
                            .trim(from: 0, to: coordinator.exportProgress)
                            .stroke(DesignTokens.Colors.primaryRed, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .frame(width: 60, height: 60)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.3), value: coordinator.exportProgress)
                        
                        if coordinator.exportProgress < 1.0 {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(DesignTokens.Colors.primaryRed)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(DesignTokens.Colors.primaryRed)
                        }
                    }
                    
                    // Progress Text
                    VStack(spacing: DesignTokens.Spacing.s8) {
                        Text("Exporting Video")
                            .font(DesignTokens.Typography.title)
                            .foregroundColor(DesignTokens.Colors.onSurface(.light))
                            .fontWeight(.medium)
                        
                        Text("Creating 1080p MP4 with transitions...")
                            .font(DesignTokens.Typography.body)
                            .foregroundColor(DesignTokens.Colors.muted(60))
                            .multilineTextAlignment(.center)
                        
                        if coordinator.exportProgress > 0 {
                            Text("\(Int(coordinator.exportProgress * 100))%")
                                .font(DesignTokens.Typography.caption)
                                .foregroundColor(DesignTokens.Colors.muted(60))
                        }
                    }
                }
                .padding(DesignTokens.Spacing.s24)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                        .fill(DesignTokens.Colors.surface(.light))
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
                )
                .padding(.horizontal, DesignTokens.Spacing.s32)
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
                
                HStack(spacing: DesignTokens.Spacing.s12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                    
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s4) {
                        Text("Export Complete")
                            .font(DesignTokens.Typography.body)
                            .foregroundColor(.white)
                            .fontWeight(.medium)
                        
                        Text("Video saved to Photos in 'Tapes' album")
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, DesignTokens.Spacing.s16)
                .padding(.vertical, DesignTokens.Spacing.s12)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.thumbnail)
                        .fill(DesignTokens.Colors.primaryRed)
                )
                .padding(.horizontal, DesignTokens.Spacing.s20)
                .padding(.bottom, DesignTokens.Spacing.s32)
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
