import Foundation
import AVFoundation
import os

/// Manages AVPlayer instance and playback state for the new hybrid loading engine.
/// Handles skip behavior and provides @Published state for UI binding.
@MainActor
final class PlaybackEngine: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isBuffering: Bool = false
    @Published private(set) var isFinished: Bool = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var currentClipIndex: Int = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var error: String?
    @Published private(set) var playbackSpeed: Float = 1.0
    
    private(set) var player: AVPlayer?
    private(set) var timeline: TapeCompositionBuilder.Timeline?
    
    // Expose skipHandler for UI access (read-only)
    var skipHandler: SkipHandler? {
        return _skipHandler
    }
    
    // MARK: - Private Properties
    
    private let builder = TapeCompositionBuilder()
    private let loader = HybridAssetLoader()
    private var _skipHandler: SkipHandler?
    
    // Phase 2 components
    private let backgroundService: BackgroundAssetService
    private let extensionManager: CompositionExtensionManager
    
    // Store tape for diagnostics
    private var currentTape: Tape?
    
    private var timeObserver: Any?
    private var playerEndObserver: NSObjectProtocol?
    private var playerStallObserver: NSObjectProtocol?
    
    @Published private(set) var isPreparing = false
    private var currentPrepareTask: Task<Void, Never>?
    private var extensionCheckTask: Task<Void, Never>?
    
    // Flag to prevent index updates during explicit seek operations
    private var isSeekingToClip = false
    
    // Flag to prevent time observer updates during composition swaps
    // This prevents race conditions where replaceCurrentItem resets time to 0
    private var isSwappingComposition = false
    
    // Debounce skip operations to prevent rapid-fire taps
    private var lastSkipTime: Date = .distantPast
    private let skipDebounceInterval: TimeInterval = 0.3
    
    // MARK: - Initialization
    
    init() {
        let sharedLoader = HybridAssetLoader()
        self.backgroundService = BackgroundAssetService(loader: sharedLoader)
        self.extensionManager = CompositionExtensionManager()
        // Note: loader is created separately but can share builder
        TapesLog.player.info("PlaybackEngine: Initialized")
    }
    
    deinit {
        Task { @MainActor [weak self] in
            self?.teardown()
        }
    }
    
    // MARK: - Public API
    
    /// Prepare playback for a tape using hybrid loading strategy
    func prepare(tape: Tape) async {
        // Prevent multiple simultaneous prepare calls
        guard !isPreparing else {
            TapesLog.player.warning("PlaybackEngine: Prepare already in progress, ignoring duplicate call")
            return
        }
        
        // Cancel any existing preparation
        currentPrepareTask?.cancel()
        
        // Store tape for diagnostics
        currentTape = tape
        
        guard !tape.clips.isEmpty else {
            setError("This tape has no clips to play.")
            return
        }
        
        isPreparing = true
        isBuffering = true
        setError(nil)
        
        let startTime = Date()
        TapesLog.player.info("PlaybackEngine: Starting preparation for tape with \(tape.clips.count) clips")
        
        // Wrap in a task so we can track it
        currentPrepareTask = Task {
            defer {
                isPreparing = false
                currentPrepareTask = nil
            }
            
            do {
                // Load assets using hybrid strategy
                let windowResult = await loader.loadWindow(clips: tape.clips)
            
                // Check if task was cancelled
                guard !Task.isCancelled else {
                    TapesLog.player.info("PlaybackEngine: Preparation cancelled")
                    return
                }
                
                // Check if we have any ready assets
                // CRITICAL FIX: Start playback immediately with whatever is ready (or placeholders)
                // Don't wait additional time - background loading will continue and swap seamlessly
                if windowResult.readyAssets.isEmpty {
                    // If still no ready assets, show error
                    if windowResult.skippedAssets.count == tape.clips.count {
                        setError("Unable to load any clips for this tape. Please check your network connection and try again.")
                        isBuffering = false
                        return
                    }
                    
                    // Fall through - will build with placeholders for missing clips
                    // Background loading will continue and swap seamlessly when assets load
                    TapesLog.player.info("PlaybackEngine: No assets ready, starting with placeholders. Background loading will continue.")
                }
                
                // Create skip handler
                let skippedIndices = Set(windowResult.skippedAssets.map { $0.0 })
                let readyIndices = Set(windowResult.readyAssets.map { $0.0 })
                let allIndices = Array(0..<tape.clips.count)
                
                // Log detailed skip information for debugging
                TapesLog.player.info("PlaybackEngine: Skip summary - ready: \(readyIndices.sorted()), skipped: \(skippedIndices.sorted())")
                for (index, reason) in windowResult.skippedAssets {
                    let reasonStr: String
                    switch reason {
                    case .timeout: reasonStr = "timeout"
                    case .error(let err): reasonStr = "error: \(err.localizedDescription)"
                    case .cancelled: reasonStr = "cancelled"
                    }
                    TapesLog.player.warning("PlaybackEngine: Clip \(index) skipped: \(reasonStr)")
                }
                
                _skipHandler = SkipHandler(
                    skippedIndices: skippedIndices,
                    readyIndices: readyIndices,
                    allClipIndices: allIndices
                )
                
                // Check for high skip rate
                let stats = _skipHandler!.getSkipStats()
                if stats.skipped > stats.ready {
                    TapesLog.player.warning("PlaybackEngine: High skip rate - \(stats.skipped) skipped, \(stats.ready) ready")
                }
                
                // Check if task was cancelled before building
                guard !Task.isCancelled else {
                    TapesLog.player.info("PlaybackEngine: Preparation cancelled before composition build")
                    return
                }
                
                // Build initial composition using extension manager
                let initialComposition = try await extensionManager.buildInitial(
                    for: tape,
                    readyAssets: windowResult.readyAssets,
                    skippedIndices: skippedIndices
                )
                
                // Check if task was cancelled after building
                guard !Task.isCancelled else {
                    TapesLog.player.info("PlaybackEngine: Preparation cancelled after composition build")
                    return
                }
                
                let elapsed = Date().timeIntervalSince(startTime)
                TapesLog.player.info("PlaybackEngine: Preparation complete in \(String(format: "%.2f", elapsed))s - \(stats.ready) ready, \(stats.skipped) skipped")
                
                // Install composition
                await install(composition: initialComposition)
                
                // Start background loading and extension checks
                await startBackgroundLoading(tape: tape, skippedIndices: skippedIndices, windowResult: windowResult)
                startExtensionChecking(tape: tape)
                
                // Calculate TTFMP
                let ttfmp = Date().timeIntervalSince(startTime)
                TapesLog.player.info("PlaybackEngine: TTFMP = \(String(format: "%.2f", ttfmp))s")
                
            } catch {
                TapesLog.player.error("PlaybackEngine: Preparation failed: \(error.localizedDescription)")
                setError(error.localizedDescription)
                isBuffering = false
            }
        }
        
        await currentPrepareTask?.value
    }
    
    /// Install initial composition into player (first time)
    private func install(composition: TapeCompositionBuilder.PlayerComposition) async {
        // If player already exists and is playing, log a warning (should use swap instead)
        if let existingPlayer = player, isPlaying {
            TapesLog.player.warning("PlaybackEngine: Install called while playback is active - this will reset playback!")
        }
        
        // Remove existing observers (but don't call full teardown which cancels preparation)
        removeObservers()
        
        // Pause and clear old player (but don't cancel loader)
        player?.pause()
        player = nil
        
        // Create new player
        let playerItem = composition.playerItem
        let newPlayer = AVPlayer(playerItem: playerItem)
        newPlayer.actionAtItemEnd = .pause
        
        // Store timeline for skip behavior
        timeline = composition.timeline
        duration = CMTimeGetSeconds(composition.timeline.totalDuration)
        
        // Install observers
        installObservers(player: newPlayer)
        
        player = newPlayer
        
        // Auto-play
        newPlayer.play()
        isPlaying = true
        isBuffering = false
        isFinished = false
        currentTime = 0
        
        // Set initial clip index based on first segment in timeline
        if let firstSegment = composition.timeline.segments.first {
            currentClipIndex = firstSegment.clipIndex
            
            // Diagnostic: Log clip 0 immediately when playback starts
            if PlaybackDiagnostics.isEnabled {
                logClipStartDiagnostics(for: firstSegment, at: 0.0)
            }
            
            TapesLog.player.info("PlaybackEngine: Starting playback at clip \(self.currentClipIndex)")
        } else {
            currentClipIndex = 0
        }
        
        TapesLog.player.info("PlaybackEngine: Composition installed, playback started")
    }
    
    /// Swap composition seamlessly (for subsequent rebuilds with placeholders)
    private func swapCompositionSeamlessly(
        newComposition: TapeCompositionBuilder.PlayerComposition,
        preservingTime: Double
    ) async {
        guard let player = player, let oldTimeline = timeline else {
            // Fallback to full install if no player
            await install(composition: newComposition)
            return
        }
        
        // CRITICAL FIX: Prevent swaps during first 10 seconds of playback
        // This avoids resets during initial playback startup and gives user time to see playback working
        if isPlaying && preservingTime < 10.0 {
            TapesLog.player.info("PlaybackEngine: Deferring swap - playback just started (time: \(String(format: "%.2f", preservingTime))s)")
            return
        }
        
        // CRITICAL FIX: Only swap if paused, in placeholder, or very close to transition boundary
        // BUT allow swap if user is seeking (isSeekingToClip flag set)
        // This prevents mid-clip jumps but allows swaps when user explicitly seeks
        if isPlaying && !isSeekingToClip {
            let swapPoint = detectSafeSwapPoint(
                currentTime: preservingTime,
                timeline: oldTimeline
            )
            
            // Only swap if:
            // 1. We're in a placeholder (black screen, invisible)
            // 2. OR we're very close to a transition boundary (< 0.2s away)
            let isCloseToBoundary = (swapPoint.timeToNextBoundary ?? 999) < 0.2
            
            if !swapPoint.isPlaceholder && !isCloseToBoundary {
                TapesLog.player.info("PlaybackEngine: Deferring swap - not at safe boundary (time: \(String(format: "%.2f", preservingTime))s, to boundary: \(String(format: "%.2f", swapPoint.timeToNextBoundary ?? 0))s)")
                return
            }
        }
        
        TapesLog.player.info("PlaybackEngine: Swapping composition at time \(String(format: "%.2f", preservingTime))s")
        
        // Map time position to new timeline (1:1 mapping with placeholders)
        let oldCMTime = CMTime(seconds: preservingTime, preferredTimescale: 600)
        let newCMTime = mapTimeToNewTimeline(
            oldTime: oldCMTime,
            oldTimeline: oldTimeline,
            newTimeline: newComposition.timeline
        )
        
        let newTimeSeconds = CMTimeGetSeconds(newCMTime)
        TapesLog.player.info("PlaybackEngine: Mapped time \(String(format: "%.2f", preservingTime))s -> \(String(format: "%.2f", newTimeSeconds))s")
        
        // Validate mapped time (should be reasonable)
        guard newTimeSeconds >= 0 && newTimeSeconds <= CMTimeGetSeconds(newComposition.timeline.totalDuration) else {
            TapesLog.player.warning("PlaybackEngine: Invalid mapped time \(String(format: "%.2f", newTimeSeconds))s, deferring swap")
            return
        }
        
        // CRITICAL: Update timeline BEFORE swap so time observer uses correct timeline
        // This prevents race conditions where observer fires with old timeline
        timeline = newComposition.timeline
        duration = CMTimeGetSeconds(newComposition.timeline.totalDuration)
        
        // Detect safe swap point (using old timeline for detection)
        let swapPoint = detectSafeSwapPoint(
            currentTime: preservingTime,
            timeline: oldTimeline
        )
        
        // If playing, wait for safe boundary (or swap immediately if in placeholder)
        if isPlaying {
            if swapPoint.isPlaceholder {
                // Swap immediately - placeholder is black, invisible change
                await performSwap(player: player, newItem: newComposition.playerItem, targetTime: newCMTime)
            } else {
                // Wait for next transition boundary (brief pause acceptable)
                await waitForSafeBoundary(timeToBoundary: swapPoint.timeToNextBoundary)
                await performSwap(player: player, newItem: newComposition.playerItem, targetTime: newCMTime)
            }
        } else {
            // Paused - swap immediately (seamless)
            await performSwap(player: player, newItem: newComposition.playerItem, targetTime: newCMTime)
        }
        
        // Update clip index after swap completes (using correct timeline and preserved time)
        // We manually update here since updateCurrentClipIndex() is guarded during swaps
        if let timeline = timeline {
            for segment in timeline.segments {
                let segmentStart = CMTimeGetSeconds(segment.timeRange.start)
                let segmentEnd = segmentStart + CMTimeGetSeconds(segment.timeRange.duration)
                
                if preservingTime >= segmentStart && preservingTime < segmentEnd {
                    currentClipIndex = segment.clipIndex
                    break
                }
            }
        }
    }
    
    private func performSwap(
        player: AVPlayer,
        newItem: AVPlayerItem,
        targetTime: CMTime
    ) async {
        // CRITICAL: Set BOTH flags to prevent time observer from processing
        // during the entire swap window
        isSwappingComposition = true
        isSeekingToClip = true
        
        // Capture target time BEFORE swap (in case observer fires during replaceCurrentItem)
        let targetTimeSeconds = CMTimeGetSeconds(targetTime)
        
        // Critical: Update observers for new item (end/stall observers are item-specific)
        // Remove old item observers
        if let observer = playerEndObserver {
            NotificationCenter.default.removeObserver(observer)
            playerEndObserver = nil
        }
        if let observer = playerStallObserver {
            NotificationCenter.default.removeObserver(observer)
            playerStallObserver = nil
        }
        
        // CRITICAL: Update currentTime IMMEDIATELY before replaceCurrentItem
        // This prevents the time observer from seeing time = 0 and updating clip index
        currentTime = targetTimeSeconds
        
        // Use replaceCurrentItem (time observer on player continues working)
        // NOTE: This will reset player's internal time to 0, but we've already
        // updated our currentTime to the target, so observer won't see the jump
        player.replaceCurrentItem(with: newItem)
        
        // Reinstall observers for new item
        installObserversForItem(newItem)
        
        // Seek to equivalent position (preserve playback rate)
        let currentRate = player.rate
        await player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
        
        // Ensure currentTime matches seek position (redundant but safe)
        currentTime = targetTimeSeconds
        
        // Restore playback rate if was playing
        if currentRate > 0 {
            player.rate = currentRate
        }
        
        // Clear flags after a delay to ensure seek completes and player stabilizes
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s delay for stability (increased from 500ms)
            isSeekingToClip = false
            isSwappingComposition = false
        }
    }
    
    private func installObserversForItem(_ item: AVPlayerItem) {
        // End observer
        playerEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.isFinished = true
            self.isPlaying = false
            TapesLog.player.info("PlaybackEngine: Playback finished")
        }
        
        // Stall observer
        playerStallObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.isBuffering = true
            TapesLog.player.warning("PlaybackEngine: Playback stalled")
        }
        
        // Update duration (CMTime is not optional, but can be .invalid)
        let duration = item.duration
        if CMTimeCompare(duration, .invalid) != 0 {
            self.duration = CMTimeGetSeconds(duration)
        }
    }
    
    private func detectSafeSwapPoint(
        currentTime: Double,
        timeline: TapeCompositionBuilder.Timeline
    ) -> (isPlaceholder: Bool, timeToNextBoundary: Double?) {
        // Find current segment
        guard let segment = timeline.segments.first(where: { segment in
            let start = CMTimeGetSeconds(segment.timeRange.start)
            let end = start + CMTimeGetSeconds(segment.timeRange.duration)
            return currentTime >= start && currentTime < end
        }) else {
            return (isPlaceholder: false, timeToNextBoundary: nil)
        }
        
        // Check if placeholder (has no real asset, or marked as temporary)
        let isPlaceholder = segment.assetContext.isTemporaryAsset
        
        // Calculate time to next transition boundary
        let segmentStart = CMTimeGetSeconds(segment.timeRange.start)
        let segmentEnd = segmentStart + CMTimeGetSeconds(segment.timeRange.duration)
        let timeToEnd = segmentEnd - currentTime
        
        return (isPlaceholder: isPlaceholder, timeToNextBoundary: timeToEnd)
    }
    
    private func waitForSafeBoundary(timeToBoundary: Double?) async {
        guard let timeToBoundary = timeToBoundary, timeToBoundary > 0.1 else {
            // Already at boundary or very close
            return
        }
        
        // Wait for next transition boundary (max 2 seconds)
        let waitTime = min(timeToBoundary, 2.0)
        try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
    }
    
    private func mapTimeToNewTimeline(
        oldTime: CMTime,
        oldTimeline: TapeCompositionBuilder.Timeline,
        newTimeline: TapeCompositionBuilder.Timeline
    ) -> CMTime {
        // Find which segment contains oldTime in old timeline
        guard let oldSegment = oldTimeline.segments.first(where: { segment in
            let start = CMTimeGetSeconds(segment.timeRange.start)
            let end = start + CMTimeGetSeconds(segment.timeRange.duration)
            let timeSeconds = CMTimeGetSeconds(oldTime)
            return timeSeconds >= start && timeSeconds < end
        }) else {
            // Past end - map to end of new timeline
            return newTimeline.totalDuration
        }
        
        // Calculate offset within segment
        let segmentStart = oldSegment.timeRange.start
        let offsetInSegment = CMTimeSubtract(oldTime, segmentStart)
        
        // Find corresponding segment in new timeline (same clipIndex)
        guard let newSegment = newTimeline.segments.first(where: { 
            $0.clipIndex == oldSegment.clipIndex 
        }) else {
            // Clip removed? Shouldn't happen, but fallback to start
            return .zero
        }
        
        // Map to same position in new segment
        let newTime = CMTimeAdd(newSegment.timeRange.start, offsetInSegment)
        
        // Ensure within bounds
        let newTimeSeconds = CMTimeGetSeconds(newTime)
        let newTotalSeconds = CMTimeGetSeconds(newTimeline.totalDuration)
        if newTimeSeconds >= newTotalSeconds {
            return newTimeline.totalDuration
        }
        
        return newTime
    }
    
    func play() {
        guard let player = player else { return }
        player.play()
        isPlaying = true
        TapesLog.player.info("PlaybackEngine: Play")
    }
    
    func pause() {
        guard let player = player else { return }
        player.pause()
        isPlaying = false
        TapesLog.player.info("PlaybackEngine: Pause")
    }
    
    /// Set playback speed
    func setPlaybackSpeed(_ speed: Float) {
        guard let player = player else { return }
        
        let clampedSpeed = max(0.5, min(2.0, speed))
        player.rate = clampedSpeed
        playbackSpeed = clampedSpeed
        
        TapesLog.player.info("PlaybackEngine: Speed set to \(String(format: "%.1f", clampedSpeed))x")
    }
    
    func seek(to time: Double) {
        guard let player = player else { return }
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime)
        currentTime = time
        updateCurrentClipIndex()
        TapesLog.player.info("PlaybackEngine: Seek to \(String(format: "%.2f", time))s")
    }
    
    /// Step one frame forward or backward
    func stepFrame(direction: Int) {
        guard let player = player, let timeline = timeline else { return }
        
        let currentCMTime = CMTime(seconds: currentTime, preferredTimescale: 600)
        let frameDuration = CMTime(value: 1, timescale: 30) // Assume 30fps, can be enhanced
        
        let newTime: CMTime
        if direction > 0 {
            newTime = CMTimeAdd(currentCMTime, frameDuration)
        } else {
            newTime = CMTimeSubtract(currentCMTime, frameDuration)
        }
        
        let clampedTime = max(0, min(CMTimeGetSeconds(newTime), duration))
        seek(to: clampedTime)
        TapesLog.player.info("PlaybackEngine: Stepped frame \(direction > 0 ? "forward" : "backward")")
    }
    
    func seekToClip(at index: Int) {
        guard let timeline = timeline else {
            TapesLog.player.warning("PlaybackEngine: Cannot seek - no timeline")
            return
        }
        
        // Prevent seeking to same clip (would restart it)
        guard index != currentClipIndex else {
            TapesLog.player.info("PlaybackEngine: Already at clip \(index), skipping seek")
            return
        }
        
        // Debounce rapid skip operations
        let now = Date()
        guard now.timeIntervalSince(lastSkipTime) >= skipDebounceInterval else {
            TapesLog.player.info("PlaybackEngine: Skip debounced (too rapid)")
            return
        }
        lastSkipTime = now
        
        // Find segment with matching clipIndex (not segment index)
        if let segment = timeline.segments.first(where: { $0.clipIndex == index }) {
            // Clip exists in timeline - seek normally
            let seekTime = segment.timeRange.start
            let seconds = CMTimeGetSeconds(seekTime)
            
            // Set flag to prevent time observer from updating index during seek
            isSeekingToClip = true
            
            // Update clip index BEFORE seeking to prevent updateCurrentClipIndex from overriding it
            // Use explicit assignment to trigger SwiftUI update immediately
            currentClipIndex = index
            
            // Seek without triggering index update (we already set it explicitly)
            // Use tolerance for smoother seeks
            guard let player = player else { return }
            let cmTime = CMTime(seconds: seconds, preferredTimescale: 600)
            let toleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
            let toleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
            
            player.seek(to: cmTime, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter)
            currentTime = seconds
            
            // Clear flag after a longer delay to ensure seek and UI updates complete smoothly
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms delay for smoother transition
                isSeekingToClip = false
            }
            
            TapesLog.player.info("PlaybackEngine: Seek to clip \(index) at time \(String(format: "%.2f", seconds))s")
        } else {
            // CRITICAL FIX: Clip not in timeline - trigger immediate swap if assets are ready
            TapesLog.player.warning("PlaybackEngine: Clip \(index) not found in timeline - triggering swap check")
            
            // Update clip index so UI shows correct position
            currentClipIndex = index
            
            // Trigger immediate extension check and swap
            Task { @MainActor [weak self] in
                guard let self = self, let tape = self.currentTape else { return }
                
                // Get completed assets from background service
                let completed = await self.backgroundService.getAllCompletedAssets()
                
                if !completed.isEmpty || !self.pendingAssets.isEmpty {
                    // We have assets ready - build new composition immediately
                    let allCompleted = completed + self.pendingAssets
                    let currentReadyAssets = await self.getCurrentReadyAssets(from: self.timeline, tape: tape)
                    let allReadyAssets = currentReadyAssets + allCompleted
                    
                    // Update SkipHandler with newly-ready assets
                    let newReadyIndices = Set(allCompleted.map { $0.0 })
                    if !newReadyIndices.isEmpty {
                        self._skipHandler?.updateReadyIndices(newReadyIndices)
                        TapesLog.player.info("PlaybackEngine: Updated SkipHandler - \(newReadyIndices.count) clips now ready")
                    }
                    
                    // Remove duplicates (keep latest)
                    var uniqueAssets: [Int: HybridAssetLoader.ResolvedAsset] = [:]
                    for (idx, asset) in allReadyAssets {
                        uniqueAssets[idx] = asset
                    }
                    let sortedAssets = Array(uniqueAssets).sorted { $0.key < $1.key }
                    
                    do {
                        let newComposition = try await self.builder.buildPlayerItem(
                            for: tape,
                            readyAssets: sortedAssets,
                            skippedIndices: []
                        )
                        
                        // CRITICAL FIX: When seeking to a specific clip, calculate target time first
                        // This prevents incorrect time mapping when seeking backward (e.g., 51 -> 11)
                        var targetTime: Double? = nil
                        if let targetSegment = newComposition.timeline.segments.first(where: { $0.clipIndex == index }) {
                            targetTime = CMTimeGetSeconds(targetSegment.timeRange.start)
                        }
                        
                        // Use target time if available, otherwise preserve current time
                        let swapTime = targetTime ?? self.currentTime
                        
                        // Force swap (bypass normal deferral logic since user is seeking)
                        await self.swapCompositionSeamlessly(
                            newComposition: newComposition,
                            preservingTime: swapTime
                        )
                        
                        // After swap, seek to the target clip
                        if let newTimeline = self.timeline,
                           let segment = newTimeline.segments.first(where: { $0.clipIndex == index }) {
                            let seekTime = segment.timeRange.start
                            let seconds = CMTimeGetSeconds(seekTime)
                            
                            self.isSeekingToClip = true
                            self.currentClipIndex = index
                            
                            if let player = self.player {
                                let cmTime = CMTime(seconds: seconds, preferredTimescale: 600)
                                await player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
                                self.currentTime = seconds
                            }
                            
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 300_000_000)
                                self.isSeekingToClip = false
                            }
                            
                            TapesLog.player.info("PlaybackEngine: Seek to clip \(index) after swap at time \(String(format: "%.2f", seconds))s")
                        }
                        
                        // Clear pending batch
                        self.pendingAssets.removeAll()
                        self.lastBatchTime = Date()
                    } catch {
                        TapesLog.player.error("PlaybackEngine: Failed to swap composition for clip \(index): \(error.localizedDescription)")
                    }
                } else {
                    // No assets ready yet - show placeholder (will be swapped when assets load)
                    TapesLog.player.info("PlaybackEngine: Clip \(index) not ready yet - will swap when assets load")
                }
            }
        }
    }
    
    func setError(_ message: String?) {
        error = message
        isBuffering = false
    }
    
    func teardown() {
        TapesLog.player.info("PlaybackEngine: Teardown called (isPreparing: \(self.isPreparing))")
        
        // Cancel any active preparation
        currentPrepareTask?.cancel()
        currentPrepareTask = nil
        isPreparing = false
        
        // Remove observers
        removeObservers()
        
        // Pause and clear player
        player?.pause()
        player = nil
        
        // Clear state
        isPlaying = false
        isBuffering = false
        isFinished = false
        currentTime = 0
        currentClipIndex = 0
        duration = 0
        error = nil
        timeline = nil
        _skipHandler = nil
        
        // Cancel loader and background service
        Task {
            await loader.cancel()
            await backgroundService.cancel()
        }
        
        // Cancel extension checking
        extensionCheckTask?.cancel()
        extensionCheckTask = nil
        
        // Reset extension manager
        extensionManager.reset()
        
        TapesLog.player.info("PlaybackEngine: Teardown complete")
    }
    
    // MARK: - Phase 2: Background Loading & Extension
    
    private func startBackgroundLoading(
        tape: Tape,
        skippedIndices: Set<Int>,
        windowResult: HybridAssetLoader.WindowResult
    ) async {
        // Collect clips that are still loading or were skipped
        var backgroundClips: [(Int, Clip)] = []
        
        for (index, clip) in tape.clips.enumerated() {
            // Skip if already ready or not in our tracking
            let isReady = windowResult.readyAssets.contains { $0.0 == index }
            let isSkipped = skippedIndices.contains(index)
            
            if !isReady {
                // Determine priority: higher for clips that come sooner
                let priority: BackgroundAssetService.Priority = (index < 10) ? .high : .normal
                backgroundClips.append((index, clip))
            }
        }
        
        if !backgroundClips.isEmpty {
            await backgroundService.enqueue(assets: backgroundClips.map { ($0.0, $0.1) }, priority: .normal)
            TapesLog.player.info("PlaybackEngine: Started background loading for \(backgroundClips.count) clips")
        }
    }
    
    // Batch rebuild state
    private var pendingAssets: [(Int, HybridAssetLoader.ResolvedAsset)] = []
    private var lastBatchTime: Date = .distantPast
    private let batchTimeout: TimeInterval = 5.0 // Increased from 2.0 to reduce swap frequency
    private let batchSize = 5 // Increased from 3 to reduce swap frequency
    
    private func startExtensionChecking(tape: Tape) {
        extensionCheckTask?.cancel()
        
        // Reset batch state
        pendingAssets.removeAll()
        lastBatchTime = Date()
        
        // Track when playback started to prevent swaps during initial period
        let playbackStartTime = Date()
        
        extensionCheckTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                // CRITICAL FIX: Check every 2 seconds instead of 0.5s (reduces polling overhead)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                
                guard !Task.isCancelled else { break }
                
                // CRITICAL FIX: Don't check/swaps during first 10 seconds of playback
                // This prevents interruptions during initial playback startup
                let playbackElapsed = Date().timeIntervalSince(playbackStartTime)
                if playbackElapsed < 10.0 {
                    TapesLog.player.info("PlaybackEngine: Extension checking deferred - playback just started (\(String(format: "%.1f", playbackElapsed))s)")
                    continue
                }
                
                // Get completed assets from background service (before checking if we should swap)
                let completed = await self.backgroundService.getAllCompletedAssets()
                
                // CRITICAL FIX: Only swap if playback is paused, near end, OR we have assets for upcoming clips
                // Don't interrupt active playback unless we have assets ready for clips coming soon
                if self.isPlaying {
                    let currentTime = self.currentTime
                    let totalDuration = self.duration
                    let timeRemaining = totalDuration - currentTime
                    
                    // Check if we have assets ready for clips coming up soon
                    let currentClipIdx = self.currentClipIndex
                    let startIdx = currentClipIdx + 1
                    let endIdx = min(currentClipIdx + 5, tape.clips.count - 1)
                    let upcomingClipIndices = startIdx <= endIdx ? Set(startIdx...endIdx) : Set<Int>()
                    
                    // Check if any completed assets or pending assets are for upcoming clips
                    let hasUpcomingAssets = !completed.isEmpty && completed.contains { upcomingClipIndices.contains($0.0) }
                    let hasPendingUpcoming = !self.pendingAssets.isEmpty && self.pendingAssets.contains { upcomingClipIndices.contains($0.0) }
                    
                    // Allow swap if:
                    // 1. We're close to end (within 5 seconds), OR
                    // 2. We have assets ready for clips coming up soon (within 5 clips ahead)
                    let shouldSwap = timeRemaining <= 5.0 || hasUpcomingAssets || hasPendingUpcoming
                    
                    if !shouldSwap {
                        TapesLog.player.info("PlaybackEngine: Extension checking deferred - playback active, not near end, no upcoming assets")
                        continue
                    }
                    
                    if hasUpcomingAssets || hasPendingUpcoming {
                        TapesLog.player.info("PlaybackEngine: Extension checking - assets ready for upcoming clips, allowing swap")
                    }
                }
                
                if !completed.isEmpty {
                    // Add to pending batch
                    self.pendingAssets.append(contentsOf: completed)
                    self.lastBatchTime = Date()
                    
                    // Check if we should rebuild now
                    // CRITICAL FIX: Reduce batch requirements when we have assets for upcoming clips
                    let currentClipIdx = self.currentClipIndex
                    let startIdx = currentClipIdx + 1
                    let endIdx = min(currentClipIdx + 5, tape.clips.count - 1)
                    let upcomingClipIndices = startIdx <= endIdx ? Set(startIdx...endIdx) : Set<Int>()
                    let hasUpcomingAssets = self.pendingAssets.contains { upcomingClipIndices.contains($0.0) }
                    
                    // If we have assets for upcoming clips, be more aggressive about swapping
                    // Otherwise, use normal batch requirements
                    let batchSizeRequired = hasUpcomingAssets ? self.batchSize : self.batchSize * 2
                    let timeoutRequired = hasUpcomingAssets ? self.batchTimeout : self.batchTimeout * 2
                    
                    let shouldRebuild = self.pendingAssets.count >= batchSizeRequired || 
                                       Date().timeIntervalSince(self.lastBatchTime) >= timeoutRequired
                    
                    if shouldRebuild && !self.pendingAssets.isEmpty {
                        // Build new composition with all ready assets (including new ones)
                        // Get current ready assets from timeline
                        let currentReadyAssets = await self.getCurrentReadyAssets(from: self.timeline, tape: tape)
                        let allReadyAssets = currentReadyAssets + self.pendingAssets
                        
                        // Remove duplicates (keep latest) - use Dictionary init that handles duplicates
                        var uniqueAssets: [Int: HybridAssetLoader.ResolvedAsset] = [:]
                        for (index, asset) in allReadyAssets {
                            uniqueAssets[index] = asset // Keep latest if duplicate
                        }
                        let sortedAssets = Array(uniqueAssets).sorted { $0.key < $1.key }
                        
                        do {
                            // Build composition with placeholders for all clips
                            let newComposition = try await self.builder.buildPlayerItem(
                                for: tape,
                                readyAssets: sortedAssets,
                                skippedIndices: []
                            )
                            
                            // Update SkipHandler with newly-ready assets
                            let newReadyIndices = Set(self.pendingAssets.map { $0.0 })
                            if !newReadyIndices.isEmpty {
                                self._skipHandler?.updateReadyIndices(newReadyIndices)
                                TapesLog.player.info("PlaybackEngine: Updated SkipHandler - \(newReadyIndices.count) clips now ready")
                            }
                            
                            // Swap seamlessly (will be deferred if playback is active)
                            await self.swapCompositionSeamlessly(
                                newComposition: newComposition,
                                preservingTime: self.currentTime
                            )
                            
                            TapesLog.player.info("PlaybackEngine: Composition swapped seamlessly with \(self.pendingAssets.count) new assets (total: \(sortedAssets.count))")
                            
                            // Clear pending batch
                            self.pendingAssets.removeAll()
                            self.lastBatchTime = Date()
                        } catch {
                            TapesLog.player.error("PlaybackEngine: Failed to rebuild composition: \(error.localizedDescription)")
                        }
                    }
                }
                
                // Also check timeout even if no new assets (to flush pending batch)
                // CRITICAL FIX: Only flush if playback is paused
                if !self.pendingAssets.isEmpty && Date().timeIntervalSince(self.lastBatchTime) >= self.batchTimeout * 2 {
                    // Only flush if paused - don't interrupt active playback
                    guard !self.isPlaying else {
                        continue
                    }
                    
                    let currentReadyAssets = await self.getCurrentReadyAssets(from: self.timeline, tape: tape)
                    let allReadyAssets = currentReadyAssets + self.pendingAssets
                    
                    // Remove duplicates (keep latest)
                    var uniqueAssets: [Int: HybridAssetLoader.ResolvedAsset] = [:]
                    for (index, asset) in allReadyAssets {
                        uniqueAssets[index] = asset // Keep latest if duplicate
                    }
                    let sortedAssets = Array(uniqueAssets).sorted { $0.key < $1.key }
                    
                    do {
                        let newComposition = try await self.builder.buildPlayerItem(
                            for: tape,
                            readyAssets: sortedAssets,
                            skippedIndices: []
                        )
                        
                        // Update SkipHandler with newly-ready assets
                        let newReadyIndices = Set(self.pendingAssets.map { $0.0 })
                        if !newReadyIndices.isEmpty {
                            self._skipHandler?.updateReadyIndices(newReadyIndices)
                            TapesLog.player.info("PlaybackEngine: Updated SkipHandler - \(newReadyIndices.count) clips now ready")
                        }
                        
                        await self.swapCompositionSeamlessly(
                            newComposition: newComposition,
                            preservingTime: self.currentTime
                        )
                        
                        TapesLog.player.info("PlaybackEngine: Composition swapped seamlessly (timeout flush) with \(self.pendingAssets.count) new assets")
                        self.pendingAssets.removeAll()
                        self.lastBatchTime = Date()
                    } catch {
                        TapesLog.player.error("PlaybackEngine: Failed to rebuild composition (timeout): \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func getCurrentReadyAssets(
        from timeline: TapeCompositionBuilder.Timeline?,
        tape: Tape
    ) async -> [(Int, HybridAssetLoader.ResolvedAsset)] {
        guard let timeline = timeline else { return [] }
        
        var readyAssets: [(Int, HybridAssetLoader.ResolvedAsset)] = []
        
        for segment in timeline.segments {
            // Skip placeholders (temporary assets)
            guard !segment.assetContext.isTemporaryAsset else { continue }
            
            // Reconstruct ResolvedAsset from segment context
            let resolved = HybridAssetLoader.ResolvedAsset(
                clipIndex: segment.clipIndex,
                asset: segment.assetContext.asset,
                clip: segment.assetContext.clip,
                duration: segment.assetContext.duration,
                naturalSize: segment.assetContext.naturalSize,
                preferredTransform: segment.assetContext.preferredTransform,
                hasAudio: segment.assetContext.hasAudio,
                isTemporary: segment.assetContext.isTemporaryAsset,
                motionEffect: segment.assetContext.motionEffect
            )
            
            readyAssets.append((segment.clipIndex, resolved))
        }
        
        return readyAssets
    }
    
    // MARK: - Observers
    
    private func installObservers(player: AVPlayer) {
        // Time observer (on player, persists across item swaps)
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            
            // CRITICAL: Don't process if we're seeking, swapping, or finished
            // This prevents race conditions where replaceCurrentItem resets time to 0
            guard !self.isSeekingToClip, !self.isSwappingComposition, !self.isFinished else {
                return
            }
            
            let newTime = CMTimeGetSeconds(time)
            
            // CRITICAL: Ignore time = 0 if we're not at the start
            // This prevents race conditions where replaceCurrentItem resets time to 0
            // during swaps, but we've already updated currentTime to the target time
            if newTime == 0 && self.currentTime > 0 {
                // This is likely a swap in progress - ignore this update
                return
            }
            
            self.currentTime = newTime
            
            // Update clip index based on current playback position
            self.updateCurrentClipIndex()
            
            // Check skip behavior (but only if not seeking/swapping)
            self.checkSkipBehavior()
        }
        
        // Install observers for current item
        if let item = player.currentItem {
            installObserversForItem(item)
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
    
    // MARK: - Skip Behavior
    
    private func checkSkipBehavior() {
        guard let skipHandler = _skipHandler,
              let timeline = timeline else {
            return
        }
        
        // Don't check skip behavior if we're currently seeking or swapping (prevents feedback loops)
        guard !isSeekingToClip, !isSwappingComposition else {
            return
        }
        
        // Note: updateCurrentClipIndex() is already called in the time observer above,
        // so we don't need to call it again here. Just use the current value.
        
        // Check if current clip should be skipped
        // Note: We check the actual clip index from the timeline segment, not the segment index
        if skipHandler.shouldSkip(clipIndex: self.currentClipIndex) {
            // Skip to next ready clip
            if skipHandler.canSkip(),
               let nextReady = skipHandler.nextReadyClip(after: self.currentClipIndex) {
                TapesLog.player.info("PlaybackEngine: Skipping clip \(self.currentClipIndex), jumping to clip \(nextReady)")
                seekToClip(at: nextReady)
            } else {
                // No next ready clip - might be at end or all subsequent clips are skipped
                TapesLog.player.warning("PlaybackEngine: Clip \(self.currentClipIndex) should be skipped but no next ready clip found")
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func updateCurrentClipIndex() {
        guard let timeline = timeline else { return }
        
        // Don't update if we're swapping (prevents race conditions)
        guard !isSwappingComposition else {
            return
        }
        
        let previousClipIndex = currentClipIndex
        
        // Find which segment contains current time
        for (index, segment) in timeline.segments.enumerated() {
            let segmentStart = CMTimeGetSeconds(segment.timeRange.start)
            let segmentEnd = segmentStart + CMTimeGetSeconds(segment.timeRange.duration)
            
            if currentTime >= segmentStart && currentTime < segmentEnd {
                currentClipIndex = segment.clipIndex
                
                // Diagnostic: Log clip change
                if PlaybackDiagnostics.isEnabled && previousClipIndex != currentClipIndex {
                    logClipStartDiagnostics(for: segment, at: segmentStart)
                }
                return
            }
        }
        
        // If at or past end, set to last clip
        if !timeline.segments.isEmpty {
            currentClipIndex = timeline.segments.last!.clipIndex
        }
    }
    
    // Diagnostic: Log clip start with all metadata
    private func logClipStartDiagnostics(for segment: TapeCompositionBuilder.Segment, at segmentStart: Double) {
        guard PlaybackDiagnostics.isEnabled else { return }
        
        let context = segment.assetContext
        let clip = context.clip
        
        // Compute display size from transform
        let displaySize = PlaybackDiagnostics.ClipDiagnostics.computeDisplaySize(
            natural: context.naturalSize,
            transform: context.preferredTransform
        )
        
        // Get PHAsset metadata if available
        var isEdited = false
        var isCloudPlaceholder = false
        var assetIDHash: String? = nil
        
        if let assetLocalId = clip.assetLocalId {
            assetIDHash = String(assetLocalId.prefix(8)) + "..."
            if let phAsset = clip.fetchAsset() {
                // Check if edited (has adjustments)
                // Note: PHAsset doesn't directly expose isEdited, but we can check for adjustments
                // For now, assume false - this requires PHLivePhotoEditingInput or checking adjustment data
                isEdited = false // TODO: Proper detection if needed
                
                // Check if cloud placeholder (not fully downloaded)
                // PHAsset doesn't directly expose this, but we can infer from resource availability
                // For now, assume false - would need to check PHAssetResource
                isCloudPlaceholder = false // TODO: Proper detection if needed
            }
        }
        
        // Get file URL basename
        let fileURLBasename = clip.localURL?.lastPathComponent
        
        // Get render size from timeline
        let timelineRenderSize = timeline?.renderSize ?? CGSize(width: 1080, height: 1920)
        
        // Get scale mode (effective: clip override or tape default)
        let tapeScaleMode = currentTape?.scaleMode ?? .fit
        let effectiveScaleMode = clip.overrideScaleMode ?? tapeScaleMode
        let scaleModeStr = clip.overrideScaleMode?.rawValue ?? tapeScaleMode.rawValue
        
        // Compute actual final transform using same logic as baseTransform()
        let finalTransform = computeFinalTransform(
            context: context,
            renderSize: timelineRenderSize,
            scaleMode: effectiveScaleMode
        )
        
        // Get instruction count from composition if available
        let instructionCount = player?.currentItem?.videoComposition?.instructions.count ?? 0
        
        // Create diagnostic entry
        let diagnostics = PlaybackDiagnostics.ClipDiagnostics(
            clipIndex: context.index,
            clipID: clip.id.uuidString,
            assetID: assetIDHash,
            fileURL: fileURLBasename,
            clipType: clip.clipType.rawValue,
            naturalSize: context.naturalSize,
            preferredTransform: context.preferredTransform,
            computedDisplaySize: displaySize,
            cleanAperture: context.cleanAperture,
            pixelAspectRatio: context.pixelAspectRatio,
            renderSize: timelineRenderSize,
            instructionCount: instructionCount,
            finalTransform: finalTransform,
            videoGravity: nil, // VideoPlayer doesn't expose this - would need UIViewRepresentable
            layerBounds: nil, // Would need to get from UI layer
            containerSize: nil, // Would need to get from SwiftUI
            safeAreaInsets: nil, // Would need to get from SwiftUI
            scaleMode: scaleModeStr,
            timeToFirstFrame: nil, // Would need to track first frame render via AVPlayerItem observers
            layoutStabilisedTime: nil, // Would need to track layout via GeometryReader
            isCloudPlaceholder: isCloudPlaceholder,
            isEdited: isEdited
        )
        
        PlaybackDiagnostics.logClipStart(diagnostics)
    }
    
    // Diagnostic: Compute final transform using same logic as TapeCompositionBuilder.baseTransform()
    private func computeFinalTransform(
        context: TapeCompositionBuilder.ClipAssetContext,
        renderSize: CGSize,
        scaleMode: ScaleMode
    ) -> CGAffineTransform {
        let preferred = context.preferredTransform
        // Basic scaling to fit render size - same logic as baseTransform
        let naturalSize = context.naturalSize.applying(preferred)
        let absWidth = abs(naturalSize.width)
        let absHeight = abs(naturalSize.height)
        guard absWidth > 0, absHeight > 0 else { return preferred }
        
        let renderWidth = renderSize.width
        let renderHeight = renderSize.height
        
        let scaleX = renderWidth / absWidth
        let scaleY = renderHeight / absHeight
        
        let scale: CGFloat
        switch scaleMode {
        case .fit:
            scale = min(scaleX, scaleY)
        case .fill:
            scale = max(scaleX, scaleY)
        }
        
        // OPTION A: Match TapeExporter approach - use concatenating() instead of scaledBy()
        // This matches the working export code exactly (for diagnostics)
        var transform = preferred
        transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        let translatedX = (renderWidth - absWidth * scale) / 2
        let translatedY = (renderHeight - absHeight * scale) / 2
        transform = transform.concatenating(CGAffineTransform(translationX: translatedX, y: translatedY))
        
        return transform
    }
}

