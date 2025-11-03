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
                // If all are skipped but we have assets, try to extend window or use placeholders
                if windowResult.readyAssets.isEmpty {
                    // If we have loading assets, wait a bit longer (extend window)
                    if !windowResult.loadingAssets.isEmpty {
                        TapesLog.player.info("PlaybackEngine: No assets ready, but \(windowResult.loadingAssets.count) still loading - extending window by 5s")
                        // Give it a bit more time
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                        // Re-check - for now, continue with skipped assets (Phase 2 will handle extension)
                    }
                    
                    // If still no ready assets, show error
                    if windowResult.readyAssets.isEmpty && windowResult.skippedAssets.count == tape.clips.count {
                        setError("Unable to load any clips for this tape. Please check your network connection and try again.")
                        isBuffering = false
                        return
                    }
                    
                    // Fall through - will build with skipped assets (placeholders)
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
    
    /// Install composition into player
    private func install(composition: TapeCompositionBuilder.PlayerComposition) async {
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
        
        // Set initial clip index based on first segment in timeline (not always 0 if clips are skipped)
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
        guard let segment = timeline.segments.first(where: { $0.clipIndex == index }) else {
            TapesLog.player.warning("PlaybackEngine: Clip \(index) not found in timeline")
            return
        }
        
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
    
    private func startExtensionChecking(tape: Tape) {
        extensionCheckTask?.cancel()
        
        extensionCheckTask = Task {
            while !Task.isCancelled {
                // Check every 2 seconds for new assets
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                
                guard !Task.isCancelled else { break }
                
                // Get completed assets from background service
                let completed = await backgroundService.getAllCompletedAssets()
                
                if !completed.isEmpty {
                    // Try to extend composition
                    if let extended = try? await extensionManager.extendIfNeeded(
                        for: tape,
                        newAssets: completed,
                        currentPlaybackTime: currentTime,
                        player: player
                    ) {
                        // Install extended composition (seamless)
                        await install(composition: extended)
                        TapesLog.player.info("PlaybackEngine: Composition extended with \(completed.count) new assets")
                    }
                }
            }
        }
    }
    
    // MARK: - Observers
    
    private func installObservers(player: AVPlayer) {
        // Time observer
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            self.currentTime = CMTimeGetSeconds(time)
            // Don't update index during explicit seek operations (prevents counter jumpiness)
            if !self.isSeekingToClip {
                self.updateCurrentClipIndex()
            }
            self.checkSkipBehavior()
        }
        
        // End observer
        playerEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
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
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.isBuffering = true
            TapesLog.player.warning("PlaybackEngine: Playback stalled")
        }
        
        // Update duration
        if let duration = player.currentItem?.duration {
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
    
    // MARK: - Skip Behavior
    
    private func checkSkipBehavior() {
        guard let skipHandler = _skipHandler,
              let timeline = timeline else {
            return
        }
        
        // Update current clip index first based on actual playback position
        updateCurrentClipIndex()
        
        // Check if current clip should be skipped
        // Note: We check the actual clip index from the timeline segment, not the segment index
        if skipHandler.shouldSkip(clipIndex: self.currentClipIndex) {
            // Skip to next ready clip
            if skipHandler.canSkip(),
               let nextReady = skipHandler.nextReadyClip(after: self.currentClipIndex) {
                TapesLog.player.info("PlaybackEngine: Skipping clip \(self.currentClipIndex), jumping to clip \(nextReady)")
                seekToClip(at: nextReady)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func updateCurrentClipIndex() {
        guard let timeline = timeline else { return }
        
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

