import Foundation
import AVFoundation
import CoreImage
import os

#if canImport(Metal) && canImport(MetalKit)
import Metal
import MetalKit
#endif

/// Protocol for transition renderers (2D and 3D)
protocol TransitionRenderer {
    /// Render transition between two video frames
    func renderTransition(
        from sourceImage: CIImage,
        to destinationImage: CIImage,
        progress: Float,
        transitionType: TransitionType,
        duration: CMTime
    ) throws -> CIImage
    
    /// Check if renderer supports the transition type
    func supports(transitionType: TransitionType) -> Bool
}

/// Basic 2D transition renderer (Phase 1, refactored)
final class BasicTransitionRenderer: TransitionRenderer {
    
    func renderTransition(
        from sourceImage: CIImage,
        to destinationImage: CIImage,
        progress: Float,
        transitionType: TransitionType,
        duration: CMTime
    ) throws -> CIImage {
        switch transitionType {
        case .none:
            return destinationImage
            
        case .dissolve:
            return dissolveTransition(from: sourceImage, to: destinationImage, progress: progress)
            
        case .wipe:
            return wipeTransition(from: sourceImage, to: destinationImage, progress: progress)
            
        case .zoom:
            return zoomTransition(from: sourceImage, to: destinationImage, progress: progress)
            
        case .slide:
            return slideTransition(from: sourceImage, to: destinationImage, progress: progress)
        }
    }
    
    func supports(transitionType: TransitionType) -> Bool {
        // Basic renderer supports all 2D transitions
        return true
    }
    
    // MARK: - Private Implementation
    
    private func dissolveTransition(from source: CIImage, to destination: CIImage, progress: Float) -> CIImage {
        let filter = CIFilter(name: "CIDissolveTransition")!
        filter.setValue(source, forKey: kCIInputImageKey)
        filter.setValue(destination, forKey: kCIInputTargetImageKey)
        filter.setValue(progress, forKey: kCIInputTimeKey)
        return filter.outputImage ?? destination
    }
    
    private func wipeTransition(from source: CIImage, to destination: CIImage, progress: Float) -> CIImage {
        // Simple horizontal wipe
        let filter = CIFilter(name: "CIBarsSwipeTransition")!
        filter.setValue(source, forKey: kCIInputImageKey)
        filter.setValue(destination, forKey: kCIInputTargetImageKey)
        filter.setValue(progress, forKey: kCIInputTimeKey)
        return filter.outputImage ?? destination
    }
    
    private func zoomTransition(from source: CIImage, to destination: CIImage, progress: Float) -> CIImage {
        // Zoom out source, zoom in destination
        let scale1 = 1.0 + Float(progress) * 0.2
        let scale2 = 1.2 - Float(progress) * 0.2
        
        let transform1 = CGAffineTransform(scaleX: CGFloat(scale1), y: CGFloat(scale1))
        let transform2 = CGAffineTransform(scaleX: CGFloat(scale2), y: CGFloat(scale2))
        
        let scaledSource = source.transformed(by: transform1)
        let scaledDest = destination.transformed(by: transform2)
        
        return dissolveTransition(from: scaledSource, to: scaledDest, progress: progress)
    }
    
    private func slideTransition(from source: CIImage, to destination: CIImage, progress: Float) -> CIImage {
        // Slide source left, destination from right
        let width = source.extent.width
        let offset1 = -width * CGFloat(progress)
        let offset2 = width * (1.0 - CGFloat(progress))
        
        let transform1 = CGAffineTransform(translationX: offset1, y: 0)
        let transform2 = CGAffineTransform(translationX: offset2, y: 0)
        
        let movedSource = source.transformed(by: transform1)
        let movedDest = destination.transformed(by: transform2)
        
        // Composite side by side
        let filter = CIFilter(name: "CISourceOverCompositing")!
        filter.setValue(movedDest, forKey: kCIInputImageKey)
        filter.setValue(movedSource, forKey: kCIInputBackgroundImageKey)
        return filter.outputImage ?? destination
    }
}

/// Metal-based 3D transition renderer (Phase 3)
final class MetalTransitionRenderer: TransitionRenderer {
    
    #if canImport(Metal) && canImport(MetalKit)
    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let ciContext: CIContext?
    
    init?() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return nil
        }
        
        guard let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        
        self.device = device
        self.commandQueue = commandQueue
        self.ciContext = CIContext(mtlDevice: device)
        
        TapesLog.player.info("MetalTransitionRenderer: Initialized with device \(device.name)")
    }
    #else
    init?() {
        return nil // Metal not available
    }
    #endif
    
    func renderTransition(
        from sourceImage: CIImage,
        to destinationImage: CIImage,
        progress: Float,
        transitionType: TransitionType,
        duration: CMTime
    ) throws -> CIImage {
        // For now, delegate to basic renderer
        // Phase 3 can implement actual Metal shaders for 3D effects
        let basicRenderer = BasicTransitionRenderer()
        return try basicRenderer.renderTransition(
            from: sourceImage,
            to: destinationImage,
            progress: progress,
            transitionType: transitionType,
            duration: duration
        )
    }
    
    func supports(transitionType: TransitionType) -> Bool {
        // Metal renderer can support 3D transitions (to be implemented)
        return true
    }
}

