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
            
        case .crossfade:
            return dissolveTransition(from: sourceImage, to: destinationImage, progress: progress)
            
        case .slideLR:
            return slideLRTransition(from: sourceImage, to: destinationImage, progress: progress)
            
        case .slideRL:
            return slideRLTransition(from: sourceImage, to: destinationImage, progress: progress)
            
        case .randomise:
            // For randomise, use crossfade as default (actual randomisation handled at composition level)
            return dissolveTransition(from: sourceImage, to: destinationImage, progress: progress)
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
    
    private func slideLRTransition(from source: CIImage, to destination: CIImage, progress: Float) -> CIImage {
        // Slide source left, destination from right (Left to Right)
        let width = source.extent.width
        let offset1 = -width * CGFloat(progress)
        let offset2 = width * (1.0 - CGFloat(progress))
        
        let transform1 = CGAffineTransform(translationX: offset1, y: 0)
        let transform2 = CGAffineTransform(translationX: offset2, y: 0)
        
        let movedSource = source.transformed(by: transform1)
        let movedDest = destination.transformed(by: transform2)
        
        // Composite with fade
        let fadedSource = applyFade(to: movedSource, progress: progress, fadeOut: true)
        let fadedDest = applyFade(to: movedDest, progress: progress, fadeOut: false)
        
        let filter = CIFilter(name: "CISourceOverCompositing")!
        filter.setValue(fadedDest, forKey: kCIInputImageKey)
        filter.setValue(fadedSource, forKey: kCIInputBackgroundImageKey)
        return filter.outputImage ?? destination
    }
    
    private func slideRLTransition(from source: CIImage, to destination: CIImage, progress: Float) -> CIImage {
        // Slide source right, destination from left (Right to Left)
        let width = source.extent.width
        let offset1 = width * CGFloat(progress)
        let offset2 = -width * (1.0 - CGFloat(progress))
        
        let transform1 = CGAffineTransform(translationX: offset1, y: 0)
        let transform2 = CGAffineTransform(translationX: offset2, y: 0)
        
        let movedSource = source.transformed(by: transform1)
        let movedDest = destination.transformed(by: transform2)
        
        // Composite with fade
        let fadedSource = applyFade(to: movedSource, progress: progress, fadeOut: true)
        let fadedDest = applyFade(to: movedDest, progress: progress, fadeOut: false)
        
        let filter = CIFilter(name: "CISourceOverCompositing")!
        filter.setValue(fadedDest, forKey: kCIInputImageKey)
        filter.setValue(fadedSource, forKey: kCIInputBackgroundImageKey)
        return filter.outputImage ?? destination
    }
    
    private func applyFade(to image: CIImage, progress: Float, fadeOut: Bool) -> CIImage {
        let opacity = fadeOut ? (1.0 - progress) : progress
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(opacity))
        ])
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

