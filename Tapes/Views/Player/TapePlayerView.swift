import SwiftUI
import AVFoundation
import AVKit

// MARK: - Unified Tape Player View (Per-Clip Preview)

struct TapePlayerView: View {
    private let builder = TapeCompositionBuilder()
    private let prefetchWindow = 2

    @State private var timeline: TapeCompositionBuilder.Timeline?
    @State private var primaryPlayer: AVPlayer?
    @State private var secondaryPlayer: AVPlayer?
    @State private var activeSlot: PlayerSlot = .primary
    @State private var isTransitioning = false
    @State private var transitionProgress: CGFloat = 0
    @State private var transitionStyle: TransitionType = .none
    @State private var transitionTask: Task<Void, Never>?
    @State private var volumeTask: Task<Void, Never>?

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
    @State private var clipCache: [Int: TapeCompositionBuilder.PlayerComposition] = [:]
    @State private var clipLoadTasks: [Int: Task<TapeCompositionBuilder.PlayerComposition, Error>] = [:]
    @State private var isSeekingToClip: Bool = false
    @State private var isTornDown: Bool = false

    @State private var skippedClipCount: Int = 0
    @State private var showSkipToast: Bool = false
    @State private var skipToastWorkItem: DispatchWorkItem?

    let tape: Tape
    let onDismiss: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                ZStack {
                    playerView(for: .primary, size: proxy.size)
                    playerView(for: .secondary, size: proxy.size)
                }

                if showingControls {
                    VStack {
                        PlayerHeader(
                            currentClipIndex: currentClipIndex,
                            totalClips: tape.clips.count,
                            onDismiss: {
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

                loadingOverlay
            }
            .onAppear {
                Task { await preparePlayer() }
                setupControlsTimer()
            }
            .onDisappear {
                stopPlaybackImmediately()
                tearDown()
            }
        }
    }

    // MARK: - Player Views

    private func playerView(for slot: PlayerSlot, size: CGSize) -> some View {
        Group {
            if let player = player(for: slot) {
                VideoPlayer(player: player)
                    .disabled(true)
                    .overlay(tapCatcher)
                    .opacity(opacity(for: slot))
                    .offset(offset(for: slot, size: size))
            }
        }
    }

    private func opacity(for slot: PlayerSlot) -> Double {
        guard isTransitioning else {
            return slot == activeSlot ? 1.0 : 0.0
        }
        let progress = Double(transitionProgress)
        return slot == activeSlot ? (1.0 - progress) : progress
    }

    private func offset(for slot: PlayerSlot, size: CGSize) -> CGSize {
        guard isTransitioning else { return .zero }
        switch transitionStyle {
        case .slideLR:
            if slot == activeSlot {
                return CGSize(width: transitionProgress * size.width, height: 0)
            }
            return CGSize(width: (transitionProgress - 1) * size.width, height: 0)
        case .slideRL:
            if slot == activeSlot {
                return CGSize(width: -transitionProgress * size.width, height: 0)
            }
            return CGSize(width: (1 - transitionProgress) * size.width, height: 0)
        default:
            return .zero
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

    private var loadingOverlay: some View {
        PlayerLoadingOverlay(
            isLoading: isLoading,
            loadError: loadError
        )
        .zIndex(100)
        .opacity(isLoading ? 1 : 0)
        .allowsHitTesting(isLoading)
    }

    // MARK: - Controls View

    private var controlsView: some View {
        VStack(spacing: 32) {
            PlayerProgressBar(
                currentTime: currentTime,
                totalDuration: totalDuration,
                onSeek: { time in
                    Task { await seek(to: time, autoplay: isPlaying) }
                }
            )

            PlayerControls(
                isPlaying: isPlaying,
                canGoBack: currentClipIndex > 0,
                canGoForward: (timeline?.segments.count ?? 1) > currentClipIndex + 1,
                onPlayPause: togglePlayPause,
                onPrevious: previousClip,
                onNext: nextClip
            )
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
    }

    // MARK: - Preparation

    @MainActor
    private func preparePlayer() async {
        guard !isLoading else { return }
        guard !tape.clips.isEmpty else { return }

        resetState()
        isLoading = true

        do {
            let timeline = try await builder.prepareTimeline(for: tape)
            self.timeline = timeline
            totalDuration = CMTimeGetSeconds(timeline.totalDuration)
            try await loadClip(index: 0, autoplay: true, forceSlot: .primary)
            prefetchAround(index: 0)
        } catch {
            loadError = error.localizedDescription
        }

        isLoading = false
    }

    @MainActor
    private func loadClip(index: Int, autoplay: Bool, forceSlot: PlayerSlot? = nil) async throws {
        guard let timeline, index >= 0, index < timeline.segments.count else {
            throw TapeCompositionBuilder.BuilderError.assetUnavailable(clipID: UUID())
        }

        let composition = try await loadClipComposition(index: index, timeline: timeline)
        let slot = forceSlot ?? activeSlot
        installComposition(composition, in: slot, autoplay: autoplay, seekTime: .zero)

        currentClipIndex = index
        isFinished = false
        updateGlobalTime(with: .zero, for: index)
    }

    @MainActor
    private func loadClipComposition(
        index: Int,
        timeline: TapeCompositionBuilder.Timeline
    ) async throws -> TapeCompositionBuilder.PlayerComposition {
        if let cached = clipCache[index] {
            return cached
        }

        if let task = clipLoadTasks[index] {
            return try await task.value
        }

        let task = Task {
            try await builder.buildSingleClipPlayerItem(for: tape, clipIndex: index, timeline: timeline)
        }
        clipLoadTasks[index] = task
        defer { clipLoadTasks[index] = nil }
        let composition = try await task.value
        clipCache[index] = composition
        trimCache(around: index)
        return composition
    }

    // MARK: - Playback

    @MainActor
    private func togglePlayPause() {
        guard let active = activePlayer() else { return }
        if isPlaying {
            pausePlayers()
        } else {
            active.play()
            if isTransitioning {
                inactivePlayer()?.play()
            }
            isPlaying = true
        }
    }

    @MainActor
    private func nextClip() {
        Task { await jumpToClip(index: currentClipIndex + 1, autoplay: true) }
    }

    @MainActor
    private func previousClip() {
        Task { await jumpToClip(index: currentClipIndex - 1, autoplay: true) }
    }

    @MainActor
    private func jumpToClip(index: Int, autoplay: Bool) async {
        guard let timeline else { return }
        let clampedIndex = max(0, min(index, timeline.segments.count - 1))
        guard clampedIndex != currentClipIndex else { return }

        cancelTransition()
        isLoading = true
        do {
            try await loadClip(index: clampedIndex, autoplay: autoplay, forceSlot: activeSlot)
            if autoplay {
                activePlayer()?.play()
                isPlaying = true
            } else {
                isPlaying = false
            }
            prefetchAround(index: clampedIndex)
        } catch {
            recordSkip(showToast: true)
        }
        isLoading = false
    }

    @MainActor
    private func seek(to seconds: Double, autoplay: Bool) async {
        guard let timeline else { return }
        let clamped = max(0, min(seconds, totalDuration))

        guard let targetSegment = timeline.segments.first(where: { segment in
            let start = CMTimeGetSeconds(segment.timeRange.start)
            let end = start + CMTimeGetSeconds(segment.timeRange.duration)
            return clamped >= start && clamped < end
        }) else { return }

        let targetIndex = targetSegment.clipIndex
        let localTime = CMTime(seconds: clamped - CMTimeGetSeconds(targetSegment.timeRange.start), preferredTimescale: 600)

        cancelTransition()
        isSeekingToClip = true
        isLoading = true
        do {
            let composition = try await loadClipComposition(index: targetIndex, timeline: timeline)
            installComposition(composition, in: activeSlot, autoplay: autoplay, seekTime: localTime)
            currentClipIndex = targetIndex
            updateGlobalTime(with: localTime, for: targetIndex)
            if autoplay {
                activePlayer()?.play()
                isPlaying = true
            } else {
                isPlaying = false
            }
            prefetchAround(index: targetIndex)
        } catch {
            recordSkip(showToast: true)
        }
        isLoading = false
        isSeekingToClip = false
    }

    // MARK: - Transition Handling

    @MainActor
    private func maybeStartTransition(localTime: CMTime) {
        guard let timeline, isPlaying, !isTransitioning else { return }
        guard currentClipIndex < timeline.segments.count - 1 else { return }

        let segment = timeline.segments[currentClipIndex]
        guard let transition = segment.outgoingTransition else { return }
        guard transition.style != .none else { return }

        let durationSeconds = CMTimeGetSeconds(segment.timeRange.duration)
        let elapsed = CMTimeGetSeconds(localTime)
        let transitionDuration = CMTimeGetSeconds(transition.duration)
        let remaining = durationSeconds - elapsed

        if remaining <= transitionDuration {
            transitionTask?.cancel()
            transitionTask = Task { @MainActor in
                await startTransition(to: currentClipIndex + 1, descriptor: transition)
            }
        }
    }

    @MainActor
    private func startTransition(
        to nextIndex: Int,
        descriptor: TapeCompositionBuilder.TransitionDescriptor
    ) async {
        guard let timeline else { return }
        guard nextIndex < timeline.segments.count else { return }
        guard !isTransitioning else { return }

        do {
            let composition = try await loadClipComposition(index: nextIndex, timeline: timeline)
            let inactive = inactiveSlot()
            installComposition(composition, in: inactive, autoplay: true, seekTime: .zero)

            transitionStyle = descriptor.style
            isTransitioning = true
            transitionProgress = 0

            let duration = max(0.1, CMTimeGetSeconds(descriptor.duration))
            rampVolumes(duration: duration)

            withAnimation(.linear(duration: duration)) {
                transitionProgress = 1
            }

            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            finalizeTransition(to: nextIndex, duration: duration)
        } catch {
            recordSkip(showToast: true)
        }
    }

    @MainActor
    private func finalizeTransition(to nextIndex: Int, duration: Double) {
        guard isTransitioning else { return }
        let oldSlot = activeSlot
        let newSlot = inactiveSlot()

        activeSlot = newSlot
        currentClipIndex = nextIndex
        isTransitioning = false
        transitionProgress = 0

        player(for: oldSlot)?.pause()
        player(for: oldSlot)?.replaceCurrentItem(with: nil)
        player(for: oldSlot)?.volume = 1.0
        player(for: newSlot)?.volume = 1.0

        installObservers(on: newSlot)
        prefetchAround(index: nextIndex)
    }

    @MainActor
    private func cancelTransition() {
        transitionTask?.cancel()
        transitionTask = nil
        volumeTask?.cancel()
        volumeTask = nil
        isTransitioning = false
        transitionProgress = 0
    }

    @MainActor
    private func rampVolumes(duration: Double) {
        volumeTask?.cancel()
        guard duration > 0 else { return }
        let steps = 24
        let stepDuration = duration / Double(steps)
        let active = activePlayer()
        let inactive = inactivePlayer()
        inactive?.volume = 0
        active?.volume = 1

        volumeTask = Task { @MainActor in
            for step in 0...steps {
                let progress = Double(step) / Double(steps)
                active?.volume = Float(1 - progress)
                inactive?.volume = Float(progress)
                try? await Task.sleep(nanoseconds: UInt64(stepDuration * 1_000_000_000))
            }
        }
    }

    // MARK: - Observers

    @MainActor
    private func installComposition(
        _ composition: TapeCompositionBuilder.PlayerComposition,
        in slot: PlayerSlot,
        autoplay: Bool,
        seekTime: CMTime
    ) {
        let player = player(for: slot) ?? AVPlayer()
        player.replaceCurrentItem(with: composition.playerItem)
        player.actionAtItemEnd = .pause
        setPlayer(player, for: slot)

        if slot == activeSlot {
            installObservers(on: slot)
        }

        player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            if autoplay {
                player.play()
            } else {
                player.pause()
            }
        }
    }

    @MainActor
    private func installObservers(on slot: PlayerSlot) {
        removeObservers()
        guard let player = player(for: slot), let item = player.currentItem else { return }

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            guard !isSeekingToClip else { return }
            updatePlaybackMetrics(localTime: time)
            maybeStartTransition(localTime: time)
        }

        playerEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            Task { @MainActor in
                handleClipFinished()
            }
        }
    }

    @MainActor
    private func removeObservers() {
        if let token = timeObserverToken, let player = activePlayer() {
            player.removeTimeObserver(token)
        }
        timeObserverToken = nil

        if let token = playerEndObserver {
            NotificationCenter.default.removeObserver(token)
        }
        playerEndObserver = nil
    }

    @MainActor
    private func handleClipFinished() {
        guard !isTransitioning else { return }
        if currentClipIndex < (timeline?.segments.count ?? 0) - 1 {
            Task { await jumpToClip(index: currentClipIndex + 1, autoplay: isPlaying) }
        } else {
            isFinished = true
            isPlaying = false
            showingControls = true
        }
    }

    @MainActor
    private func updatePlaybackMetrics(localTime: CMTime) {
        guard let timeline else { return }
        let localSeconds = max(CMTimeGetSeconds(localTime), 0)
        let segment = timeline.segments[currentClipIndex]
        let start = CMTimeGetSeconds(segment.timeRange.start)
        currentTime = start + localSeconds
        isPlaying = activePlayer()?.rate ?? 0 > 0
    }

    @MainActor
    private func updateGlobalTime(with localTime: CMTime, for index: Int) {
        guard let timeline, index < timeline.segments.count else { return }
        let start = CMTimeGetSeconds(timeline.segments[index].timeRange.start)
        currentTime = start + CMTimeGetSeconds(localTime)
    }

    // MARK: - Helpers

    private func setupControlsTimer() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation {
                showingControls = false
            }
        }
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

    @MainActor
    private func pausePlayers() {
        activePlayer()?.pause()
        inactivePlayer()?.pause()
        isPlaying = false
    }

    @MainActor
    private func stopPlaybackImmediately() {
        isTornDown = true
        cancelTransition()
        pausePlayers()
        activePlayer()?.replaceCurrentItem(with: nil)
        inactivePlayer()?.replaceCurrentItem(with: nil)

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Ignore errors during teardown
        }
    }

    @MainActor
    private func tearDown() {
        removeObservers()
        controlsTimer?.invalidate()
        controlsTimer = nil
        clipCache.removeAll()
        clipLoadTasks.values.forEach { $0.cancel() }
        clipLoadTasks.removeAll()
        primaryPlayer = nil
        secondaryPlayer = nil
    }

    @MainActor
    private func prefetchAround(index: Int) {
        guard let timeline else { return }
        let maxIndex = timeline.segments.count - 1
        let targets = (1...prefetchWindow).compactMap { index + $0 }.filter { $0 <= maxIndex }
        for target in targets {
            if clipCache[target] != nil { continue }
            Task { @MainActor in
                _ = try? await loadClipComposition(index: target, timeline: timeline)
            }
        }
    }

    @MainActor
    private func trimCache(around index: Int) {
        let keep = Set([index, index - 1, index + 1, index + 2])
        clipCache = clipCache.filter { keep.contains($0.key) }
    }

    private func player(for slot: PlayerSlot) -> AVPlayer? {
        switch slot {
        case .primary: return primaryPlayer
        case .secondary: return secondaryPlayer
        }
    }

    private func setPlayer(_ player: AVPlayer, for slot: PlayerSlot) {
        switch slot {
        case .primary: primaryPlayer = player
        case .secondary: secondaryPlayer = player
        }
    }

    private func activePlayer() -> AVPlayer? {
        player(for: activeSlot)
    }

    private func inactiveSlot() -> PlayerSlot {
        activeSlot == .primary ? .secondary : .primary
    }

    private func inactivePlayer() -> AVPlayer? {
        player(for: inactiveSlot())
    }

    @MainActor
    private func resetState() {
        isTornDown = false
        isFinished = false
        isPlaying = false
        isTransitioning = false
        transitionProgress = 0
        currentClipIndex = 0
        currentTime = 0
        loadError = nil
        clipCache.removeAll()
        clipLoadTasks.values.forEach { $0.cancel() }
        clipLoadTasks.removeAll()
    }
}

private enum PlayerSlot {
    case primary
    case secondary
}

// MARK: - Skip Handling & Toasts

extension TapePlayerView {
    @MainActor
    private func recordSkip(showToast: Bool) {
        skippedClipCount += 1
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
