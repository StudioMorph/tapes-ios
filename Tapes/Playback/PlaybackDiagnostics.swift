import Foundation
import AVFoundation
import Photos
import UIKit

/// Diagnostic logging for video mispositioning investigation.
/// Only active when isEnabled = true (debug builds).
enum PlaybackDiagnostics {
    static var isEnabled: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    
    /// Log clip start diagnostics once per clip
    struct ClipDiagnostics {
        let clipIndex: Int
        let clipID: String // Hashed
        let assetID: String? // PHAsset localIdentifier (hashed) or nil
        let fileURL: String? // Basename only
        let clipType: String
        
        // Video track properties
        let naturalSize: CGSize
        let preferredTransform: CGAffineTransform
        let computedDisplaySize: CGSize // After applying preferredTransform
        let cleanAperture: CGRect?
        let pixelAspectRatio: CGSize?
        
        // Composition properties
        let renderSize: CGSize
        let instructionCount: Int
        let finalTransform: CGAffineTransform?
        
        // Player/Layer properties
        let videoGravity: String? // If accessible
        let layerBounds: CGRect?
        let containerSize: CGSize?
        let safeAreaInsets: UIEdgeInsets?
        let scaleMode: String
        
        // Timing
        let timeToFirstFrame: TimeInterval?
        let layoutStabilisedTime: TimeInterval?
        
        // Flags
        let isCloudPlaceholder: Bool
        let isEdited: Bool
        
        // Helper to create display size from transform
        static func computeDisplaySize(natural: CGSize, transform: CGAffineTransform) -> CGSize {
            let rect = CGRect(origin: .zero, size: natural)
            let transformed = rect.applying(transform)
            return CGSize(width: abs(transformed.width), height: abs(transformed.height))
        }
    }
    
    /// Log diagnostics for a clip (called once when clip starts)
    static func logClipStart(_ diagnostics: ClipDiagnostics) {
        guard isEnabled else { return }
        
        // Hash asset IDs for privacy
        let assetIDHash = diagnostics.assetID.map { String($0.prefix(8)) + "..." } ?? "nil"
        let clipIDHash = String(diagnostics.clipID.prefix(8)) + "..."
        
        // Format as single parsable line
        let cleanApertureStr = diagnostics.cleanAperture.map { "\(Int($0.width))x\(Int($0.height))@(\(Int($0.origin.x)),\(Int($0.origin.y)))" } ?? "nil"
        let pixelAspectRatioStr = diagnostics.pixelAspectRatio.map { "\(String(format: "%.3f", $0.width)):\(String(format: "%.3f", $0.height))" } ?? "1:1"
        let finalTransformStr = diagnostics.finalTransform.map { "[a:\(String(format: "%.3f", $0.a)) b:\(String(format: "%.3f", $0.b)) c:\(String(format: "%.3f", $0.c)) d:\(String(format: "%.3f", $0.d)) tx:\(String(format: "%.1f", $0.tx)) ty:\(String(format: "%.1f", $0.ty))]" } ?? "nil"
        let layerBoundsStr = diagnostics.layerBounds.map { "\(Int($0.width))x\(Int($0.height))" } ?? "nil"
        let containerSizeStr = diagnostics.containerSize.map { "\(Int($0.width))x\(Int($0.height))" } ?? "nil"
        let ttfFrameStr = diagnostics.timeToFirstFrame.map { String(format: "%.3f", $0) } ?? "nil"
        let layoutStableStr = diagnostics.layoutStabilisedTime.map { String(format: "%.3f", $0) } ?? "nil"
        
        // Use direct string interpolation for Logger
        TapesLog.player.info(
            "[PLAYBACK] clip=\(diagnostics.clipIndex) clipID=\(clipIDHash, privacy: .public) assetID=\(assetIDHash, privacy: .public) fileURL=\(diagnostics.fileURL ?? "nil", privacy: .public) type=\(diagnostics.clipType) naturalSize=\(Int(diagnostics.naturalSize.width))x\(Int(diagnostics.naturalSize.height)) preferredTransform=[a:\(String(format: "%.3f", diagnostics.preferredTransform.a)) b:\(String(format: "%.3f", diagnostics.preferredTransform.b)) c:\(String(format: "%.3f", diagnostics.preferredTransform.c)) d:\(String(format: "%.3f", diagnostics.preferredTransform.d)) tx:\(String(format: "%.1f", diagnostics.preferredTransform.tx)) ty:\(String(format: "%.1f", diagnostics.preferredTransform.ty))] displaySize=\(Int(diagnostics.computedDisplaySize.width))x\(Int(diagnostics.computedDisplaySize.height)) cleanAperture=\(cleanApertureStr) pixelAspectRatio=\(pixelAspectRatioStr) renderSize=\(Int(diagnostics.renderSize.width))x\(Int(diagnostics.renderSize.height)) instructionCount=\(diagnostics.instructionCount) finalTransform=\(finalTransformStr) videoGravity=\(diagnostics.videoGravity ?? "unknown") layerBounds=\(layerBoundsStr) containerSize=\(containerSizeStr) safeArea=(\(Int(diagnostics.safeAreaInsets?.top ?? 0)),\(Int(diagnostics.safeAreaInsets?.left ?? 0)),\(Int(diagnostics.safeAreaInsets?.bottom ?? 0)),\(Int(diagnostics.safeAreaInsets?.right ?? 0))) scaleMode=\(diagnostics.scaleMode) ttfFrame=\(ttfFrameStr) layoutStable=\(layoutStableStr) isCloud=\(diagnostics.isCloudPlaceholder) isEdited=\(diagnostics.isEdited)"
        )
    }
    
    /// Log layout stabilisation (called after layout completes)
    static func logLayoutStabilised(clipIndex: Int, bounds: CGRect, containerSize: CGSize, safeArea: UIEdgeInsets) {
        guard isEnabled else { return }
        
        TapesLog.player.info(
            "[PLAYBACK] layoutStabilised clip=\(clipIndex) bounds=\(Int(bounds.width))x\(Int(bounds.height)) container=\(Int(containerSize.width))x\(Int(containerSize.height)) safeArea=(\(Int(safeArea.top)),\(Int(safeArea.left)),\(Int(safeArea.bottom)),\(Int(safeArea.right)))"
        )
    }
}

