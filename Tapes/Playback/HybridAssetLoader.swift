import Foundation
import AVFoundation
import Photos
import UIKit

/// Implements three-tier hybrid loading strategy:
/// 1. Fast Queue: Parallel loading for local files
/// 2. Sequential Queue: Photos/iCloud assets with overlap
/// 3. CPU Queue: Limited parallel (max 2) for image encodings
/// 
/// NOTE: Regular class (not actor) to avoid blocking Photos API callbacks.
/// Actor isolation was preventing Photos API callbacks from firing.
/// The old PlaybackPreparationCoordinator (regular class) worked perfectly.
final class HybridAssetLoader {
    
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
        let loadStartTime = Date()
        async let fastResults = loadFastQueue(localClips, deadline: deadline)
        async let sequentialResults = loadSequentialQueue(photosClips, deadline: deadline)
        async let cpuResults = loadCPUQueue(imageClips, deadline: deadline)
        
        // Wait for all queues
        let fast = await fastResults
        let sequential = await sequentialResults
        let cpu = await cpuResults
        
        let loadElapsed = Date().timeIntervalSince(loadStartTime)
        TapesLog.player.info("HybridAssetLoader: Queues completed in \(String(format: "%.2f", loadElapsed))s (fast: \(fast.count), sequential: \(sequential.count), cpu: \(cpu.count))")
        
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
            // Resolve local file
        
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
            
            // Load required properties
            let duration = try await asset.load(.duration)
            
            guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                return .skipped(.error(NSError(domain: "HybridAssetLoader", code: -3, userInfo: [NSLocalizedDescriptionKey: "No video track"])))
            }
            
            let naturalSize = try await videoTrack.load(.naturalSize)
            let preferredTransform = try await videoTrack.load(.preferredTransform)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            
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
        
        TapesLog.player.info("HybridAssetLoader: Sequential queue - loading \(clips.count) Photos assets")
        
        // CRITICAL FIX: Load sequentially with overlap (not all at once)
        // Photos framework has limits - creating 5+ requests simultaneously exhausts it
        // Load one at a time with overlap delay to prevent framework exhaustion
        // ATTEMPT #1: Don't block waiting for in-progress loads - break immediately when deadline expires
        let builder = self.builder
        var results: [(Int, LoadingResult)] = []
        var currentTask: Task<(Int, LoadingResult), Never>?
        
        for (offset, clip) in clips {
            guard !cancelled else {
                TapesLog.player.info("HybridAssetLoader: Sequential queue cancelled, skipping clip \(offset)")
                results.append((offset, .skipped(.cancelled)))
                continue
            }
            
            // Check deadline before starting - if expired, return immediately with what we have
            guard Date() < deadline else {
                TapesLog.player.warning("HybridAssetLoader: Window expired - returning \(results.count) ready assets")
                // Don't mark remaining clips as skipped - they haven't started yet
                // Background service will handle them
                break
            }
            
            // If we have a previous task still running, try to collect it quickly
            // Don't block too long - if deadline is close, let it finish in background
            if let task = currentTask {
                let timeRemaining = deadline.timeIntervalSince(Date())
                if timeRemaining > 0.3 {
                    // Try to get result, but don't wait too long
                    // This is a race - task might finish or we might time out
                    do {
                        // Use async let with timeout pattern
                        async let taskResult = task.value
                        try await withThrowingTaskGroup(of: (Int, LoadingResult).self) { group in
                            group.addTask {
                                await taskResult
                            }
                            group.addTask {
                                try await Task.sleep(nanoseconds: UInt64(0.3 * 1_000_000_000))
                                throw CancellationError()
                            }
                            
                            if let result = try? await group.next() {
                                group.cancelAll()
                                results.append(result)
                            } else {
                                group.cancelAll()
                                TapesLog.player.info("HybridAssetLoader: Previous task timeout, continuing in background")
                            }
                        }
                    } catch {
                        // Task still loading - will continue in background
                        TapesLog.player.info("HybridAssetLoader: Previous task still loading, continuing in background")
                    }
                } else {
                    // Deadline too close - don't wait
                    TapesLog.player.info("HybridAssetLoader: Deadline too close, not waiting for previous task")
                }
            }
            
            // Start loading this clip (don't await - let it run)
            currentTask = Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else {
                    return (offset, LoadingResult.skipped(.cancelled))
                }
                let loadingResult = await self.resolvePhotosAsset(clip: clip, index: offset, deadline: deadline, builder: builder)
                return (offset, loadingResult)
            }
            
            // Overlap: Wait delay before starting next (if not last clip)
            // This creates overlap - next starts while current is still loading (if it takes longer than delay)
            if offset < clips.count - 1 {
                try? await Task.sleep(nanoseconds: UInt64(self.overlapDelay * 1_000_000_000))
            }
        }
        
        // Wait for final task if we still have time
        if let task = currentTask, Date() < deadline {
            let timeRemaining = deadline.timeIntervalSince(Date())
            if timeRemaining > 0.2 {
                // Try to collect final task result
                do {
                    async let taskResult = task.value
                    try await withThrowingTaskGroup(of: (Int, LoadingResult).self) { group in
                        group.addTask {
                            await taskResult
                        }
                        group.addTask {
                            try await Task.sleep(nanoseconds: UInt64(0.3 * 1_000_000_000))
                            throw CancellationError()
                        }
                        
                        if let result = try? await group.next() {
                            group.cancelAll()
                            results.append(result)
                        } else {
                            group.cancelAll()
                            TapesLog.player.info("HybridAssetLoader: Final task timeout, will continue in background")
                        }
                    }
                } catch {
                    // Task still loading - will continue in background
                    TapesLog.player.info("HybridAssetLoader: Final task still loading, will continue in background")
                }
            }
        }
        
        // Summary logged by caller
        return results
    }
    
    private func resolvePhotosAsset(
        clip: Clip,
        index: Int,
        deadline: Date,
        builder: TapeCompositionBuilder
    ) async -> LoadingResult {
        guard let assetLocalId = clip.assetLocalId else {
            return .skipped(.error(NSError(domain: "HybridAssetLoader", code: -4, userInfo: [NSLocalizedDescriptionKey: "No asset local ID"])))
        }
        
        let startTime = Date()
        
        do {
            // Use builder's Photos resolution - we're a regular class now, no actor blocking
            // This matches old PlaybackPreparationCoordinator pattern exactly
            let context = try await builder.resolveClipContext(for: clip, index: index)
            
            let elapsed = Date().timeIntervalSince(startTime)
            
            // Accept successful loads even if slightly past deadline
            // Only skip if loading took way too long (> 2x window duration)
            let maxAllowedTime = windowDuration * 2.0
            if elapsed > maxAllowedTime {
                TapesLog.player.warning("HybridAssetLoader: Photos asset \(index) resolved but took too long (\(String(format: "%.2f", elapsed))s)")
                return .skipped(.timeout)
            }
            
            // Success - logged at summary level
            
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
        
        // CRITICAL FIX: Don't create all tasks at once - Photos API gets exhausted
        // Create tasks sequentially as slots become available (producer-consumer pattern)
        let builder = self.builder
        var results: [(Int, LoadingResult)] = []
        var clipIndex = 0
        
        // Use AsyncSemaphore for proper async/await support
        let semaphore = AsyncSemaphore(value: self.maxConcurrentEncodings)
        
        await withTaskGroup(of: (Int, LoadingResult).self) { group in
            // Start initial batch (maxConcurrentEncodings tasks)
            for i in 0..<min(self.maxConcurrentEncodings, clips.count) {
                let (offset, clip) = clips[i]
                guard !cancelled else {
                    group.addTask { (offset, .skipped(.cancelled)) }
                    continue
                }
                
                clipIndex = i + 1
                group.addTask { [weak self] in
                    guard let self = self else { return (offset, .skipped(.cancelled)) }
                    
                    // CRITICAL: Wait on semaphore BEFORE creating detached task
                    // This ensures Photos API requests are throttled properly
                    await semaphore.wait()
                    defer { semaphore.signal() }
                    
                    // Run Photos API call in detached context (only after semaphore allows it)
                    let result = await Task.detached(priority: .userInitiated) {
                        return await self.encodeImage(clip: clip, index: offset, deadline: deadline, builder: builder)
                    }.value
                    return (offset, result)
                }
            }
            
            // As tasks complete, start next one (producer-consumer)
            for await result in group {
                results.append(result)
                
                // Start next task if more clips to process
                if clipIndex < clips.count && !cancelled {
                    let (offset, clip) = clips[clipIndex]
                    clipIndex += 1
                    
                    group.addTask { [weak self] in
                        guard let self = self else { return (offset, .skipped(.cancelled)) }
                        
                        // CRITICAL: Wait on semaphore BEFORE creating detached task
                        // This ensures Photos API requests are throttled properly
                        await semaphore.wait()
                        defer { semaphore.signal() }
                        
                        // Run Photos API call in detached context (only after semaphore allows it)
                        let result = await Task.detached(priority: .userInitiated) {
                            return await self.encodeImage(clip: clip, index: offset, deadline: deadline, builder: builder)
                        }.value
                        return (offset, result)
                    }
                }
            }
        }
        
        return results
    }
    
    private func encodeImage(
        clip: Clip,
        index: Int,
        deadline: Date,
        builder: TapeCompositionBuilder
    ) async -> LoadingResult {
        let startTime = Date()
        
        // Check deadline before starting (don't start if already expired)
        guard Date() < deadline else {
            TapesLog.player.warning("HybridAssetLoader: Image \(index) skipped - deadline expired before start")
            return .skipped(.timeout)
        }
        
        do {
            // Use builder's image encoding - we're a regular class now, no actor blocking
            // This matches old PlaybackPreparationCoordinator pattern exactly
            let context = try await builder.resolveClipContext(for: clip, index: index)
            
            let elapsed = Date().timeIntervalSince(startTime)
            
            // Accept successful encodings even if slightly past deadline
            // Only skip if encoding took way too long (> 2x window duration)
            let maxAllowedTime = windowDuration * 2.0
            if elapsed > maxAllowedTime {
                TapesLog.player.warning("HybridAssetLoader: Image \(index) encoded but took too long (\(String(format: "%.2f", elapsed))s)")
                return .skipped(.timeout)
            }
            
            // Success - logged at summary level
            
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


