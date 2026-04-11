import SwiftUI
import AVFoundation
import AVKit
import UIKit

// MARK: - Player Slot

enum PlayerSlot {
    case primary
    case secondary
}

// MARK: - View Model

@MainActor
final class TapePlayerViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var primaryPlayer: AVPlayer?
    @Published private(set) var secondaryPlayer: AVPlayer?
    @Published private(set) var activeSlot: PlayerSlot = .primary
    @Published private(set) var isTransitioning = false
    @Published private(set) var transitionProgress: CGFloat = 0
    @Published private(set) var transitionStyle: TransitionType = .none
    @Published private(set) var currentClipIndex: Int = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var showingControls = true
    @Published private(set) var clipDuration: Double = 0
    @Published private(set) var clipTime: Double = 0
    @Published private(set) var isFinished = false
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?
    @Published private(set) var skippedClipCount: Int = 0
    @Published private(set) var showSkipToast = false
    @Published var clipVolume: Double = 1.0
    @Published var clipMusicVolume: Double = 0.3

    // MARK: - Input

    var tape: Tape
    var viewportSize: CGSize = UIScreen.main.bounds.size {
        didSet {
            let wasLandscape = oldValue.width > oldValue.height
            let isLandscape = viewportSize.width > viewportSize.height
            if wasLandscape != isLandscape {
                handleOrientationChange()
            }
        }
    }

    // MARK: - Computed Properties

    var totalClips: Int { tape.clips.count }
    var canGoBack: Bool { currentClipIndex > 0 }
    var canGoForward: Bool { (timeline?.segments.count ?? 1) > currentClipIndex + 1 }

    var totalTapeDuration: Double {
        guard let timeline else { return 0 }
        let seconds = CMTimeGetSeconds(timeline.totalDuration)
        return seconds.isFinite ? max(seconds, 0) : 0
    }

    var globalCurrentTime: Double {
        guard let timeline else { return 0 }
        var accumulated: Double = 0
        for i in 0..<min(currentClipIndex, timeline.segments.count) {
            let seg = CMTimeGetSeconds(timeline.segments[i].timeRange.duration)
            accumulated += seg.isFinite ? seg : 0
        }
        return accumulated + clipTime
    }

    // MARK: - Private State

    private let builder: TapeCompositionBuilder
    private var timeline: TapeCompositionBuilder.Timeline?
    private var transitionTask: Task<Void, Never>?
    private var volumeTask: Task<Void, Never>?
    private var autoHideTask: Task<Void, Never>?
    private var timeObserverToken: Any?
    private var timeObserverPlayer: AVPlayer?
    private var playerEndObserver: NSObjectProtocol?
    private var playerFailedObserver: NSObjectProtocol?
    private var playerStallObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var memoryWarningObserver: NSObjectProtocol?

    private var clipCache: [Int: TapeCompositionBuilder.PlayerComposition] = [:]
    private var cacheAccessOrder: [Int] = []
    private var clipLoadTasks: [Int: Task<TapeCompositionBuilder.PlayerComposition, Error>] = [:]
    private var isSeekingToClip = false
    private var isTornDown = false
    private var slotClipIndex: [PlayerSlot: Int] = [:]
    private var slotClipDuration: [PlayerSlot: Double] = [:]
    private var slotVideoNaturalSize: [PlayerSlot: CGSize] = [:]
    private var preloadTask: Task<Void, Never>?
    private var preloadNextIndex: Int = 0
    private var isInteractiveDragging = false
    private var dragTranslation: CGFloat = 0
    private var dragTargetIndex: Int?
    private var dragWasPlaying = false
    private var skipToastWorkItem: DispatchWorkItem?
    private var wasPlayingBeforeBackground = false
    private var airplayObservation: NSKeyValueObservation?
    private var isAirPlayActive = false
    private var preRenderedImageURLs: [Int: URL] = [:]
    private var preRenderTasks: [Int: Task<URL, Error>] = [:]

    private static let cacheCapacity = 10
    private static let maxConcurrentPreRenders = 2

    let backgroundMusic = BackgroundMusicPlayer()

    // MARK: - Init

    init(tape: Tape) {
        self.tape = tape
        self.builder = TapeCompositionBuilder(livePhotosAsVideo: tape.livePhotosAsVideo, livePhotosMuted: tape.livePhotosMuted)
    }

    // MARK: - Public API

    func prepare() async {
        guard !isLoading, !tape.clips.isEmpty else { return }

        resetState()
        isLoading = true
        configureAudioSession()
        registerSystemObservers()

        let hasMood = tape.musicMood != .none

        // Start music generation concurrently with video loading
        let musicTask: Task<Void, Never>? = hasMood ? Task {
            await backgroundMusic.prepare(
                mood: tape.musicMood, tapeID: tape.id, volume: tape.musicVolume
            )
        } : nil

        do {
            let tl = try await builder.prepareTimeline(for: tape)
            timeline = updateTimelineRenderSize(tl)

            if hasMood {
                // Load clip without autoplay — wait for music first
                try await loadClip(index: 0, autoplay: false, forceSlot: .primary)

                // Wait for music to be ready before starting playback
                await musicTask?.value

                // Start video and music together
                activePlayer()?.play()
                isPlaying = true
                backgroundMusic.syncPlay()
            } else {
                try await loadClip(index: 0, autoplay: true, forceSlot: .primary)
                isPlaying = true
            }

            startSequentialPreload(from: 1)
            resetControlsTimer()
        } catch {
            loadError = error.localizedDescription
        }

        isLoading = false
    }

    func shutdown() {
        isTornDown = true
        backgroundMusic.syncStop()
        cancelTransition()
        pausePlayers()
        activePlayer()?.replaceCurrentItem(with: nil)
        inactivePlayer()?.replaceCurrentItem(with: nil)
        removeObservers()
        removeSystemObservers()
        autoHideTask?.cancel()
        autoHideTask = nil
        clipCache.removeAll()
        cacheAccessOrder.removeAll()
        clipLoadTasks.values.forEach { $0.cancel() }
        clipLoadTasks.removeAll()
        primaryPlayer = nil
        secondaryPlayer = nil
        preloadTask?.cancel()
        preloadTask = nil
        preloadNextIndex = 0
        airplayObservation?.invalidate()
        airplayObservation = nil
        isAirPlayActive = false
        cleanupAllPreRenderedFiles()
        deactivateAudioSession()
    }

    func togglePlayPause() {
        if isFinished {
            replay()
            return
        }
        guard let active = activePlayer() else { return }
        if isPlaying {
            pausePlayers()
            backgroundMusic.syncPause()
        } else {
            active.play()
            if isTransitioning { inactivePlayer()?.play() }
            isPlaying = true
            backgroundMusic.syncPlay()
        }
        resetControlsTimer()
    }

    func nextClip() {
        Task { await jumpToClip(index: currentClipIndex + 1, autoplay: true) }
        resetControlsTimer()
    }

    func previousClip() {
        Task { await jumpToClip(index: currentClipIndex - 1, autoplay: true) }
        resetControlsTimer()
    }

    func seekWithinClip(_ seconds: Double) async {
        await seek(to: seconds, autoplay: isPlaying)
        resetControlsTimer()
    }

    func seekToGlobalTime(_ globalSeconds: Double) async {
        guard let timeline, !timeline.segments.isEmpty else { return }
        let clamped = max(0, min(globalSeconds, totalTapeDuration))

        var accumulated: Double = 0
        for (index, segment) in timeline.segments.enumerated() {
            let segDuration = CMTimeGetSeconds(segment.timeRange.duration)
            let safeDuration = segDuration.isFinite ? segDuration : 0
            if accumulated + safeDuration > clamped || index == timeline.segments.count - 1 {
                let localTime = clamped - accumulated
                if index != currentClipIndex {
                    cancelTransition()
                    isLoading = true
                    do {
                        try await loadClip(index: index, autoplay: isPlaying, forceSlot: activeSlot)
                    } catch {
                        await skipFailedClip(from: index, autoplay: isPlaying)
                        isLoading = false
                        return
                    }
                    isLoading = false
                }
                await seek(to: localTime, autoplay: isPlaying)
                startSequentialPreload(from: index + 1)
                return
            }
            accumulated += safeDuration
        }
        resetControlsTimer()
    }

    func replay() {
        isFinished = false
        Task {
            await jumpToClip(index: 0, autoplay: true)
        }
        resetControlsTimer()
    }

    func retryLoading() async {
        loadError = nil
        await prepare()
    }

    func toggleControls() {
        if showingControls {
            withAnimation(.easeInOut(duration: 0.2)) { showingControls = false }
            autoHideTask?.cancel()
            autoHideTask = nil
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { showingControls = true }
            resetControlsTimer()
        }
    }

    func resetControlsTimer() {
        autoHideTask?.cancel()
        guard isPlaying else { return }
        autoHideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) { self.showingControls = false }
        }
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background, .inactive:
            wasPlayingBeforeBackground = isPlaying
            if isPlaying {
                pausePlayers()
                backgroundMusic.syncPause()
            }
        case .active:
            if wasPlayingBeforeBackground {
                activePlayer()?.play()
                if isTransitioning { inactivePlayer()?.play() }
                isPlaying = true
                backgroundMusic.syncPlay()
                wasPlayingBeforeBackground = false
            }
        @unknown default:
            break
        }
    }

    // MARK: - View Helpers

    func player(for slot: PlayerSlot) -> AVPlayer? {
        switch slot {
        case .primary: return primaryPlayer
        case .secondary: return secondaryPlayer
        }
    }

    func opacity(for slot: PlayerSlot) -> Double {
        guard isTransitioning else {
            return slot == activeSlot ? 1.0 : 0.0
        }
        let progress = Double(transitionProgress)
        return slot == activeSlot ? (1.0 - progress) : progress
    }

    func offset(for slot: PlayerSlot, viewSize: CGSize) -> CGSize {
        guard isTransitioning else { return .zero }
        switch transitionStyle {
        case .slideLR:
            if slot == activeSlot {
                return CGSize(width: transitionProgress * viewSize.width, height: 0)
            }
            return CGSize(width: (transitionProgress - 1) * viewSize.width, height: 0)
        case .slideRL:
            if slot == activeSlot {
                return CGSize(width: -transitionProgress * viewSize.width, height: 0)
            }
            return CGSize(width: (1 - transitionProgress) * viewSize.width, height: 0)
        default:
            return .zero
        }
    }

    func videoGravity(for slot: PlayerSlot) -> AVLayerVideoGravity {
        guard let index = slotClipIndex[slot], index >= 0, index < tape.clips.count else {
            return tape.scaleMode == .fill ? .resizeAspectFill : .resizeAspect
        }
        let clip = tape.clips[index]
        if let override = clip.overrideScaleMode {
            return override == .fill ? .resizeAspectFill : .resizeAspect
        }
        guard let contentSize = slotVideoNaturalSize[slot],
              contentSize.width > 0, contentSize.height > 0,
              viewportSize.width > 0, viewportSize.height > 0
        else {
            return .resizeAspectFill
        }
        let contentIsLandscape = contentSize.width > contentSize.height
        let viewportIsLandscape = viewportSize.width > viewportSize.height
        return contentIsLandscape == viewportIsLandscape ? .resizeAspectFill : .resizeAspect
    }

    // MARK: - Swipe Gesture

    func handleSwipeChanged(translation: CGFloat, viewWidth: CGFloat) {
        guard let timeline else { return }
        guard !isLoading, !isSeekingToClip else { return }
        guard timeline.segments.count > 1 else { return }

        if isInteractiveDragging {
            dragTranslation = translation
            let progress = min(max(abs(translation) / max(viewWidth, 1), 0), 1)
            transitionProgress = progress
            return
        }

        guard !isTransitioning else { return }
        guard abs(translation) > 2 else { return }
        let direction: Int = translation < 0 ? 1 : -1
        let targetIndex = currentClipIndex + direction
        guard targetIndex >= 0, targetIndex < timeline.segments.count else { return }

        cancelTransition()
        isInteractiveDragging = true
        dragWasPlaying = isPlaying
        if isPlaying { pausePlayers() }
        isPlaying = false
        dragTargetIndex = targetIndex

        let rawStyle: TransitionType = translation < 0 ? .slideRL : .slideLR
        transitionStyle = UIAccessibility.isReduceMotionEnabled ? .crossfade : rawStyle
        isTransitioning = true
        transitionProgress = 0

        Task { await prepareDragTarget(index: targetIndex) }
    }

    func handleSwipeEnded(translation: CGFloat, viewWidth: CGFloat) {
        guard isInteractiveDragging else { return }
        let progress = min(max(abs(translation) / max(viewWidth, 1), 0), 1)
        if progress > 0.25 {
            completeDragTransition()
        } else {
            cancelDragTransition()
        }
    }

    // MARK: - Preparation

    private func loadClip(index: Int, autoplay: Bool, forceSlot: PlayerSlot? = nil) async throws {
        guard let timeline, index >= 0, index < timeline.segments.count else {
            throw TapeCompositionBuilder.BuilderError.assetUnavailable(clipID: UUID())
        }

        let composition = try await loadClipComposition(
            index: index,
            timeline: updateTimelineRenderSize(timeline),
            allowTrim: false
        )
        let slot = forceSlot ?? activeSlot

        if let airplayItem = await preRenderedPlayerItem(for: index) {
            installAirPlayItem(airplayItem, composition: composition, in: slot, autoplay: autoplay)
        } else {
            installComposition(composition, in: slot, autoplay: autoplay, seekTime: .zero)
        }

        currentClipIndex = index
        isFinished = false
        updateClipTime(with: .zero)
        updateVolumeForClip(at: index)
    }

    private func loadClipComposition(
        index: Int,
        timeline: TapeCompositionBuilder.Timeline,
        allowTrim: Bool = true
    ) async throws -> TapeCompositionBuilder.PlayerComposition {
        if let cached = clipCache[index] {
            touchCacheEntry(index)
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
        cacheComposition(composition, for: index)
        return composition
    }

    // MARK: - Playback Control

    private func jumpToClip(index: Int, autoplay: Bool) async {
        guard let timeline else { return }
        let clampedIndex = max(0, min(index, timeline.segments.count - 1))
        guard clampedIndex != currentClipIndex || isFinished else { return }

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
            startSequentialPreload(from: clampedIndex + 1)
        } catch {
            await skipFailedClip(from: clampedIndex, autoplay: autoplay)
        }
        isLoading = false
    }

    private func seek(to seconds: Double, autoplay: Bool) async {
        guard let active = activePlayer() else { return }
        let clamped = max(0, min(seconds, clipDuration))
        let localTime = CMTime(seconds: clamped, preferredTimescale: 600)

        cancelTransition()
        isSeekingToClip = true
        active.seek(to: localTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateClipTime(with: localTime)
                if autoplay {
                    active.play()
                    self.isPlaying = true
                } else {
                    self.isPlaying = false
                }
                self.isSeekingToClip = false
            }
        }
    }

    private func pausePlayers() {
        activePlayer()?.pause()
        inactivePlayer()?.pause()
        isPlaying = false
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            TapesLog.player.error("TapePlayerVM: Audio session configuration failed: \(error.localizedDescription)")
        }
    }

    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Ignore during teardown
        }
    }

    // MARK: - Transition Handling

    private func maybeStartTransition(localTime: CMTime) {
        guard let timeline, isPlaying, !isTransitioning, !isInteractiveDragging else { return }
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
            transitionTask = Task { [weak self] in
                guard let self else { return }
                await self.startTransition(to: self.currentClipIndex + 1, descriptor: transition)
            }
        }
    }

    private func startTransition(
        to nextIndex: Int,
        descriptor: TapeCompositionBuilder.TransitionDescriptor
    ) async {
        guard let timeline else { return }
        guard nextIndex < timeline.segments.count else { return }
        guard !isTransitioning else { return }

        do {
            let composition = try await loadClipComposition(
                index: nextIndex, timeline: timeline, allowTrim: false
            )
            let inactive = inactiveSlot()
            installComposition(composition, in: inactive, autoplay: true, seekTime: .zero)

            let effectiveStyle: TransitionType
            if UIAccessibility.isReduceMotionEnabled &&
                (descriptor.style == .slideLR || descriptor.style == .slideRL) {
                effectiveStyle = .crossfade
            } else {
                effectiveStyle = descriptor.style
            }

            transitionStyle = effectiveStyle
            isTransitioning = true
            transitionProgress = 0

            let duration = max(0.1, CMTimeGetSeconds(descriptor.duration))
            rampVolumes(duration: duration)

            let capturedNextIndex = nextIndex
            withAnimation(.linear(duration: duration)) {
                transitionProgress = 1
            } completion: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.isTransitioning else { return }
                    self.finalizeTransition(to: capturedNextIndex)
                }
            }
        } catch {
            await skipFailedClip(from: nextIndex, autoplay: isPlaying)
        }
    }

    private func finalizeTransition(to nextIndex: Int) {
        guard isTransitioning else { return }
        let oldSlot = activeSlot
        let newSlot = inactiveSlot()

        activeSlot = newSlot
        currentClipIndex = nextIndex
        updateVolumeForClip(at: nextIndex)
        isTransitioning = false
        transitionProgress = 0
        clipDuration = slotClipDuration[newSlot] ?? 0
        clipTime = 0

        player(for: oldSlot)?.pause()
        player(for: oldSlot)?.replaceCurrentItem(with: nil)
        player(for: oldSlot)?.volume = 1.0
        player(for: oldSlot)?.allowsExternalPlayback = false
        player(for: oldSlot)?.usesExternalPlaybackWhileExternalScreenIsActive = false
        player(for: newSlot)?.volume = Float(clipVolume)
        player(for: newSlot)?.allowsExternalPlayback = true
        player(for: newSlot)?.usesExternalPlaybackWhileExternalScreenIsActive = true

        installObservers(on: newSlot)
        startSequentialPreload(from: nextIndex + 1)
    }

    private func cancelTransition() {
        transitionTask?.cancel()
        transitionTask = nil
        volumeTask?.cancel()
        volumeTask = nil
        isTransitioning = false
        transitionProgress = 0
    }

    private func rampVolumes(duration: Double) {
        volumeTask?.cancel()
        guard duration > 0 else { return }
        let steps = 24
        let stepDuration = duration / Double(steps)
        let active = activePlayer()
        let inactive = inactivePlayer()
        inactive?.volume = 0
        active?.volume = 1

        volumeTask = Task { [weak self] in
            for step in 0...steps {
                guard !Task.isCancelled else { return }
                let progress = Double(step) / Double(steps)
                await MainActor.run {
                    active?.volume = Float(1 - progress)
                    inactive?.volume = Float(progress)
                }
                try? await Task.sleep(nanoseconds: UInt64(stepDuration * 1_000_000_000))
            }
        }
    }

    // MARK: - Interactive Swipe

    private func prepareDragTarget(index: Int) async {
        guard let timeline else { return }
        do {
            let composition = try await loadClipComposition(
                index: index, timeline: timeline, allowTrim: false
            )
            let inactive = inactiveSlot()
            installComposition(composition, in: inactive, autoplay: false, seekTime: .zero)
            inactivePlayer()?.pause()
            inactivePlayer()?.volume = 0
        } catch {
            cancelDragTransition()
        }
    }

    private func completeDragTransition() {
        guard let targetIndex = dragTargetIndex else {
            cancelDragTransition()
            return
        }
        let capturedDragWasPlaying = dragWasPlaying
        withAnimation(.linear(duration: 0.2)) {
            transitionProgress = 1
        } completion: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.finalizeTransition(to: targetIndex)
                if capturedDragWasPlaying {
                    self.activePlayer()?.play()
                    self.isPlaying = true
                }
                self.resetDragState()
            }
        }
    }

    private func cancelDragTransition() {
        let capturedDragWasPlaying = dragWasPlaying
        withAnimation(.linear(duration: 0.2)) {
            transitionProgress = 0
        } completion: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isTransitioning = false
                self.inactivePlayer()?.pause()
                if capturedDragWasPlaying {
                    self.activePlayer()?.play()
                    self.isPlaying = true
                }
                self.resetDragState()
            }
        }
    }

    private func resetDragState() {
        isInteractiveDragging = false
        dragTranslation = 0
        dragTargetIndex = nil
        dragWasPlaying = false
    }

    // MARK: - Observers

    private func installAirPlayItem(
        _ item: AVPlayerItem,
        composition: TapeCompositionBuilder.PlayerComposition,
        in slot: PlayerSlot,
        autoplay: Bool
    ) {
        let player = player(for: slot) ?? AVPlayer()
        player.replaceCurrentItem(with: item)
        player.actionAtItemEnd = .pause
        player.allowsExternalPlayback = (slot == activeSlot)
        player.usesExternalPlaybackWhileExternalScreenIsActive = (slot == activeSlot)
        setPlayer(player, for: slot)

        if let segment = composition.timeline.segments.first {
            slotClipIndex[slot] = segment.clipIndex
            slotVideoNaturalSize.removeValue(forKey: slot)
        }

        let durationSeconds = CMTimeGetSeconds(composition.timeline.totalDuration)
        slotClipDuration[slot] = durationSeconds
        if slot == activeSlot {
            clipDuration = durationSeconds
            clipTime = 0
            installObservers(on: slot)
            observeAirPlayState(on: player)
        }

        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            if autoplay { player.play() } else { player.pause() }
        }
    }

    private func installComposition(
        _ composition: TapeCompositionBuilder.PlayerComposition,
        in slot: PlayerSlot,
        autoplay: Bool,
        seekTime: CMTime
    ) {
        let player = player(for: slot) ?? AVPlayer()
        let playerItem = makePlayerItem(from: composition)
        player.replaceCurrentItem(with: playerItem)
        player.actionAtItemEnd = .pause
        player.allowsExternalPlayback = (slot == activeSlot)
        player.usesExternalPlaybackWhileExternalScreenIsActive = (slot == activeSlot)
        setPlayer(player, for: slot)

        if let segment = composition.timeline.segments.first {
            slotClipIndex[slot] = segment.clipIndex
            if let ctx = segment.assetContext {
                let transformed = ctx.naturalSize.applying(ctx.preferredTransform)
                slotVideoNaturalSize[slot] = CGSize(
                    width: abs(transformed.width),
                    height: abs(transformed.height)
                )
            } else if let imageSize = segment.metadata.naturalSize,
                      imageSize.width > 0, imageSize.height > 0 {
                slotVideoNaturalSize[slot] = imageSize
            } else {
                slotVideoNaturalSize.removeValue(forKey: slot)
            }
        } else {
            slotClipIndex.removeValue(forKey: slot)
            slotVideoNaturalSize.removeValue(forKey: slot)
        }

        let durationSeconds = CMTimeGetSeconds(composition.timeline.totalDuration)
        slotClipDuration[slot] = durationSeconds
        if slot == activeSlot {
            clipDuration = durationSeconds
            clipTime = CMTimeGetSeconds(seekTime)
        }

        if slot == activeSlot {
            installObservers(on: slot)
            observeAirPlayState(on: player)
        }

        player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            if autoplay { player.play() } else { player.pause() }
        }
    }

    private func installObservers(on slot: PlayerSlot) {
        removeObservers()
        guard let player = player(for: slot), let item = player.currentItem else { return }

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval, queue: .main
        ) { [weak self] time in
            guard let self else { return }
            guard !self.isSeekingToClip else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updatePlaybackMetrics(localTime: time)
                self.maybeStartTransition(localTime: time)
            }
        }
        timeObserverPlayer = player

        playerEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleClipFinished() }
        }

        playerFailedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor [weak self] in self?.handleClipFailure(error) }
        }

        playerStallObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleClipFailure(nil) }
        }
    }

    private func removeObservers() {
        if let token = timeObserverToken, let player = timeObserverPlayer {
            player.removeTimeObserver(token)
        }
        timeObserverToken = nil
        timeObserverPlayer = nil

        [playerEndObserver, playerFailedObserver, playerStallObserver]
            .compactMap { $0 }
            .forEach { NotificationCenter.default.removeObserver($0) }
        playerEndObserver = nil
        playerFailedObserver = nil
        playerStallObserver = nil
    }

    private func registerSystemObservers() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in self?.handleAudioInterruption(notification) }
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in self?.handleRouteChange(notification) }
        }

        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleMemoryWarning() }
        }
    }

    private func removeSystemObservers() {
        [interruptionObserver, routeChangeObserver, memoryWarningObserver]
            .compactMap { $0 }
            .forEach { NotificationCenter.default.removeObserver($0) }
        interruptionObserver = nil
        routeChangeObserver = nil
        memoryWarningObserver = nil
    }

    // MARK: - System Event Handlers

    private func handleAudioInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }

        switch type {
        case .began:
            if isPlaying { pausePlayers() }
            withAnimation(.easeInOut(duration: 0.2)) { showingControls = true }
        case .ended:
            if let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
                if options.contains(.shouldResume) {
                    activePlayer()?.play()
                    if isTransitioning { inactivePlayer()?.play() }
                    isPlaying = true
                    resetControlsTimer()
                }
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonRaw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else { return }

        if reason == .oldDeviceUnavailable {
            pausePlayers()
            withAnimation(.easeInOut(duration: 0.2)) { showingControls = true }
        }
    }

    private func handleMemoryWarning() {
        preloadTask?.cancel()
        preloadTask = nil

        let keepSet: Set<Int> = Set(
            [currentClipIndex - 1, currentClipIndex, currentClipIndex + 1]
                .filter { $0 >= 0 }
        )
        let keysToRemove = clipCache.keys.filter { !keepSet.contains($0) }
        for key in keysToRemove {
            clipCache.removeValue(forKey: key)
            cacheAccessOrder.removeAll { $0 == key }
            clipLoadTasks[key]?.cancel()
            clipLoadTasks.removeValue(forKey: key)
            cleanupPreRenderedFile(at: key)
        }

        for (index, task) in preRenderTasks where !keepSet.contains(index) {
            task.cancel()
            preRenderTasks.removeValue(forKey: index)
        }
    }

    private func handleOrientationChange() {
        clipCache.removeAll()
        cacheAccessOrder.removeAll()
        guard let tl = timeline, !isTornDown else { return }
        timeline = updateTimelineRenderSize(tl)
        let wasPlaying = isPlaying
        let seekTime = CMTime(seconds: clipTime, preferredTimescale: 600)
        Task { @MainActor in
            do {
                let composition = try await loadClipComposition(
                    index: currentClipIndex,
                    timeline: timeline!,
                    allowTrim: false
                )
                installComposition(composition, in: activeSlot, autoplay: wasPlaying, seekTime: seekTime)
            } catch {}
        }
    }

    // MARK: - Per-Clip Volume

    var hasBackgroundMusic: Bool { tape.musicMood != .none }

    var hasClipAudio: Bool {
        let clip = tape.clips[currentClipIndex]
        if clip.clipType == .video { return true }
        if clip.isLivePhoto {
            let playsAsVideo = clip.shouldPlayAsLiveVideo(tapeDefault: tape.livePhotosAsVideo)
            let isMuted = clip.shouldMuteLiveAudio(tapeDefault: tape.livePhotosMuted)
            return playsAsVideo && !isMuted
        }
        return false
    }

    private func updateVolumeForClip(at index: Int) {
        guard index >= 0, index < tape.clips.count else { return }
        let clip = tape.clips[index]
        clipVolume = clip.volume ?? 1.0
        clipMusicVolume = clip.musicVolume ?? Double(tape.musicVolume)

        player(for: activeSlot)?.volume = Float(clipVolume)
        backgroundMusic.setVolume(Float(clipMusicVolume))
    }

    func setClipVolume(_ vol: Double) {
        clipVolume = vol
        player(for: activeSlot)?.volume = Float(vol)
        persistCurrentClipVolumes()
    }

    func setClipMusicVolume(_ vol: Double) {
        clipMusicVolume = vol
        backgroundMusic.setVolume(Float(vol))
        persistCurrentClipVolumes()
    }

    private func persistCurrentClipVolumes() {
        guard currentClipIndex >= 0, currentClipIndex < tape.clips.count else { return }
        tape.clips[currentClipIndex].volume = clipVolume < 0.99 ? clipVolume : nil
        let tapeDefault = Double(tape.musicVolume)
        tape.clips[currentClipIndex].musicVolume = abs(clipMusicVolume - tapeDefault) > 0.01 ? clipMusicVolume : nil
        clipCache.removeValue(forKey: currentClipIndex)
    }

    // MARK: - Clip Event Handlers

    private func handleClipFinished() {
        guard !isTransitioning, !isInteractiveDragging else { return }
        if currentClipIndex < (timeline?.segments.count ?? 0) - 1 {
            Task { await jumpToClip(index: currentClipIndex + 1, autoplay: isPlaying) }
        } else {
            isFinished = true
            isPlaying = false
            backgroundMusic.syncPause()
            withAnimation(.easeInOut(duration: 0.2)) { showingControls = true }
        }
    }

    private func handleClipFailure(_ error: Error?) {
        recordSkip(showToast: true)
        Task { await skipFailedClip(from: currentClipIndex, autoplay: isPlaying) }
    }

    private func updatePlaybackMetrics(localTime: CMTime) {
        let localSeconds = CMTimeGetSeconds(localTime)
        clipTime = min(max(localSeconds.isFinite ? localSeconds : 0, 0), clipDuration)
        isPlaying = (activePlayer()?.rate ?? 0) > 0
    }

    private func updateClipTime(with localTime: CMTime) {
        let seconds = CMTimeGetSeconds(localTime)
        clipTime = min(max(seconds.isFinite ? seconds : 0, 0), clipDuration)
    }

    // MARK: - Skip Handling

    private func recordSkip(showToast: Bool) {
        skippedClipCount += 1
        guard showToast else { return }

        skipToastWorkItem?.cancel()
        withAnimation { showSkipToast = true }

        let workItem = DispatchWorkItem { [weak self] in
            withAnimation {
                self?.showSkipToast = false
                self?.skippedClipCount = 0
            }
        }
        skipToastWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: workItem)
    }

    private func skipFailedClip(from index: Int, autoplay: Bool) async {
        guard let timeline else { return }
        var nextIndex = index + 1
        while nextIndex < timeline.segments.count {
            do {
                try await loadClip(index: nextIndex, autoplay: autoplay, forceSlot: activeSlot)
                if autoplay {
                    activePlayer()?.play()
                    isPlaying = true
                } else {
                    isPlaying = false
                }
                startSequentialPreload(from: nextIndex + 1)
                return
            } catch {
                recordSkip(showToast: true)
                nextIndex += 1
            }
        }

        isFinished = true
        isPlaying = false
        withAnimation(.easeInOut(duration: 0.2)) { showingControls = true }
    }

    // MARK: - AirPlay Pre-Rendering

    private func observeAirPlayState(on player: AVPlayer) {
        airplayObservation?.invalidate()
        airplayObservation = player.observe(\.isExternalPlaybackActive, options: [.new]) { [weak self] _, change in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let active = change.newValue ?? false
                guard active != self.isAirPlayActive else { return }
                self.isAirPlayActive = active
                if active {
                    self.preRenderUpcomingImageClips()
                } else {
                    self.cleanupAllPreRenderedFiles()
                }
            }
        }
    }

    private func preRenderUpcomingImageClips() {
        guard let timeline else { return }
        let start = max(0, currentClipIndex)
        let end = min(start + Self.cacheCapacity, timeline.segments.count)
        for i in start..<end {
            guard i < tape.clips.count, tape.clips[i].clipType == .image else { continue }
            guard preRenderTasks.count < Self.maxConcurrentPreRenders else { break }
            preRenderImageClip(at: i)
        }
    }

    @discardableResult
    private func preRenderImageClip(at index: Int) -> Task<URL, Error>? {
        if let url = preRenderedImageURLs[index] { return Task { url } }
        if let existing = preRenderTasks[index] { return existing }
        guard index < tape.clips.count, tape.clips[index].clipType == .image else { return nil }
        guard preRenderTasks.count < Self.maxConcurrentPreRenders else { return nil }

        let clip = tape.clips[index]
        let capturedBuilder = builder
        let motionEffect = TapeCompositionBuilder.MotionEffect.from(style: clip.motionStyle)
        let scaleMode = clip.overrideScaleMode ?? capturedBuilder.imageConfiguration.baseScaleMode
        let task = Task<URL, Error> { [weak self] in
            let image = try await capturedBuilder.loadImage(for: clip)
            let duration = clip.duration > 0 ? clip.duration : 4.0
            let asset = try await capturedBuilder.createVideoAsset(
                from: image,
                clip: clip,
                duration: duration,
                motionEffect: motionEffect,
                scaleMode: scaleMode,
                includeBlurredBackground: true
            )
            guard let urlAsset = asset as? AVURLAsset else {
                throw TapeCompositionBuilder.BuilderError.imageEncodingFailed
            }
            let url = urlAsset.url
            await MainActor.run { [weak self] in
                self?.preRenderedImageURLs[index] = url
                self?.preRenderTasks.removeValue(forKey: index)
            }
            return url
        }
        preRenderTasks[index] = task
        return task
    }

    private func preRenderedPlayerItem(for index: Int) async -> AVPlayerItem? {
        guard isAirPlayActive,
              index < tape.clips.count,
              tape.clips[index].clipType == .image else { return nil }

        if let url = preRenderedImageURLs[index] {
            return AVPlayerItem(url: url)
        }
        if let task = preRenderTasks[index] ?? preRenderImageClip(at: index) {
            if let url = try? await task.value {
                return AVPlayerItem(url: url)
            }
        }
        return nil
    }

    private func cleanupPreRenderedFile(at index: Int) {
        if let url = preRenderedImageURLs.removeValue(forKey: index) {
            try? FileManager.default.removeItem(at: url)
        }
        preRenderTasks[index]?.cancel()
        preRenderTasks.removeValue(forKey: index)
    }

    private func cleanupAllPreRenderedFiles() {
        for (_, url) in preRenderedImageURLs {
            try? FileManager.default.removeItem(at: url)
        }
        preRenderedImageURLs.removeAll()
        preRenderTasks.values.forEach { $0.cancel() }
        preRenderTasks.removeAll()
    }

    // MARK: - Cache Management

    private func cacheComposition(_ composition: TapeCompositionBuilder.PlayerComposition, for index: Int) {
        clipCache[index] = composition
        cacheAccessOrder.removeAll { $0 == index }
        cacheAccessOrder.append(index)
        evictDistantCacheEntries()
    }

    private func touchCacheEntry(_ index: Int) {
        cacheAccessOrder.removeAll { $0 == index }
        cacheAccessOrder.append(index)
    }

    private func evictDistantCacheEntries() {
        while clipCache.count > Self.cacheCapacity, let oldest = cacheAccessOrder.first {
            cacheAccessOrder.removeFirst()
            clipCache.removeValue(forKey: oldest)
            cleanupPreRenderedFile(at: oldest)
        }
    }

    // MARK: - Helpers

    private func activePlayer() -> AVPlayer? { player(for: activeSlot) }
    private func inactivePlayer() -> AVPlayer? { player(for: inactiveSlot()) }
    private func inactiveSlot() -> PlayerSlot { activeSlot == .primary ? .secondary : .primary }

    private func setPlayer(_ player: AVPlayer, for slot: PlayerSlot) {
        switch slot {
        case .primary: primaryPlayer = player
        case .secondary: secondaryPlayer = player
        }
    }

    private func updateTimelineRenderSize(
        _ timeline: TapeCompositionBuilder.Timeline
    ) -> TapeCompositionBuilder.Timeline {
        guard viewportSize != .zero else { return timeline }
        let scale = UIScreen.main.scale
        let renderSize = CGSize(
            width: viewportSize.width * scale,
            height: viewportSize.height * scale
        )
        guard renderSize != timeline.renderSize else { return timeline }
        return TapeCompositionBuilder.Timeline(
            segments: timeline.segments,
            renderSize: renderSize,
            totalDuration: timeline.totalDuration,
            transitionSequence: timeline.transitionSequence
        )
    }

    private func makePlayerItem(
        from composition: TapeCompositionBuilder.PlayerComposition
    ) -> AVPlayerItem {
        let template = composition.playerItem
        let item = AVPlayerItem(asset: template.asset)
        if let videoComposition = template.videoComposition {
            item.videoComposition = (videoComposition.copy() as? AVVideoComposition) ?? videoComposition
        }
        if let audioMix = template.audioMix {
            item.audioMix = (audioMix.copy() as? AVAudioMix) ?? audioMix
        }
        return item
    }

    private func resetState() {
        isTornDown = false
        isFinished = false
        isPlaying = false
        isTransitioning = false
        transitionProgress = 0
        currentClipIndex = 0
        clipTime = 0
        clipDuration = 0
        loadError = nil
        clipCache.removeAll()
        cacheAccessOrder.removeAll()
        clipLoadTasks.values.forEach { $0.cancel() }
        clipLoadTasks.removeAll()
        slotClipIndex.removeAll()
        slotClipDuration.removeAll()
        slotVideoNaturalSize.removeAll()
        preloadTask?.cancel()
        preloadTask = nil
        preloadNextIndex = 0
        cleanupAllPreRenderedFiles()
    }

    private func startSequentialPreload(from startIndex: Int) {
        guard let timeline else { return }
        let maxIndex = timeline.segments.count - 1
        guard maxIndex >= 0 else { return }
        let clampedStart = max(0, min(startIndex, maxIndex))
        if clampedStart <= preloadNextIndex, preloadTask != nil { return }
        preloadTask?.cancel()
        preloadNextIndex = clampedStart
        let tapeTimeline = updateTimelineRenderSize(timeline)
        preloadTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            var index = self.preloadNextIndex
            while index <= maxIndex, !Task.isCancelled {
                self.preloadNextIndex = index
                if self.clipCache[index] == nil {
                    _ = try? await self.loadClipComposition(
                        index: index, timeline: tapeTimeline, allowTrim: false
                    )
                    await Task.yield()
                }
                if self.isAirPlayActive,
                   index < self.tape.clips.count,
                   self.tape.clips[index].clipType == .image {
                    self.preRenderImageClip(at: index)
                    await Task.yield()
                }
                index += 1
            }
        }
    }
}
