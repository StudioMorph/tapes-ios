import Foundation
import AVFoundation
import os

/// Manages progressive extension of composition during playback
@MainActor
final class CompositionExtensionManager {
    
    // MARK: - Properties
    
    private let builder: TapeCompositionBuilder
    private let strategy: CompositionStrategy
    private var currentComposition: TapeCompositionBuilder.PlayerComposition?
    private var extendedAssets: Set<Int> = []
    
    // MARK: - Initialization
    
    init(
        builder: TapeCompositionBuilder = TapeCompositionBuilder(),
        strategy: CompositionStrategy? = nil
    ) {
        self.builder = builder
        self.strategy = strategy ?? (FeatureFlags.playbackEngineV2Phase2 ? ExtendableCompositionStrategy() : SingleCompositionStrategy())
    }
    
    // MARK: - Public API
    
    /// Build initial composition
    func buildInitial(
        for tape: Tape,
        readyAssets: [(Int, HybridAssetLoader.ResolvedAsset)],
        skippedIndices: Set<Int>
    ) async throws -> TapeCompositionBuilder.PlayerComposition {
        let composition = try await strategy.buildInitialComposition(
            for: tape,
            readyAssets: readyAssets,
            skippedIndices: skippedIndices,
            builder: builder
        )
        
        currentComposition = composition
        extendedAssets = Set(readyAssets.map { $0.0 })
        
        TapesLog.player.info("CompositionExtensionManager: Initial composition built with \(readyAssets.count) assets")
        
        return composition
    }
    
    /// Try to extend composition with new assets
    func extendIfNeeded(
        for tape: Tape,
        newAssets: [(Int, HybridAssetLoader.ResolvedAsset)],
        currentPlaybackTime: Double,
        player: AVPlayer?
    ) async -> TapeCompositionBuilder.PlayerComposition? {
        guard FeatureFlags.playbackEngineV2Phase2 else {
            return nil
        }
        
        guard let currentComposition = currentComposition else {
            return nil
        }
        
        // Filter to truly new assets
        let trulyNew = newAssets.filter { !extendedAssets.contains($0.0) }
        guard !trulyNew.isEmpty else {
            return nil
        }
        
        // Check if extension makes sense (playback hasn't reached end)
        let compositionEnd = CMTimeGetSeconds(currentComposition.timeline.totalDuration)
        guard currentPlaybackTime < compositionEnd - 5.0 else {
            // Playback near end, extension not needed
            return nil
        }
        
        // Try to extend
        do {
            if let extended = try await strategy.extendComposition(
                currentComposition,
                with: trulyNew,
                for: tape,
                builder: builder
            ) {
                // Update tracking
                for (index, _) in trulyNew {
                    extendedAssets.insert(index)
                }
                
                TapesLog.player.info("CompositionExtensionManager: Extended composition with \(trulyNew.count) new assets")
                
                return extended
            }
        } catch {
            TapesLog.player.error("CompositionExtensionManager: Extension failed: \(error.localizedDescription)")
        }
        
        return nil
    }
    
    /// Reset manager state
    func reset() {
        currentComposition = nil
        extendedAssets.removeAll()
        TapesLog.player.info("CompositionExtensionManager: Reset")
    }
}

