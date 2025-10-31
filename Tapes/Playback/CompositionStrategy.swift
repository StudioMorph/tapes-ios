import Foundation
import AVFoundation

/// Protocol for different composition strategies
protocol CompositionStrategy {
    /// Build initial composition with available assets
    func buildInitialComposition(
        for tape: Tape,
        readyAssets: [(Int, HybridAssetLoader.ResolvedAsset)],
        skippedIndices: Set<Int>,
        builder: TapeCompositionBuilder
    ) async throws -> TapeCompositionBuilder.PlayerComposition
    
    /// Extend existing composition with new assets (if supported)
    func extendComposition(
        _ existing: TapeCompositionBuilder.PlayerComposition,
        with newAssets: [(Int, HybridAssetLoader.ResolvedAsset)],
        for tape: Tape,
        builder: TapeCompositionBuilder
    ) async throws -> TapeCompositionBuilder.PlayerComposition?
}

/// Phase 1 strategy: Single composition, no extension
final class SingleCompositionStrategy: CompositionStrategy {
    func buildInitialComposition(
        for tape: Tape,
        readyAssets: [(Int, HybridAssetLoader.ResolvedAsset)],
        skippedIndices: Set<Int>,
        builder: TapeCompositionBuilder
    ) async throws -> TapeCompositionBuilder.PlayerComposition {
        return try await builder.buildPlayerItem(
            for: tape,
            readyAssets: readyAssets,
            skippedIndices: skippedIndices
        )
    }
    
    func extendComposition(
        _ existing: TapeCompositionBuilder.PlayerComposition,
        with newAssets: [(Int, HybridAssetLoader.ResolvedAsset)],
        for tape: Tape,
        builder: TapeCompositionBuilder
    ) async throws -> TapeCompositionBuilder.PlayerComposition? {
        // Single composition doesn't support extension
        return nil
    }
}

/// Phase 2 strategy: Extendable composition
final class ExtendableCompositionStrategy: CompositionStrategy {
    func buildInitialComposition(
        for tape: Tape,
        readyAssets: [(Int, HybridAssetLoader.ResolvedAsset)],
        skippedIndices: Set<Int>,
        builder: TapeCompositionBuilder
    ) async throws -> TapeCompositionBuilder.PlayerComposition {
        return try await builder.buildPlayerItem(
            for: tape,
            readyAssets: readyAssets,
            skippedIndices: skippedIndices
        )
    }
    
    func extendComposition(
        _ existing: TapeCompositionBuilder.PlayerComposition,
        with newAssets: [(Int, HybridAssetLoader.ResolvedAsset)],
        for tape: Tape,
        builder: TapeCompositionBuilder
    ) async throws -> TapeCompositionBuilder.PlayerComposition? {
        // Check if we have new assets to add
        guard !newAssets.isEmpty else { return nil }
        
        // Get existing asset indices
        let existingIndices = Set(existing.timeline.segments.map { $0.clipIndex })
        
        // Filter out assets we already have
        let trulyNewAssets = newAssets.filter { !existingIndices.contains($0.0) }
        guard !trulyNewAssets.isEmpty else { return nil }
        
        // Build extended composition with all assets (existing + new)
        // Note: In a real implementation, we'd merge compositions more efficiently
        // For now, rebuild with all available assets
        let allAssets = Array(existing.timeline.segments.map { segment -> (Int, HybridAssetLoader.ResolvedAsset)? in
            // Reconstruct from existing context
            // This is a simplification - in production, we'd cache ResolvedAsset instances
            return nil // Placeholder - would need to reconstruct from segment
        }.compactMap { $0 }) + trulyNewAssets
        
        // For now, return nil to indicate extension needs full rebuild
        // Phase 2 can implement proper merging later
        return nil
    }
}

