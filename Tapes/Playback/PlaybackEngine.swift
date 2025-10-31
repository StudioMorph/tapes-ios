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
    
    private(set) var player: AVPlayer?
    private(set) var timeline: TapeCompositionBuilder.Timeline?
    
    // MARK: - Private Properties
    
    private let builder = TapeCompositionBuilder()
    private let loader = HybridAssetLoader()
    private var skipHandler: SkipHandler?
    
    private var timeObserver: Any?
    private var playerEndObserver: NSObjectProtocol?
    private var playerStallObserver: NSObjectProtocol?
    
    private var isPreparing = false
    private var currentPrepareTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    init() {
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
                guard !windowResult.readyAssets.isEmpty else {
                    setError("Unable to load any clips for this tape. Please check your network connection.")
                    isBuffering = false
                    return
                }
                
                // Create skip handler
                let skippedIndices = Set(windowResult.skippedAssets.map { $0.0 })
                let readyIndices = Set(windowResult.readyAssets.map { $0.0 })
                let allIndices = Array(0..<tape.clips.count)
                skipHandler = SkipHandler(
                    skippedIndices: skippedIndices,
                    readyIndices: readyIndices,
                    allClipIndices: allIndices
                )
                
                // Check for high skip rate
                let stats = skipHandler!.getSkipStats()
                if stats.skipped > stats.ready {
                    TapesLog.player.warning("PlaybackEngine: High skip rate - \(stats.skipped) skipped, \(stats.ready) ready")
                }
                
                // Build composition with ready assets
                let composition = try await builder.buildPlayerItem(
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
                await install(composition: composition)
                
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
        currentClipIndex = 0
        
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
    
    func seek(to time: Double) {
        guard let player = player else { return }
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime)
        currentTime = time
        updateCurrentClipIndex()
        TapesLog.player.info("PlaybackEngine: Seek to \(String(format: "%.2f", time))s")
    }
    
    func seekToClip(at index: Int) {
        guard let timeline = timeline,
              index >= 0,
              index < timeline.segments.count else {
            return
        }
        
        let segment = timeline.segments[index]
        let seekTime = segment.timeRange.start
        let seconds = CMTimeGetSeconds(seekTime)
        
        seek(to: seconds)
        currentClipIndex = index
        TapesLog.player.info("PlaybackEngine: Seek to clip \(index)")
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
        skipHandler = nil
        
        // Cancel loader
        Task {
            await loader.cancel()
        }
        
        TapesLog.player.info("PlaybackEngine: Teardown complete")
    }
    
    // MARK: - Observers
    
    private func installObservers(player: AVPlayer) {
        // Time observer
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            self.currentTime = CMTimeGetSeconds(time)
            self.updateCurrentClipIndex()
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
        guard FeatureFlags.playbackEngineV2SkipBehavior,
              let skipHandler = skipHandler,
              let timeline = timeline else {
            return
        }
        
        // Check if current clip should be skipped
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
        
        // Find which segment contains current time
        for (index, segment) in timeline.segments.enumerated() {
            let segmentStart = CMTimeGetSeconds(segment.timeRange.start)
            let segmentEnd = segmentStart + CMTimeGetSeconds(segment.timeRange.duration)
            
            if currentTime >= segmentStart && currentTime < segmentEnd {
                currentClipIndex = segment.clipIndex
                return
            }
        }
        
        // If at or past end, set to last clip
        if !timeline.segments.isEmpty {
            currentClipIndex = timeline.segments.last!.clipIndex
        }
    }
}

