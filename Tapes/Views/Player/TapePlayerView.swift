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

    let tape: Tape
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Tokens.Colors.primaryBackground.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .disabled(true)
                    .overlay(overlayContent)
                    .overlay(tapCatcher)
                    .onDisappear { player.pause() }
            } else {
                overlayContent
                    .overlay(tapCatcher)
            }

            if showingControls {
                VStack {
                    headerView
                    Spacer()
                    controlsView
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: showingControls)
            }

            if showSkipToast {
                skipToastOverlay
            }
        }
        .onAppear {
            Task { await preparePlayer() }
            setupControlsTimer()
        }
        .onDisappear {
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

    // MARK: - Overlay

    private var overlayContent: some View {
        VStack {
            if isLoading {
                ProgressView("Getting tape ready…")
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .foregroundColor(.white)
            } else if let loadError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.yellow)
                    Text(loadError)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                        .font(.headline)
                }
                .padding(24)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundColor(.white)
            }

            Spacer()

            Text("\(currentClipIndex + 1) of \(tape.clips.count)")
                .font(.headline)
                .foregroundColor(.white)
        }
        .padding()
    }

    // MARK: - Controls View

    private var controlsView: some View {
        VStack(spacing: 24) {
            progressView
            controlButtons
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
    }

    private var progressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 6)

                    Rectangle()
                        .fill(Color.white)
                        .frame(width: geometry.size.width * progressFraction, height: 6)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let progress = max(0, min(1, value.location.x / geometry.size.width))
                            currentTime = totalDuration * progress
                        }
                        .onEnded { value in
                            let progress = max(0, min(1, value.location.x / geometry.size.width))
                            seek(to: totalDuration * progress, autoplay: isPlaying)
                        }
                )
            }
            .frame(height: 6)

            HStack {
                Text(formatTime(currentTime))
                    .foregroundColor(.white)
                    .font(.caption)
                Spacer()
                Text(formatTime(totalDuration))
                    .foregroundColor(.white)
                    .font(.caption)
            }
        }
    }

    private var controlButtons: some View {
        HStack(spacing: 40) {
            Button(action: previousClip) {
                Image(systemName: "backward.fill")
                    .font(.title)
                    .foregroundColor(.white)
            }
            .disabled(currentClipIndex == 0)

            Button(action: togglePlayPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.largeTitle)
                    .foregroundColor(.white)
            }

            Button(action: nextClip) {
                Image(systemName: "forward.fill")
                    .font(.title)
                    .foregroundColor(.white)
            }
            .disabled(timeline == nil || currentClipIndex >= (timeline?.segments.count ?? 1) - 1)
        }
    }

    // MARK: - Player Preparation

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
        coordinatorHolder.coordinator.cancel()
        controlsTimer?.invalidate()
        controlsTimer = nil
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

    private var skipToastOverlay: some View {
        VStack {
            Spacer()
            Text("Skipped \(skippedClipCount) clip\(skippedClipCount == 1 ? "" : "s")")
                .font(.footnote)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.7))
                .clipShape(Capsule())
                .padding(.bottom, 48)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
