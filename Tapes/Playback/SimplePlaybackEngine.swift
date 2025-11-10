import Foundation
import AVFoundation
import os

/// Simple, robust playback engine.
/// Loads assets, builds composition with placeholders, plays. That's it.
@MainActor
final class SimplePlaybackEngine: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isBuffering: Bool = false
    @Published private(set) var isFinished: Bool = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var currentClipIndex: Int = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var error: String?
    @Published private(set) var playbackSpeed: Float = 1.0
    @Published private(set) var isPreparing = false
    
    private(set) var player: AVPlayer?
    private(set) var timeline: TapeCompositionBuilder.Timeline?
    
    // MARK: - Private Properties
    
    private let builder = TapeCompositionBuilder()
    private var timeObserver: Any?
    private var playerEndObserver: NSObjectProtocol?
    private var playerStallObserver: NSObjectProtocol?
    private var currentTape: Tape?
    private var prepareTask: Task<Void, Never>?
    
    // Background loading
    private var backgroundTask: Task<Void, Never>?
    private var loadedAssets: [Int: ResolvedAsset] = [:]
    
    // Seek protection to prevent time observer from overriding clip index
    private var isSeekingToClip: Bool = false
    
    // Simple resolved asset type
    private struct ResolvedAsset {
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
    
    // MARK: - Public API
    
    func prepare(tape: Tape) async {
        guard !isPreparing else { return }
        
        isPreparing = true
        isBuffering = true
        setError(nil)
        currentTape = tape
        
        prepareTask?.cancel()
        prepareTask = Task {
            defer {
                isPreparing = false
            }
            
            do {
                let startTime = Date()
                TapesLog.player.info("SimplePlaybackEngine: Starting preparation for \(tape.clips.count) clips")
                
                // Load assets in parallel - no timeout, let them all load
                let readyAssets = await loadAssets(tape.clips)
                
                guard !Task.isCancelled else { return }
                
                // Store loaded assets
                for (index, asset) in readyAssets {
                    loadedAssets[index] = asset
                }
                
                // Convert to HybridAssetLoader.ResolvedAsset format for builder
                let builderAssets = readyAssets.map { tuple in
                    let (index, asset) = tuple
                    return (index, HybridAssetLoader.ResolvedAsset(
                        clipIndex: asset.clipIndex,
                        asset: asset.asset,
                        clip: asset.clip,
                        duration: asset.duration,
                        naturalSize: asset.naturalSize,
                        preferredTransform: asset.preferredTransform,
                        hasAudio: asset.hasAudio,
                        isTemporary: asset.isTemporary,
                        motionEffect: asset.motionEffect
                    ))
                }
                
                // CRITICAL FIX: Use placeholder-building method that handles missing assets gracefully
                // This allows playback to start even with 0 assets (all placeholders)
                // Background loading will swap in real assets as they become available
                let buildStartTime = Date()
                let composition = try await builder.buildPlayerItem(
                    for: tape,
                    readyAssets: builderAssets,
                    skippedIndices: []
                )
                
                guard !Task.isCancelled else { return }
                
                // Calculate how long we've spent so far
                let totalElapsed = Date().timeIntervalSince(startTime)
                
                // CRITICAL FIX: Start playback immediately - don't wait additional time
                // For large tapes, starting with placeholders is acceptable and expected
                // Background loading will swap in real assets as they become available
                // Install and play - start immediately with whatever we have (even if 0 assets = all placeholders)
                await install(composition: composition)
                
                let ttfmp = Date().timeIntervalSince(startTime)
                TapesLog.player.info("SimplePlaybackEngine: TTFMP = \(String(format: "%.2f", ttfmp))s (ready: \(readyAssets.count)/\(tape.clips.count))")
                
                // Start background loading for remaining assets
                startBackgroundLoading(tape: tape, loadedIndices: Set(readyAssets.map { $0.0 }))
                
            } catch {
                TapesLog.player.error("SimplePlaybackEngine: Preparation failed: \(error.localizedDescription)")
                setError(error.localizedDescription)
                isBuffering = false
            }
        }
        
        await prepareTask?.value
    }
    
    func play() {
        guard let player = player else { return }
        player.play()
        isPlaying = true
    }
    
    func pause() {
        guard let player = player else { return }
        player.pause()
        isPlaying = false
    }
    
    func setPlaybackSpeed(_ speed: Float) {
        guard let player = player else { return }
        let clampedSpeed = max(0.5, min(2.0, speed))
        player.rate = clampedSpeed
        playbackSpeed = clampedSpeed
    }
    
    func seek(to time: Double) {
        guard let player = player else { return }
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime)
        currentTime = time
        // Don't update clip index here if we're seeking to a specific clip
        // (seekToClip handles that explicitly to prevent race conditions)
        if !isSeekingToClip {
            updateCurrentClipIndex()
        }
    }
    
    func seekToClip(at index: Int) {
        guard let timeline = timeline else { return }
        
        // CRITICAL FIX: Find the requested clip, or the next available clip if it doesn't exist
        // This prevents silent failures when skipping forward from clips that aren't in the timeline
        var targetIndex = index
        var segment = timeline.segments.first(where: { $0.clipIndex == targetIndex })
        
        // If clip not found, find next available clip in timeline
        if segment == nil {
            // Find next clip in timeline that exists (sorted by clipIndex)
            let availableIndices = timeline.segments.map { $0.clipIndex }.sorted()
            if let nextAvailable = availableIndices.first(where: { $0 > currentClipIndex }) {
                targetIndex = nextAvailable
                segment = timeline.segments.first(where: { $0.clipIndex == targetIndex })
                TapesLog.player.warning("SimplePlaybackEngine: Clip \(index) not found in timeline, seeking to next available clip \(targetIndex)")
            } else {
                // No next clip available - might be at end
                TapesLog.player.warning("SimplePlaybackEngine: Clip \(index) not found in timeline and no next clip available")
                return
            }
        }
        
        // Prevent seeking to same clip (after finding target)
        guard targetIndex != currentClipIndex else {
            TapesLog.player.info("SimplePlaybackEngine: Already at clip \(targetIndex), skipping seek")
            return
        }
        
        guard let segment = segment else { return }
        
        // CRITICAL FIX: Set flag to prevent time observer from overriding clip index during seek
        isSeekingToClip = true
        
        // Update clip index BEFORE seeking to prevent updateCurrentClipIndex from overriding it
        currentClipIndex = targetIndex
        
        let seekTime = segment.timeRange.start
        let seconds = CMTimeGetSeconds(seekTime)
        seek(to: seconds)
        
        TapesLog.player.info("SimplePlaybackEngine: Seek to clip \(targetIndex) at time \(String(format: "%.2f", seconds))s")
        
        // Clear flag after delay to ensure seek completes and UI updates
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            await MainActor.run {
                self?.isSeekingToClip = false
            }
        }
    }
    
    func teardown() {
        TapesLog.player.info("SimplePlaybackEngine: Teardown")
        prepareTask?.cancel()
        backgroundTask?.cancel()
        removeObservers()
        player?.pause()
        player = nil
        isPlaying = false
        isBuffering = false
        isFinished = false
        currentTime = 0
        currentClipIndex = 0
        duration = 0
        error = nil
        timeline = nil
        currentTape = nil
        loadedAssets.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func loadAssets(_ clips: [Clip]) async -> [(Int, ResolvedAsset)] {
        let startTime = Date()
        var results: [(Int, ResolvedAsset)] = []
        
        // CRITICAL MEMORY FIX: Limit concurrent image loading to prevent memory exhaustion
        // Images are memory-intensive (especially Photos assets), so limit to 3 concurrent
        // Videos can load in parallel (they're streamed, not fully loaded into memory)
        let maxConcurrentImages = 3
        let maxConcurrentVideos = 10
        
        // Separate clips by type for different concurrency limits
        var imageClips: [(Int, Clip)] = []
        var videoClips: [(Int, Clip)] = []
        for (index, clip) in clips.enumerated() {
            if clip.clipType == .image {
                imageClips.append((index, clip))
            } else {
                videoClips.append((index, clip))
            }
        }
        
        // Use AsyncSemaphore for proper concurrency control
        let imageSemaphore = AsyncSemaphore(value: maxConcurrentImages)
        let videoSemaphore = AsyncSemaphore(value: maxConcurrentVideos)
        
        await withTaskGroup(of: (Int, ResolvedAsset?).self) { group in
            // Start video tasks (higher concurrency)
            for (index, clip) in videoClips {
                guard !Task.isCancelled else { break }
                
                group.addTask { [weak self] in
                    guard let self = self else { return (index, nil) }
                    
                    await videoSemaphore.wait()
                    defer { videoSemaphore.signal() }
                    
                    return await self.loadSingleAsset(clip: clip, index: index)
                }
            }
            
            // Start image tasks (lower concurrency to prevent memory issues)
            for (index, clip) in imageClips {
                guard !Task.isCancelled else { break }
                
                group.addTask { [weak self] in
                    guard let self = self else { return (index, nil) }
                    
                    await imageSemaphore.wait()
                    defer { imageSemaphore.signal() }
                    
                    return await self.loadSingleAsset(clip: clip, index: index)
                }
            }
            
            // Collect all results - no deadline, let everything load
            for await (index, asset) in group {
                if let asset = asset {
                    results.append((index, asset))
                }
            }
        }
        
        let loadTime = Date().timeIntervalSince(startTime)
        TapesLog.player.info("SimplePlaybackEngine: Loaded \(results.count)/\(clips.count) assets in \(String(format: "%.2f", loadTime))s")
        
        return results.sorted { $0.0 < $1.0 }
    }
    
    private func loadSingleAsset(
        clip: Clip,
        index: Int
    ) async -> (Int, ResolvedAsset?) {
        do {
            let context = try await builder.resolveClipContext(for: clip, index: index)
            
            let resolved = ResolvedAsset(
                clipIndex: index,
                asset: context.asset,
                clip: context.clip,
                duration: context.duration,
                naturalSize: context.naturalSize,
                preferredTransform: context.preferredTransform,
                hasAudio: context.hasAudio,
                isTemporary: context.isTemporaryAsset,
                motionEffect: context.motionEffect
            )
            
            return (index, resolved)
        } catch {
            TapesLog.player.warning("SimplePlaybackEngine: Failed to load clip \(index): \(error.localizedDescription)")
            return (index, nil)
        }
    }
    
    private func install(composition: TapeCompositionBuilder.PlayerComposition) async {
        removeObservers()
        player?.pause()
        player = nil
        
        let newPlayer = AVPlayer(playerItem: composition.playerItem)
        newPlayer.actionAtItemEnd = .pause
        
        timeline = composition.timeline
        duration = CMTimeGetSeconds(composition.timeline.totalDuration)
        
        installObservers(player: newPlayer)
        
        player = newPlayer
        newPlayer.play()
        isPlaying = true
        isBuffering = false
        isFinished = false
        currentTime = 0
        
        if let firstSegment = composition.timeline.segments.first {
            currentClipIndex = firstSegment.clipIndex
        }
        
        TapesLog.player.info("SimplePlaybackEngine: Playback started")
    }
    
    private func startBackgroundLoading(tape: Tape, loadedIndices: Set<Int>) {
        backgroundTask?.cancel()
        
        backgroundTask = Task { [weak self] in
            guard let self = self else { return }
            
            // Load remaining clips in background
            var remainingIndices: [Int] = []
            for (index, _) in tape.clips.enumerated() {
                if !loadedIndices.contains(index) {
                    remainingIndices.append(index)
                }
            }
            
            if remainingIndices.isEmpty {
                TapesLog.player.info("SimplePlaybackEngine: All clips already loaded")
                return
            }
            
            TapesLog.player.info("SimplePlaybackEngine: Background loading \(remainingIndices.count) remaining clips")
            
            // Load in small batches to avoid overwhelming system
            let batchSize = 5
            for batchStart in stride(from: 0, to: remainingIndices.count, by: batchSize) {
                guard !Task.isCancelled else { break }
                
                let batch = Array(remainingIndices[batchStart..<min(batchStart + batchSize, remainingIndices.count)])
                
                await withTaskGroup(of: (Int, ResolvedAsset?).self) { group in
                    for index in batch {
                        let clip = tape.clips[index]
                        group.addTask { [weak self] in
                            guard let self = self else { return (index, nil) }
                            
                            do {
                                let context = try await self.builder.resolveClipContext(for: clip, index: index)
                                
                                let resolved = ResolvedAsset(
                                    clipIndex: index,
                                    asset: context.asset,
                                    clip: context.clip,
                                    duration: context.duration,
                                    naturalSize: context.naturalSize,
                                    preferredTransform: context.preferredTransform,
                                    hasAudio: context.hasAudio,
                                    isTemporary: context.isTemporaryAsset,
                                    motionEffect: context.motionEffect
                                )
                                
                                return (index, resolved)
                            } catch {
                                return (index, nil)
                            }
                        }
                    }
                    
                    for await (index, asset) in group {
                        if let asset = asset {
                            await MainActor.run {
                                self.loadedAssets[index] = asset
                            }
                        }
                    }
                }
                
                // Small delay between batches
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            }
            
            TapesLog.player.info("SimplePlaybackEngine: Background loading complete")
        }
    }
    
    private func installObservers(player: AVPlayer) {
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            
            // CRITICAL: Don't update clip index if we're seeking to a specific clip
            // This prevents race conditions where the time observer overrides the clip index
            // we explicitly set in seekToClip
            guard !self.isSeekingToClip else {
                return
            }
            
            let newTime = CMTimeGetSeconds(time)
            self.currentTime = newTime
            self.updateCurrentClipIndex()
        }
        
        if let item = player.currentItem {
            installObserversForItem(item)
        }
    }
    
    private func installObserversForItem(_ item: AVPlayerItem) {
        playerEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.isFinished = true
            self.isPlaying = false
        }
        
        playerStallObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.isBuffering = true
        }
        
        let duration = item.duration
        if CMTimeCompare(duration, .invalid) != 0 {
            self.duration = CMTimeGetSeconds(duration)
        }
    }
    
    private func removeObservers() {
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        if let observer = playerEndObserver {
            NotificationCenter.default.removeObserver(observer)
            playerEndObserver = nil
        }
        
        if let observer = playerStallObserver {
            NotificationCenter.default.removeObserver(observer)
            playerStallObserver = nil
        }
    }
    
    private func updateCurrentClipIndex() {
        guard let timeline = timeline else { return }
        
        // Don't update if we're seeking to a specific clip (prevents race conditions)
        guard !isSeekingToClip else {
            return
        }
        
        for segment in timeline.segments {
            let segmentStart = CMTimeGetSeconds(segment.timeRange.start)
            let segmentEnd = segmentStart + CMTimeGetSeconds(segment.timeRange.duration)
            
            if currentTime >= segmentStart && currentTime < segmentEnd {
                currentClipIndex = segment.clipIndex
                return
            }
        }
        
        if !timeline.segments.isEmpty {
            currentClipIndex = timeline.segments.last!.clipIndex
        }
    }
    
    func setError(_ message: String?) {
        error = message
        isBuffering = false
    }
}

