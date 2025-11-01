import Foundation
import AVFoundation
import Photos
import UIKit

/// Implements three-tier hybrid loading strategy:
/// 1. Fast Queue: Parallel loading for local files
/// 2. Sequential Queue: Photos/iCloud assets with overlap
/// 3. CPU Queue: Limited parallel (max 2) for image encodings
actor HybridAssetLoader {
    
    // MARK: - Configuration
    
    let windowDuration: TimeInterval = 15.0
    let overlapDelay: TimeInterval = 1.5 // Start next Photos asset after 1.5s
    let maxConcurrentEncodings: Int = 2
    
    // MARK: - Types
    
    enum LoadingResult {
        case ready(ResolvedAsset)
        case skipped(SkipReason)
        // Note: Assets still loading after window expires are tracked in loadingAssets array
    }
    
    enum SkipReason {
        case timeout
        case error(Error)
        case cancelled
    }
    
    struct WindowResult {
        let readyAssets: [(Int, ResolvedAsset)] // (clipIndex, asset)
        let loadingAssets: [Int] // Clip indices still loading
        let skippedAssets: [(Int, SkipReason)] // (clipIndex, reason)
    }
    
    struct ResolvedAsset {
        let clipIndex: Int
        let asset: AVAsset
        let clip: Clip
        let duration: CMTime
        let naturalSize: CGSize
        let preferredTransform: CGAffineTransform
        let hasAudio: Bool
        let isTemporary: Bool
        let motionEffect: TapeCompositionBuilder.MotionEffect?
    }
    
    // MARK: - Private Properties
    
    private let builder: TapeCompositionBuilder
    private var cancelled = false
    
    // MARK: - Initialization
    
    init(builder: TapeCompositionBuilder = TapeCompositionBuilder()) {
        self.builder = builder
    }
    
    // MARK: - Public API
    
    func loadWindow(clips: [Clip]) async -> WindowResult {
        cancelled = false
        let deadline = Date().addingTimeInterval(windowDuration)
        
        TapesLog.player.info("HybridAssetLoader: Starting loading window for \(clips.count) clips")
        
        // Separate clips by type
        // Strategy: Only clips with existing localURL files go to fast queue
        // Clips needing Photos API (no localURL or localURL missing) go to sequential queue
        // Image clips go to CPU queue
        var processedIndices = Set<Int>()
        
        // Fast queue: Only clips with localURL AND file exists
        let fileManager = FileManager.default
        let localClips = clips.enumerated().filter { offset, clip in
            guard let localURL = clip.localURL,
                  fileManager.fileExists(atPath: localURL.path) else { return false }
            processedIndices.insert(offset)
            return true
        }
        
        // Sequential queue: Video clips that need Photos API (no localURL file or only assetLocalId)
        let photosClips = clips.enumerated().filter { offset, clip in
            guard clip.clipType == .video && !processedIndices.contains(offset) else { return false }
            // Include if has assetLocalId (will load from Photos) OR if localURL exists but file doesn't
            let needsPhotos = clip.assetLocalId != nil
            if needsPhotos {
                processedIndices.insert(offset)
                return true
            }
            return false
        }
        
        // CPU queue: Image clips
        let imageClips = clips.enumerated().filter { offset, clip in
            guard clip.clipType == .image && !processedIndices.contains(offset) else { return false }
            processedIndices.insert(offset)
            return true
        }
        
        // Load all queues
        TapesLog.player.info("HybridAssetLoader: Starting parallel queue loading")
        
        let loadStartTime = Date()
        async let fastResults = loadFastQueue(localClips, deadline: deadline)
        async let sequentialResults = loadSequentialQueue(photosClips, deadline: deadline)
        async let cpuResults = loadCPUQueue(imageClips, deadline: deadline)
        
        // Collect all results
        TapesLog.player.info("HybridAssetLoader: Waiting for queue results...")
        
        // Collect results one by one with logging
        TapesLog.player.info("HybridAssetLoader: Waiting for fast queue...")
        let fast = await fastResults
        TapesLog.player.info("HybridAssetLoader: Fast queue completed with \(fast.count) results")
        
        TapesLog.player.info("HybridAssetLoader: Waiting for sequential queue...")
        let sequential = await sequentialResults
        TapesLog.player.info("HybridAssetLoader: Sequential queue completed with \(sequential.count) results")
        
        TapesLog.player.info("HybridAssetLoader: Waiting for CPU queue...")
        let cpu = await cpuResults
        TapesLog.player.info("HybridAssetLoader: CPU queue completed with \(cpu.count) results")
        
        let loadElapsed = Date().timeIntervalSince(loadStartTime)
        TapesLog.player.info("HybridAssetLoader: All queues completed in \(String(format: "%.2f", loadElapsed))s - processing results")
        
        // Combine results (all queues now return (Int, LoadingResult))
        var readyAssets: [(Int, ResolvedAsset)] = []
        var loadingAssets: [Int] = []
        var skippedAssets: [(Int, SkipReason)] = []
        
        // Process fast queue results
        for (index, result) in fast {
            switch result {
            case .ready(let asset):
                readyAssets.append((index, asset))
            case .skipped(let reason):
                skippedAssets.append((index, reason))
            }
        }
        
        // Process sequential queue results
        for (index, result) in sequential {
            switch result {
            case .ready(let asset):
                readyAssets.append((index, asset))
            case .skipped(let reason):
                skippedAssets.append((index, reason))
            }
        }
        
        // Process CPU queue results
        for (index, result) in cpu {
            switch result {
            case .ready(let asset):
                readyAssets.append((index, asset))
            case .skipped(let reason):
                skippedAssets.append((index, reason))
            }
        }
        
        // Assets still loading after window expires are tracked separately
        // They become ready later (if window extended) or timeout (if deadline passed)
        // For now, we'll track them as "timed out" if not ready by window end
        // Phase 2 can handle background continuation
        
        // Sort by clip index
        readyAssets.sort { $0.0 < $1.0 }
        loadingAssets.sort()
        skippedAssets.sort { $0.0 < $1.0 }
        
        TapesLog.player.info("HybridAssetLoader: Window complete - \(readyAssets.count) ready, \(loadingAssets.count) loading, \(skippedAssets.count) skipped")
        
        return WindowResult(
            readyAssets: readyAssets,
            loadingAssets: loadingAssets,
            skippedAssets: skippedAssets
        )
    }
    
    func cancel() {
        cancelled = true
        TapesLog.player.info("HybridAssetLoader: Cancelled")
    }
    
    // MARK: - Fast Queue (Parallel Local Files)
    
    private func loadFastQueue(
        _ clips: [(offset: Int, element: Clip)],
        deadline: Date
    ) async -> [(Int, LoadingResult)] {
        guard !clips.isEmpty else { return [] }
        
        TapesLog.player.info("HybridAssetLoader: Fast queue - loading \(clips.count) local files in parallel")
        
        return await withTaskGroup(of: (Int, LoadingResult).self) { group in
            for (offset, clip) in clips {
                // Check cancelled before creating task
                guard !cancelled else {
                    group.addTask { (offset, LoadingResult.skipped(.cancelled)) }
                    continue
                }
                
                group.addTask { [weak self] in
                    guard let self = self else { return (offset, LoadingResult.skipped(.cancelled)) }
                    let result = await self.resolveLocalFile(clip: clip, index: offset, deadline: deadline)
                    return (offset, result)
                }
            }
            
            var results: [(Int, LoadingResult)] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }
    
    private func resolveLocalFile(
        clip: Clip,
        index: Int,
        deadline: Date
    ) async -> LoadingResult {
        guard let localURL = clip.localURL else {
            TapesLog.player.warning("HybridAssetLoader: Local file \(index) has no localURL")
            // If no localURL, this shouldn't be in fast queue - should be in Photos queue
            // Return timeout so it gets handled by sequential queue
            return .skipped(.timeout)
        }
        
        let startTime = Date()
        TapesLog.player.info("HybridAssetLoader: Resolving local file \(index) from \(localURL.lastPathComponent)")
        
        do {
            let fileManager = FileManager.default
            var assetURL = localURL
            
            // Check if file exists at original path
            if !fileManager.fileExists(atPath: localURL.path) {
                // Try cache (same logic as old resolveVideoAsset)
                let cacheDirectory = fileManager.temporaryDirectory.appendingPathComponent("PlaybackCache", isDirectory: true)
                if !fileManager.fileExists(atPath: cacheDirectory.path) {
                    try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
                }
                
                let fileExtension = localURL.pathExtension.isEmpty ? "mov" : localURL.pathExtension
                let updatedAt = clip.updatedAt
                let timestamp = Int((updatedAt.timeIntervalSince1970 * 1_000).rounded())
                let versionComponent = "\(clip.id.uuidString)-\(timestamp)"
                let cachedURL = cacheDirectory.appendingPathComponent(versionComponent).appendingPathExtension(fileExtension)
                
                if fileManager.fileExists(atPath: cachedURL.path) {
                    TapesLog.player.info("HybridAssetLoader: Local file \(index) found in cache")
                    assetURL = cachedURL
                } else {
                    // File not found locally or in cache - fall back to Photos API
                    // But don't load Photos API in parallel (it's slow) - return skipped so it goes to sequential queue
                    TapesLog.player.warning("HybridAssetLoader: Local file \(index) not found, will load via Photos queue")
                    // Return timeout so it gets picked up by sequential/background loading
                    return .skipped(.timeout)
                }
            }
            
            let asset = AVURLAsset(url: assetURL)
            
            // Load required properties with timeout protection
            TapesLog.player.info("HybridAssetLoader: Loading properties for local file \(index)")
            let duration = try await asset.load(.duration)
            TapesLog.player.info("HybridAssetLoader: Duration loaded for local file \(index)")
            
            guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                return .skipped(.error(NSError(domain: "HybridAssetLoader", code: -3, userInfo: [NSLocalizedDescriptionKey: "No video track"])))
            }
            TapesLog.player.info("HybridAssetLoader: Video track loaded for local file \(index)")
            
            let naturalSize = try await videoTrack.load(.naturalSize)
            let preferredTransform = try await videoTrack.load(.preferredTransform)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            TapesLog.player.info("HybridAssetLoader: All properties loaded for local file \(index)")
            
            let elapsed = Date().timeIntervalSince(startTime)
            TapesLog.player.info("HybridAssetLoader: Local file \(index) resolved in \(String(format: "%.2f", elapsed))s")
            
            return .ready(ResolvedAsset(
                clipIndex: index,
                asset: asset,
                clip: clip,
                duration: duration,
                naturalSize: naturalSize,
                preferredTransform: preferredTransform,
                hasAudio: !audioTracks.isEmpty,
                isTemporary: false,
                motionEffect: nil
            ))
        } catch {
            let elapsed = Date().timeIntervalSince(startTime)
            TapesLog.player.error("HybridAssetLoader: Local file \(index) failed after \(String(format: "%.2f", elapsed))s: \(error.localizedDescription)")
            
            // If error loading local file, don't try Photos API here (would cause parallel Photos requests)
            // The sequential queue will handle Photos assets
            TapesLog.player.warning("HybridAssetLoader: Local file \(index) failed: \(error.localizedDescription)")
            return .skipped(.error(error))
        }
    }
    
    // MARK: - Sequential Queue (Photos/iCloud with Overlap)
    
    private func loadSequentialQueue(
        _ clips: [(offset: Int, element: Clip)],
        deadline: Date
    ) async -> [(Int, LoadingResult)] {
        guard !clips.isEmpty else { return [] }
        
        TapesLog.player.info("HybridAssetLoader: Sequential queue - loading \(clips.count) Photos assets with overlap")
        
        // Start all tasks with overlap delay between starts
        var tasks: [Task<(Int, LoadingResult), Never>] = []
        
        for (offset, clip) in clips {
            guard !cancelled else {
                TapesLog.player.info("HybridAssetLoader: Sequential queue cancelled, skipping clip \(offset)")
                tasks.append(Task { (offset, LoadingResult.skipped(.cancelled)) })
                continue
            }
            
            guard Date() < deadline else {
                TapesLog.player.warning("HybridAssetLoader: Window expired, skipping remaining Photos assets")
                tasks.append(Task { (offset, LoadingResult.skipped(.timeout)) })
                continue
            }
            
            // Create task for this clip (starts immediately)
            TapesLog.player.info("HybridAssetLoader: Sequential queue - starting task for clip \(offset)")
            let task = Task { [weak self] in
                guard let self = self else {
                    TapesLog.player.warning("HybridAssetLoader: Sequential queue - self deallocated for clip \(offset)")
                    return (offset, LoadingResult.skipped(.cancelled))
                }
                TapesLog.player.info("HybridAssetLoader: Sequential queue - task executing for clip \(offset)")
                let result = await self.resolvePhotosAsset(clip: clip, index: offset, deadline: deadline)
                TapesLog.player.info("HybridAssetLoader: Sequential queue - task completed for clip \(offset)")
                return (offset, result)
            }
            
            tasks.append(task)
            
            // Overlap: Wait delay before starting next (if not last clip)
            // This creates overlap - next starts while current is still loading
            if offset < clips.count - 1 {
                TapesLog.player.info("HybridAssetLoader: Sequential queue - waiting \(self.overlapDelay)s before starting clip \(offset + 1)")
                try? await Task.sleep(nanoseconds: UInt64(self.overlapDelay * 1_000_000_000))
            }
        }
        
        // Collect all results (they may complete in any order)
        TapesLog.player.info("HybridAssetLoader: Sequential queue - waiting for \(tasks.count) tasks to complete")
        var results: [(Int, LoadingResult)] = []
        for (index, task) in tasks.enumerated() {
            TapesLog.player.info("HybridAssetLoader: Sequential queue - waiting for task \(index)")
            let result = await task.value
            TapesLog.player.info("HybridAssetLoader: Sequential queue - got result for task \(index)")
            results.append(result)
        }
        
        TapesLog.player.info("HybridAssetLoader: Sequential queue - all \(results.count) tasks completed")
        return results
    }
    
    private func resolvePhotosAsset(
        clip: Clip,
        index: Int,
        deadline: Date
    ) async -> LoadingResult {
        guard let assetLocalId = clip.assetLocalId else {
            return .skipped(.error(NSError(domain: "HybridAssetLoader", code: -4, userInfo: [NSLocalizedDescriptionKey: "No asset local ID"])))
        }
        
        let startTime = Date()
        
        do {
            // Use builder's Photos resolution
            // Builder is NOT an actor, so we can call it directly from actor (no blocking)
            TapesLog.player.info("HybridAssetLoader: Calling resolveClipContext for Photos asset \(index)")
            let context = try await builder.resolveClipContext(for: clip, index: index)
            TapesLog.player.info("HybridAssetLoader: resolveClipContext completed for Photos asset \(index)")
            
            let elapsed = Date().timeIntervalSince(startTime)
            
            // Accept successful loads even if slightly past deadline
            // Only skip if loading took way too long (> 2x window duration)
            let maxAllowedTime = windowDuration * 2.0
            if elapsed > maxAllowedTime {
                TapesLog.player.warning("HybridAssetLoader: Photos asset \(index) resolved but took too long (\(String(format: "%.2f", elapsed))s)")
                return .skipped(.timeout)
            }
            
            TapesLog.player.info("HybridAssetLoader: Photos asset \(index) resolved in \(String(format: "%.2f", elapsed))s")
            
            return .ready(ResolvedAsset(
                clipIndex: index,
                asset: context.asset,
                clip: clip,
                duration: context.duration,
                naturalSize: context.naturalSize,
                preferredTransform: context.preferredTransform,
                hasAudio: context.hasAudio,
                isTemporary: context.isTemporaryAsset,
                motionEffect: context.motionEffect
            ))
        } catch {
            let elapsed = Date().timeIntervalSince(startTime)
            TapesLog.player.error("HybridAssetLoader: Photos asset \(index) failed after \(String(format: "%.2f", elapsed))s: \(error.localizedDescription)")
            
            // Return error, not timeout (timeout is for taking too long, not failing)
            return .skipped(.error(error))
        }
    }
    
    // MARK: - CPU Queue (Limited Parallel Image Encoding)
    
    private func loadCPUQueue(
        _ clips: [(offset: Int, element: Clip)],
        deadline: Date
    ) async -> [(Int, LoadingResult)] {
        guard !clips.isEmpty else { return [] }
        
        TapesLog.player.info("HybridAssetLoader: CPU queue - encoding \(clips.count) images (max \(self.maxConcurrentEncodings) concurrent)")
        
        let semaphore = DispatchSemaphore(value: self.maxConcurrentEncodings)
        
        return await withTaskGroup(of: (Int, LoadingResult).self) { group in
            for (offset, clip) in clips {
                guard !cancelled else {
                    group.addTask { (offset, .skipped(.cancelled)) }
                    continue
                }
                
                group.addTask { [weak self] in
                    guard let self = self else { return (offset, .skipped(.cancelled)) }
                    
                    await semaphore.wait()
                    defer { semaphore.signal() }
                    
                    let result = await self.encodeImage(clip: clip, index: offset, deadline: deadline)
                    return (offset, result)
                }
            }
            
            var results: [(Int, LoadingResult)] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }
    
    private func encodeImage(
        clip: Clip,
        index: Int,
        deadline: Date
    ) async -> LoadingResult {
        let startTime = Date()
        
        // Check deadline before starting (don't start if already expired)
        guard Date() < deadline else {
            TapesLog.player.warning("HybridAssetLoader: Image \(index) skipped - deadline expired before start")
            return .skipped(.timeout)
        }
        
        do {
            // Use builder's image encoding
            // Builder is NOT an actor, so we can call it directly from actor (no blocking)
            TapesLog.player.info("HybridAssetLoader: Calling resolveClipContext for image \(index)")
            let context = try await builder.resolveClipContext(for: clip, index: index)
            TapesLog.player.info("HybridAssetLoader: resolveClipContext completed for image \(index)")
            
            let elapsed = Date().timeIntervalSince(startTime)
            
            // Accept successful encodings even if slightly past deadline
            // Only skip if encoding took way too long (> 2x window duration)
            let maxAllowedTime = windowDuration * 2.0
            if elapsed > maxAllowedTime {
                TapesLog.player.warning("HybridAssetLoader: Image \(index) encoded but took too long (\(String(format: "%.2f", elapsed))s)")
                return .skipped(.timeout)
            }
            
            TapesLog.player.info("HybridAssetLoader: Image \(index) encoded in \(String(format: "%.2f", elapsed))s")
            
            return .ready(ResolvedAsset(
                clipIndex: index,
                asset: context.asset,
                clip: clip,
                duration: context.duration,
                naturalSize: context.naturalSize,
                preferredTransform: context.preferredTransform,
                hasAudio: context.hasAudio,
                isTemporary: context.isTemporaryAsset,
                motionEffect: context.motionEffect
            ))
        } catch {
            let elapsed = Date().timeIntervalSince(startTime)
            TapesLog.player.error("HybridAssetLoader: Image \(index) encoding failed after \(String(format: "%.2f", elapsed))s: \(error.localizedDescription)")
            
            // Only skip on error if it happened early enough that we might retry
            // Otherwise, still return error (not timeout)
            return .skipped(.error(error))
        }
    }
}

// Note: LoadingResult doesn't have clipIndex - we track indices separately in results arrays

