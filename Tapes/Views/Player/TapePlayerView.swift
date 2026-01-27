import SwiftUI
import AVFoundation
import AVKit

private final class PlaybackCoordinatorHolder: ObservableObject {
    let coordinator = PlaybackPreparationCoordinator()
}

// MARK: - Unified Tape Player View

struct TapePlayerView: View {
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
    @State private var isTornDown: Bool = false // CRITICAL: Prevent new playback after tearDown

    let tape: Tape
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .disabled(true)
                    .overlay(loadingOverlay)
                    .overlay(tapCatcher)
                    .onDisappear {
                        // AUDIO FIX: Stop audio immediately and synchronously when VideoPlayer disappears
                        player.pause()
                        player.rate = 0.0
                        player.isMuted = true
                        player.volume = 0.0
                        
                        // Deactivate audio session immediately
                        do {
                            let audioSession = AVAudioSession.sharedInstance()
                            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
                        } catch {
                            // Ignore errors in onDisappear
                        }
                    }
            } else {
                loadingOverlay
                    .overlay(tapCatcher)
            }

            if showingControls {
                VStack {
                    PlayerHeader(
                        currentClipIndex: currentClipIndex,
                        totalClips: tape.clips.count,
                        onDismiss: {
                            // AUDIO FIX: Stop playback immediately when user taps dismiss - must be synchronous
                            stopPlaybackImmediately()
                            tearDown()
                            onDismiss()
                        }
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
        .onAppear {
            Task { await preparePlayer() }
            setupControlsTimer()
        }
        .onDisappear {
            // AUDIO FIX: Stop audio immediately - must be synchronous
            // CRITICAL: Set player to nil FIRST to remove VideoPlayer from view hierarchy
            stopPlaybackImmediately()
            tearDown()
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

    // MARK: - Player Preparation

    @MainActor
    private func preparePlayer() async {
        guard !isLoading else { return }
        guard !tape.clips.isEmpty else { return }

        // Reset torn down flag when starting new playback
        isTornDown = false
        
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
        // CRITICAL: Ignore any callbacks if we're torn down - prevents new playback from starting
        guard !isTornDown else {
            TapesLog.player.info("TapePlayerView: Ignoring prepared result - view is torn down")
            return
        }
        
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

    @State private var isSeekingToClip: Bool = false
    
    @MainActor
    private func seekToClip(index: Int, autoplay: Bool) {
        guard let player, let timeline, index >= 0 else { return }
        
        // SKIP FIX: Find the requested clip or the next available clip
        let targetIndex: Int
        if index >= timeline.segments.count {
            // Requested index is beyond available segments, use the last available
            targetIndex = max(0, timeline.segments.count - 1)
        } else {
            // Use the exact index if available
            targetIndex = index
        }
        
        guard targetIndex < timeline.segments.count else { return }
        
        isSeekingToClip = true
        applyPendingComposition(force: true, resumeOverride: autoplay)
        let start = timeline.segments[targetIndex].timeRange.start
        player.seek(to: start, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            Task { @MainActor in
                self.currentClipIndex = targetIndex
                self.isSeekingToClip = false
                self.isFinished = false
                if autoplay {
                    player.play()
                    self.isPlaying = true
                }
                self.playbackIntent = autoplay
            }
        }
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

        // MEMORY FIX: Properly release old player item before replacing
        removeTimeObserver()
        
        // Remove end observer from old item
        if let oldItem = player.currentItem, let token = playerEndObserver {
            NotificationCenter.default.removeObserver(token)
            playerEndObserver = nil
        }
        
        // Cancel pending seeks on old item
        player.currentItem?.cancelPendingSeeks()
        
        // Stop playback before swapping
        player.pause()
        player.rate = 0
        
        // Replace with new item
        let oldItem = player.currentItem
        player.replaceCurrentItem(with: composition.playerItem)
        
        // Allow old item to be released
        oldItem?.cancelPendingSeeks()
        
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

    @MainActor
    private func stopPlaybackImmediately() {
        // CRITICAL: Set torn down flag FIRST to prevent any new callbacks from starting playback
        isTornDown = true
        
        // CRITICAL: Cancel coordinator FIRST to stop any new compositions from being created
        coordinatorHolder.coordinator.cancel()
        
        // CRITICAL: Clear pending composition to prevent it from being applied
        pendingComposition = nil
        pendingAutoplay = false
        pendingCompositionIsFinal = false
        
        // CRITICAL: Stop audio BEFORE anything else - this must happen first
        if let player = player {
            // Remove observers FIRST to prevent any callbacks
            removeTimeObserver()
            if let token = playerEndObserver {
                NotificationCenter.default.removeObserver(token)
                playerEndObserver = nil
            }
            
            // Stop playback IMMEDIATELY
            player.pause()
            player.rate = 0.0
            player.isMuted = true
            player.volume = 0.0
            
            // Cancel pending seeks
            player.currentItem?.cancelPendingSeeks()
            
            // CRITICAL: Remove player item BEFORE setting player to nil
            // This stops all audio/video processing
            let playerItem = player.currentItem
            player.replaceCurrentItem(with: nil)
            playerItem?.cancelPendingSeeks()
            
            // Deactivate audio session IMMEDIATELY
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                TapesLog.player.warning("Failed to deactivate audio session: \(error.localizedDescription)")
            }
            
            // Set player to nil IMMEDIATELY to remove VideoPlayer from view
            // This will cause SwiftUI to remove VideoPlayer from the view hierarchy
            self.player = nil
        } else {
            // Still deactivate audio session even if player is nil
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                TapesLog.player.warning("Failed to deactivate audio session: \(error.localizedDescription)")
            }
        }
    }
    
    @MainActor
    private func tearDown() {
        // Cleanup after player is already nil and stopped
        // Note: Coordinator already cancelled and pendingComposition cleared in stopPlaybackImmediately()
        
        // Remove observers (already done in stopPlaybackImmediately, but ensure they're gone)
        removeTimeObserver()
        if let token = playerEndObserver {
            NotificationCenter.default.removeObserver(token)
            playerEndObserver = nil
        }
        
        // Cancel all timers and work items
        controlsTimer?.invalidate()
        controlsTimer = nil
        skipToastWorkItem?.cancel()
        skipToastWorkItem = nil
        
        // Clear all state
        showSkipToast = false
        skippedClipCount = 0
        playbackIntent = false
        isPlaying = false
        isFinished = false
        isLoading = false
        isUsingFullComposition = false
        pendingComposition = nil
        pendingAutoplay = false
        pendingCompositionIsFinal = false
        currentClipIndex = 0
        currentTime = 0
        totalDuration = 0
        loadError = nil
        
        // MEMORY CLEANUP: Clear timeline (player already nil from stopPlaybackImmediately)
        autoreleasepool {
            timeline = nil
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
        // SKIP FIX: Don't update clip index during seek to prevent race conditions
        guard !isSeekingToClip, let timeline else { return }
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
