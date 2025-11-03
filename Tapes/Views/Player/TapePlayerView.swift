import SwiftUI
import AVFoundation
import AVKit
import Combine

extension Notification.Name {
    static let autoHideControls = Notification.Name("autoHideControls")
}

private final class PlaybackCoordinatorHolder: ObservableObject {
    let coordinator = PlaybackPreparationCoordinator()
}

// MARK: - Unified Tape Player View

struct TapePlayerView: View {
    // New engine (Phase 1)
    @StateObject private var engine = PlaybackEngine()
    @State private var showingControlsV2: Bool = true
    @State private var controlsTimerV2: Timer?
    @State private var hasAppeared = false
    @State private var appearanceTime: Date?
    
    // Legacy state
    @State private var player: AVPlayer?
    @State private var timeline: TapeCompositionBuilder.Timeline?
    @State private var currentClipIndex: Int = 0
    @State private var isPlaying: Bool = false
    @State private var showingControls: Bool = true
    @State private var controlsTimer: Timer?
    @State private var totalDuration: Double = 0
    @State private var currentTime: Double = 0
    @State private var isFinished: Bool = false
    @State private var isLoading: Bool = false
    @State private var loadError: String?
    @State private var timeObserverToken: Any?
    @State private var playerEndObserver: NSObjectProtocol?
    @StateObject private var coordinatorHolder = PlaybackCoordinatorHolder()
    @State private var isUsingFullComposition = false
    @State private var playbackIntent: Bool = false
    @State private var pendingComposition: TapeCompositionBuilder.PlayerComposition?
    @State private var pendingAutoplay: Bool = false
    @State private var pendingCompositionIsFinal: Bool = false
    @State private var skippedClipCount: Int = 0
    @State private var showSkipToast: Bool = false
    @State private var skipToastWorkItem: DispatchWorkItem?

    let tape: Tape
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Phase 1: New engine path
            if FeatureFlags.playbackEngineV2Phase1 {
                // Video player (if exists)
                if let player = engine.player {
                    VideoPlayer(player: player)
                        .disabled(true)
                        .overlay(tapCatcherV2)
                        .onDisappear { player.pause() }
                } else {
                    // No player yet - show tap catcher for controls
                    tapCatcherV2
                }
                
                // Loading overlay - show whenever actually loading/preparing (no fake delays)
                // Always render overlay (but conditionally visible) to ensure SwiftUI tracks state
                PlayerLoadingOverlay(
                    isLoading: engine.isPreparing || engine.isBuffering,
                    loadError: engine.error
                )
                .zIndex(100)
                .opacity((engine.isPreparing || engine.isBuffering) ? 1 : 0)
                .allowsHitTesting(engine.isPreparing || engine.isBuffering)

                // Controls (show/hide based on state)
                if showingControlsV2 || engine.error != nil || engine.isFinished {
                    VStack {
                        PlayerHeader(
                            currentClipIndex: engine.currentClipIndex,
                            totalClips: tape.clips.count,
                            onDismiss: onDismiss
                        )
                        Spacer()
                        if engine.error == nil {
                            controlsViewV2
                        }
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: showingControlsV2)
                }
            } else {
                // Legacy path
                if let player {
                    VideoPlayer(player: player)
                        .disabled(true)
                        .overlay(loadingOverlay)
                        .overlay(tapCatcher)
                        .onDisappear { player.pause() }
                } else {
                    loadingOverlay
                        .overlay(tapCatcher)
                }

                if showingControls {
                    VStack {
                        PlayerHeader(
                            currentClipIndex: currentClipIndex,
                            totalClips: tape.clips.count,
                            onDismiss: onDismiss
                        )
                        Spacer()
                        controlsView
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: showingControls)
                }

                PlayerSkipToast(
                    skippedCount: skippedClipCount,
                    isVisible: showSkipToast
                )
            }
        }
        .onAppear {
            hasAppeared = true
            appearanceTime = Date()
            if FeatureFlags.playbackEngineV2Phase1 {
                Task { await preparePlayerV2() }
                setupControlsTimerV2()
            } else {
                Task { await preparePlayer() }
                setupControlsTimer()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .autoHideControls)) { _ in
            // Hide controls when timer fires (if conditions are met)
            if engine.isPlaying && engine.error == nil && !engine.isPreparing && !engine.isBuffering {
                withAnimation {
                    showingControlsV2 = false
                }
            }
        }
        .onDisappear {
            TapesLog.player.info("TapePlayerView: onDisappear called (appearanceTime: \(appearanceTime != nil ? "set" : "nil"), buffering: \(engine.isBuffering))")
            
            // Prevent premature teardown during SwiftUI lifecycle transitions
            if FeatureFlags.playbackEngineV2Phase1 {
                // Don't tear down if we just appeared or are actively buffering or preparing
                if engine.isBuffering || engine.isPreparing {
                    TapesLog.player.warning("TapePlayerView: Ignoring onDisappear - engine is still buffering (\(engine.isBuffering)) or preparing (\(engine.isPreparing))")
                    return
                }
                
                // Check if engine is still preparing (hasn't started playing yet)
                // Use a longer timeout - preparation can take 15+ seconds
                if engine.player == nil && engine.error == nil {
                    if let appearanceTime = appearanceTime {
                        let timeSinceAppearance = Date().timeIntervalSince(appearanceTime)
                        // Allow up to 30 seconds for preparation before allowing teardown (Photos can be slow)
                        if timeSinceAppearance < 30.0 {
                            TapesLog.player.warning("TapePlayerView: Ignoring onDisappear - engine is still preparing (only \(String(format: "%.1f", timeSinceAppearance))s since appearance)")
                            return
                        }
                    } else {
                        // No appearance time but no player - still preparing
                        TapesLog.player.warning("TapePlayerView: Ignoring onDisappear - engine is still preparing (no player yet, no appearanceTime)")
                        return
                    }
                }
                
                if let appearanceTime = appearanceTime {
                    let timeSinceAppearance = Date().timeIntervalSince(appearanceTime)
                    if timeSinceAppearance < 3.0 {
                        TapesLog.player.warning("TapePlayerView: Ignoring premature onDisappear (only \(String(format: "%.2f", timeSinceAppearance))s since appearance)")
                        return
                    }
                } else if hasAppeared {
                    // Has appeared but no time recorded - still ignore for safety
                    TapesLog.player.warning("TapePlayerView: Ignoring onDisappear - hasAppeared=true but no appearanceTime")
                    return
                }
            } else {
                // For legacy path
                if isLoading {
                    TapesLog.player.warning("TapePlayerView: Ignoring onDisappear - legacy path is loading")
                    return
                }
                
                if let appearanceTime = appearanceTime {
                    let timeSinceAppearance = Date().timeIntervalSince(appearanceTime)
                    if timeSinceAppearance < 2.0 {
                        return
                    }
                }
            }
            
            TapesLog.player.info("TapePlayerView: Proceeding with teardown")
            tearDown()
            hasAppeared = false
            appearanceTime = nil
        }
    }

    private var tapCatcher: some View {
        Color.clear
            .contentShape(Rectangle())
            .allowsHitTesting(!showingControls)
            .onTapGesture {
                if !showingControls {
                    toggleControls()
                }
            }
    }
    
    private var tapCatcherV2: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                toggleControlsV2()
            }
    }

    // MARK: - Loading Overlay

    private var loadingOverlay: some View {
        PlayerLoadingOverlay(
            isLoading: isLoading,
            loadError: loadError
        )
    }

    // MARK: - Controls View

    private var controlsView: some View {
        VStack(spacing: 32) {
            PlayerProgressBar(
                currentTime: currentTime,
                totalDuration: totalDuration,
                onSeek: { time in
                    seek(to: time, autoplay: isPlaying)
                }
            )
            
            PlayerControls(
                isPlaying: isPlaying,
                canGoBack: currentClipIndex > 0,
                canGoForward: timeline != nil && currentClipIndex < (timeline?.segments.count ?? 1) - 1,
                onPlayPause: togglePlayPause,
                onPrevious: previousClip,
                onNext: nextClip
            )
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
    }
    
    private var controlsViewV2: some View {
        VStack(spacing: 32) {
            // Phase 3: Thumbnail scrubber or standard progress bar
            if FeatureFlags.playbackEngineV2Phase3 {
                // TODO: Integrate ThumbnailScrubber when thumbnails are generated
                PlayerProgressBar(
                    currentTime: engine.currentTime,
                    totalDuration: engine.duration,
                    onSeek: { time in
                        engine.seek(to: time)
                    }
                )
            } else {
                PlayerProgressBar(
                    currentTime: engine.currentTime,
                    totalDuration: engine.duration,
                    onSeek: { time in
                        engine.seek(to: time)
                    }
                )
            }
            
            // Phase 3: Advanced controls or standard controls
            if FeatureFlags.playbackEngineV2Phase3 {
                AdvancedPlayerControls(
                    isPlaying: engine.isPlaying,
                    playbackSpeed: engine.playbackSpeed,
                    canGoBack: engine.currentClipIndex > 0,
                    canGoForward: engine.currentClipIndex < tape.clips.count - 1,
                    onPlayPause: {
                        if engine.isPlaying {
                            engine.pause()
                        } else {
                            engine.play()
                        }
                    },
                    onPrevious: {
                        // Find previous playable clip (accounting for skips)
                        let prevIndex = engine.currentClipIndex - 1
                        
                        guard prevIndex >= 0 else {
                            // Already at first clip
                            return
                        }
                        
                        if let skipHandler = engine.skipHandler {
                            // Use skipHandler to find previous ready clip (handles skipped clips)
                            if let prevReady = skipHandler.previousReadyClip(before: engine.currentClipIndex) {
                                engine.seekToClip(at: prevReady)
                            } else {
                                // No previous ready clip found, but try previous index if not skipped
                                if !skipHandler.shouldSkip(clipIndex: prevIndex) {
                                    engine.seekToClip(at: prevIndex)
                                }
                            }
                        } else {
                            // No skipHandler - just go to previous clip
                            engine.seekToClip(at: prevIndex)
                        }
                    },
                    onNext: {
                        // Find next playable clip (accounting for skips)
                        let nextIndex = engine.currentClipIndex + 1
                        
                        guard nextIndex < tape.clips.count else {
                            // Already at last clip
                            return
                        }
                        
                        if let skipHandler = engine.skipHandler {
                            // Use skipHandler to find next ready clip (handles skipped clips)
                            if let nextReady = skipHandler.nextReadyClip(after: engine.currentClipIndex) {
                                engine.seekToClip(at: nextReady)
                            } else {
                                // No next ready clip found, but try next index if not skipped
                                if !skipHandler.shouldSkip(clipIndex: nextIndex) {
                                    engine.seekToClip(at: nextIndex)
                                }
                            }
                        } else {
                            // No skipHandler - just go to next clip
                            engine.seekToClip(at: nextIndex)
                        }
                    },
                    onSpeedChange: { speed in
                        engine.setPlaybackSpeed(speed)
                    },
                    onFrameStep: { direction in
                        engine.stepFrame(direction: direction)
                    }
                )
            } else {
                PlayerControls(
                    isPlaying: engine.isPlaying,
                    canGoBack: engine.currentClipIndex > 0,
                    canGoForward: engine.currentClipIndex < tape.clips.count - 1,
                    onPlayPause: {
                        if engine.isPlaying {
                            engine.pause()
                        } else {
                            engine.play()
                        }
                    },
                    onPrevious: {
                        // Find previous playable clip (accounting for skips)
                        let prevIndex = engine.currentClipIndex - 1
                        
                        guard prevIndex >= 0 else {
                            // Already at first clip
                            return
                        }
                        
                        if let skipHandler = engine.skipHandler {
                            // Use skipHandler to find previous ready clip (handles skipped clips)
                            if let prevReady = skipHandler.previousReadyClip(before: engine.currentClipIndex) {
                                engine.seekToClip(at: prevReady)
                            } else {
                                // No previous ready clip found, but try previous index if not skipped
                                if !skipHandler.shouldSkip(clipIndex: prevIndex) {
                                    engine.seekToClip(at: prevIndex)
                                }
                            }
                        } else {
                            // No skipHandler - just go to previous clip
                            engine.seekToClip(at: prevIndex)
                        }
                    },
                    onNext: {
                        // Find next playable clip (accounting for skips)
                        let nextIndex = engine.currentClipIndex + 1
                        
                        guard nextIndex < tape.clips.count else {
                            // Already at last clip
                            return
                        }
                        
                        if let skipHandler = engine.skipHandler {
                            // Use skipHandler to find next ready clip (handles skipped clips)
                            if let nextReady = skipHandler.nextReadyClip(after: engine.currentClipIndex) {
                                engine.seekToClip(at: nextReady)
                            } else {
                                // No next ready clip found, but try next index if not skipped
                                if !skipHandler.shouldSkip(clipIndex: nextIndex) {
                                    engine.seekToClip(at: nextIndex)
                                }
                            }
                        } else {
                            // No skipHandler - just go to next clip
                            engine.seekToClip(at: nextIndex)
                        }
                    }
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
    }

    // MARK: - Player Preparation (Phase 1 - New Engine)
    
    @MainActor
    private func preparePlayerV2() async {
        // Set loading state immediately before async preparation starts
        // This ensures UI shows loading overlay right away
        engine.setError(nil) // Clear any previous errors
        // isPreparing and isBuffering are set inside prepare(), but we want immediate UI feedback
        // The prepare() function will set these, but let's ensure they're observed
        await engine.prepare(tape: tape)
    }
    
    private func toggleControlsV2() {
        if showingControlsV2 {
            // Hide controls
            withAnimation { showingControlsV2 = false }
            controlsTimerV2?.invalidate()
            controlsTimerV2 = nil
        } else {
            // Show controls
            withAnimation { showingControlsV2 = true }
            // Auto-hide after 3 seconds if playing
            setupControlsTimerV2()
        }
    }
    
    private func setupControlsTimerV2() {
        controlsTimerV2?.invalidate()
        // Timer will auto-hide controls after 3 seconds
        // Capture engine reference (it's a @StateObject, so it's a reference type)
        let engineRef = engine
        controlsTimerV2 = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            Task { @MainActor in
                // Check conditions on main thread
                if engineRef.isPlaying && engineRef.error == nil && !engineRef.isPreparing && !engineRef.isBuffering {
                    // Post notification to trigger state update
                    NotificationCenter.default.post(name: .autoHideControls, object: nil)
                }
            }
        }
    }

    // MARK: - Player Preparation (Legacy)

    @MainActor
    private func preparePlayer() async {
        guard !isLoading else { return }
        guard !tape.clips.isEmpty else { return }

        isLoading = true
        loadError = nil
        isUsingFullComposition = false
        skippedClipCount = 0
        showSkipToast = false
        skipToastWorkItem?.cancel()
        skipToastWorkItem = nil
        playbackIntent = false
        pendingComposition = nil
        pendingAutoplay = false
        pendingCompositionIsFinal = false

        let coordinator = coordinatorHolder.coordinator
        coordinator.cancel()

        coordinator.prepare(
            tape: tape,
            onWarmupReady: { result in
                Task { @MainActor in
                    handlePreparedResult(result, isFinal: false)
                }
            },
            onProgress: { result in
                Task { @MainActor in
                    handlePreparedResult(result, isFinal: false)
                }
            },
            onCompletion: { result in
                Task { @MainActor in
            handlePreparedResult(result, isFinal: true)
                }
            },
            onSkip: { reason, index in
                Task { @MainActor in
                    recordSkip(reason: reason, index: index)
                }
            },
            onError: { error in
                Task { @MainActor in
                    handlePreparationError(error)
                }
            }
        )
    }

    @MainActor
    private func handlePreparedResult(_ result: PlaybackPreparationCoordinator.PreparedResult, isFinal: Bool) {
        let composition = result.composition
        loadError = nil
        isLoading = false
        isFinished = false
        if player == nil {
            installInitialPlayer(with: composition)
            isUsingFullComposition = isFinal
            return
        }

        guard let player else { return }

        let isCurrentlyPlaying = player.rate != 0 || player.timeControlStatus == .playing

        if !isCurrentlyPlaying {
            pendingComposition = nil
            pendingAutoplay = false
            pendingCompositionIsFinal = false
            let shouldAutoplay = playbackIntent || isPlaying
            let current = player.currentTime()
            swapPlayerItem(
                with: composition,
                preserveTime: current,
                autoplay: shouldAutoplay,
                isFinal: isFinal
            )
        } else {
            pendingComposition = composition
            pendingAutoplay = playbackIntent || isPlaying
            pendingCompositionIsFinal = pendingCompositionIsFinal || isFinal

            // Update UI timeline immediately so controls reflect latest duration.
            timeline = composition.timeline
            totalDuration = CMTimeGetSeconds(composition.timeline.totalDuration)
        }
    }

    // MARK: - Playback Helpers

    @MainActor
    private func seekToClip(index: Int, autoplay: Bool) {
        guard let player, let timeline, index >= 0, index < timeline.segments.count else { return }
        applyPendingComposition(force: true, resumeOverride: autoplay)
        let start = timeline.segments[index].timeRange.start
        player.seek(to: start, toleranceBefore: .zero, toleranceAfter: .zero)
        currentClipIndex = index
        isFinished = false
        if autoplay {
            player.play()
            isPlaying = true
        }
        playbackIntent = autoplay
    }

    @MainActor
    private func seek(to seconds: Double, autoplay: Bool) {
        guard let player, let timeline else { return }
        applyPendingComposition(force: true, resumeOverride: autoplay)
        let clamped = max(0, min(seconds, totalDuration))
        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            if autoplay {
                player.play()
                isPlaying = true
            }
        }
        playbackIntent = autoplay
        updateClipIndex(for: time)
    }

    @MainActor
    @discardableResult
    private func applyPendingComposition(force: Bool = false, resumeOverride: Bool? = nil) -> Bool {
        guard let pending = pendingComposition, let player else { return false }
        let isCurrentlyPlaying = player.rate != 0 || player.timeControlStatus == .playing
        if isCurrentlyPlaying && !force {
            return false
        }

        let resume = resumeOverride ?? pendingAutoplay
        let pendingWasFinal = pendingCompositionIsFinal

        pendingComposition = nil
        pendingAutoplay = false
        pendingCompositionIsFinal = false

        let current = player.currentTime()

        if isCurrentlyPlaying {
            player.pause()
            isPlaying = false
        }

        swapPlayerItem(
            with: pending,
            preserveTime: current,
            autoplay: resume,
            isFinal: pendingWasFinal
        )
        playbackIntent = resume

        if pendingWasFinal {
            isUsingFullComposition = true
        }

        return true
    }

    private func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            playbackIntent = false
            _ = applyPendingComposition(force: false, resumeOverride: false)
        } else {
            playbackIntent = true
            if !applyPendingComposition(force: false, resumeOverride: true) {
                player.play()
                isPlaying = true
            }
        }
    }

    @MainActor
    private func swapPlayerItem(
        with composition: TapeCompositionBuilder.PlayerComposition,
        preserveTime: CMTime?,
        autoplay: Bool,
        isFinal: Bool
    ) {
        guard let player else {
            installInitialPlayer(with: composition)
            isUsingFullComposition = isFinal
            return
        }

        removeTimeObserver()
        player.pause()
        player.replaceCurrentItem(with: composition.playerItem)
        installEndObserver(for: composition.playerItem)
        installTimeObserver(on: player)

        timeline = composition.timeline
        totalDuration = CMTimeGetSeconds(composition.timeline.totalDuration)
        isUsingFullComposition = isFinal
        playbackIntent = autoplay

        let targetSeconds: Double
        if let preserveTime {
            targetSeconds = min(
                max(0, CMTimeGetSeconds(preserveTime)),
                totalDuration.isFinite && totalDuration > 0 ? totalDuration : CMTimeGetSeconds(preserveTime)
            )
        } else {
            targetSeconds = 0
        }

        let targetTime = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            if autoplay {
                player.play()
                isPlaying = true
            } else {
                isPlaying = false
            }
            updateClipIndex(for: targetTime)
            isFinished = false
        }
    }

    private func nextClip() {
        seekToClip(index: currentClipIndex + 1, autoplay: true)
    }

    private func previousClip() {
        seekToClip(index: currentClipIndex - 1, autoplay: true)
    }

    private func toggleControls() {
        if showingControls {
            withAnimation { showingControls = false }
            controlsTimer?.invalidate()
            controlsTimer = nil
        } else {
            withAnimation { showingControls = true }
            setupControlsTimer()
        }
    }

    private func setupControlsTimer() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation {
                showingControls = false
            }
        }
    }

    @MainActor
    private func installInitialPlayer(with composition: TapeCompositionBuilder.PlayerComposition) {
        timeline = composition.timeline
        totalDuration = CMTimeGetSeconds(composition.timeline.totalDuration)
        let player = AVPlayer(playerItem: composition.playerItem)
        player.actionAtItemEnd = .pause
        installEndObserver(for: composition.playerItem)
        installTimeObserver(on: player)
        self.player = player
        isFinished = false
        currentClipIndex = 0
        seekToClip(index: 0, autoplay: true)
    }

    @MainActor
    private func handlePreparationError(_ error: Error) {
        if let coordinatorError = error as? PlaybackPreparationCoordinator.CoordinatorError {
            loadError = coordinatorError.localizedDescription
        } else {
            loadError = error.localizedDescription
        }
        isLoading = false
        isUsingFullComposition = false
        skipToastWorkItem?.cancel()
        skipToastWorkItem = nil
        showSkipToast = false
        skippedClipCount = 0
        playbackIntent = false
        pendingComposition = nil
        pendingAutoplay = false
        pendingCompositionIsFinal = false
        player?.pause()
        player = nil
        timeline = nil
    }

    // MARK: - Observers

    private func installEndObserver(for item: AVPlayerItem) {
        if let token = playerEndObserver {
            NotificationCenter.default.removeObserver(token)
        }
        playerEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            let resumeIntent = self.pendingAutoplay || self.playbackIntent
            if self.applyPendingComposition(force: true, resumeOverride: resumeIntent) {
                self.isFinished = false
                self.playbackIntent = resumeIntent
                if resumeIntent {
                    withAnimation {
                        self.showingControls = false
                    }
                } else {
                    self.showingControls = true
                }
                return
            }

            if self.isUsingFullComposition {
                self.playbackIntent = false
                self.isFinished = true
            } else {
                self.isFinished = false
            }
            self.isPlaying = false
            self.showingControls = true
        }
    }

    private func installTimeObserver(on player: AVPlayer) {
        removeTimeObserver()
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            updatePlaybackMetrics(currentTime: time, rate: player.rate)
        }
    }

    private func removeTimeObserver() {
        if let token = timeObserverToken, let player {
            player.removeTimeObserver(token)
        }
        timeObserverToken = nil
    }

    private func tearDown() {
        if FeatureFlags.playbackEngineV2Phase1 {
            engine.teardown()
            controlsTimerV2?.invalidate()
            controlsTimerV2 = nil
        } else {
            coordinatorHolder.coordinator.cancel()
            removeTimeObserver()
            if let token = playerEndObserver {
                NotificationCenter.default.removeObserver(token)
            }
            playerEndObserver = nil
            skipToastWorkItem?.cancel()
            skipToastWorkItem = nil
            showSkipToast = false
            skippedClipCount = 0
            playbackIntent = false
            pendingComposition = nil
            pendingAutoplay = false
            pendingCompositionIsFinal = false
            player?.pause()
            player = nil
            controlsTimer?.invalidate()
            controlsTimer = nil
        }
    }

    // MARK: - Metrics

    private func updatePlaybackMetrics(currentTime time: CMTime, rate: Float) {
        let seconds = max(CMTimeGetSeconds(time), 0)
        currentTime = seconds
        isPlaying = rate > 0

        updateClipIndex(for: time)

        if let timeline,
           seconds >= CMTimeGetSeconds(timeline.totalDuration) - 0.05 {
            if isUsingFullComposition {
                isFinished = true
                isPlaying = false
                showingControls = true
            }
        }
    }

    private func updateClipIndex(for time: CMTime) {
        guard let timeline else { return }
        for segment in timeline.segments.enumerated().reversed() {
            if CMTimeCompare(time, segment.element.timeRange.start) >= 0 {
                if currentClipIndex != segment.offset {
                    currentClipIndex = segment.offset
                }
                break
            }
        }
    }

    // MARK: - Helpers

    private var progressFraction: CGFloat {
        guard totalDuration > 0 else { return 0 }
        return CGFloat(currentTime / totalDuration)
    }

    private func formatTime(_ time: Double) -> String {
        guard time.isFinite else { return "0:00" }
        let clamped = max(0, time)
        let minutes = Int(clamped) / 60
        let seconds = Int(clamped) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Skip Handling & Toasts

extension TapePlayerView {
    @MainActor
    private func recordSkip(
        reason: PlaybackPreparationCoordinator.SkipReason,
        index: Int,
        showToast: Bool = true
    ) {
        skippedClipCount += 1
        TapesLog.player.warning("PlaybackPrep: skipped clip \(index) due to \(reason.rawValue)")

        guard showToast else { return }

        skipToastWorkItem?.cancel()
        withAnimation {
            showSkipToast = true
        }

        let workItem = DispatchWorkItem {
            withAnimation {
                showSkipToast = false
                skippedClipCount = 0
            }
        }
        skipToastWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: workItem)
    }

}
