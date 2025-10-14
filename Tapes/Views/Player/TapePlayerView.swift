import SwiftUI
import AVFoundation
import AVKit

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

    let tape: Tape
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .disabled(true)
                    .onTapGesture { toggleControls() }
                    .overlay(overlayContent)
                    .onDisappear { player.pause() }
            } else {
                overlayContent
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
        }
        .onAppear {
            Task { await preparePlayer() }
            setupControlsTimer()
        }
        .onDisappear {
            tearDown()
        }
    }

    // MARK: - Overlay

    private var overlayContent: some View {
        VStack {
            if isLoading {
                ProgressView("Preparing tape…")
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

        do {
            let builder = TapeCompositionBuilder()
            let result = try await builder.buildPlayerItem(for: tape)
            timeline = result.timeline
            totalDuration = CMTimeGetSeconds(result.timeline.totalDuration)

            let player = AVPlayer(playerItem: result.playerItem)
            player.actionAtItemEnd = .pause
            installEndObserver(for: result.playerItem)
            installTimeObserver(on: player)
            self.player = player
            isFinished = false
            currentClipIndex = 0
            seekToClip(index: 0, autoplay: true)
        } catch {
            loadError = error.localizedDescription
            player?.pause()
            player = nil
            timeline = nil
        }

        isLoading = false
    }

    // MARK: - Playback Helpers

    @MainActor
    private func seekToClip(index: Int, autoplay: Bool) {
        guard let player, let timeline, index >= 0, index < timeline.segments.count else { return }
        let start = timeline.segments[index].timeRange.start
        player.seek(to: start, toleranceBefore: .zero, toleranceAfter: .zero)
        currentClipIndex = index
        isFinished = false
        if autoplay {
            player.play()
            isPlaying = true
        }
    }

    @MainActor
    private func seek(to seconds: Double, autoplay: Bool) {
        guard let player, let timeline else { return }
        let clamped = max(0, min(seconds, totalDuration))
        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            if autoplay {
                player.play()
                isPlaying = true
            }
        }
        updateClipIndex(for: time)
    }

    private func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    private func nextClip() {
        seekToClip(index: currentClipIndex + 1, autoplay: true)
    }

    private func previousClip() {
        seekToClip(index: currentClipIndex - 1, autoplay: true)
    }

    private func toggleControls() {
        withAnimation {
            showingControls.toggle()
        }
        if showingControls {
            setupControlsTimer()
        } else {
            controlsTimer?.invalidate()
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
            self.isPlaying = false
            self.isFinished = true
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
        controlsTimer?.invalidate()
        controlsTimer = nil
        removeTimeObserver()
        if let token = playerEndObserver {
            NotificationCenter.default.removeObserver(token)
        }
        playerEndObserver = nil
        player?.pause()
        player = nil
    }

    // MARK: - Metrics

    private func updatePlaybackMetrics(currentTime time: CMTime, rate: Float) {
        let seconds = max(CMTimeGetSeconds(time), 0)
        currentTime = seconds
        isPlaying = rate > 0

        updateClipIndex(for: time)

        if let timeline, seconds >= CMTimeGetSeconds(timeline.totalDuration) - 0.05 {
            isFinished = true
            isPlaying = false
            showingControls = true
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
