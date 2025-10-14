import SwiftUI
import AVFoundation
import AVKit
import Photos
import UIKit

// MARK: - Transition Scaffolding

private enum ClipMedia {
    case video(AVPlayer)
    case image(UIImage)
}

private struct ClipPlaybackBundle: Identifiable {
    let id = UUID()
    let index: Int
    let clip: Clip
    let media: ClipMedia
    let duration: Double
}

private struct ActiveTransition {
    let style: TransitionStyle
    let duration: Double
}

private enum TransitionRenderRole {
    case active
    case incoming
    case outgoing
}

// MARK: - Unified Tape Player View

struct TapePlayerView: View {
    @State private var player: AVPlayer?
    @State private var currentClipIndex: Int = 0
    @State private var currentBundle: ClipPlaybackBundle? = nil
    @State private var upcomingBundle: ClipPlaybackBundle? = nil
    @State private var incomingBundle: ClipPlaybackBundle? = nil
    @State private var outgoingBundle: ClipPlaybackBundle? = nil
    @State private var transitionWorkItem: DispatchWorkItem? = nil
    @State private var transitionTimer: Timer? = nil
    @State private var transitionStartDate: Date? = nil
    @State private var transitionContext: ActiveTransition = ActiveTransition(style: .none, duration: 0)
    @State private var transitionProgress: CGFloat = 1
    @State private var didLogTransitionTick: Bool = false
    @State private var isTransitioning: Bool = false
    @State private var crossfadeTriggerWorkItem: DispatchWorkItem? = nil
    @State private var crossfadeBoundaryObserver: Any? = nil
    @State private var crossfadeBoundaryPlayer: AVPlayer? = nil
    @State private var pendingClipIndex: Int? = nil
    @State private var isPlaying: Bool = false
    @State private var showingControls: Bool = false
    @State private var controlsTimer: Timer?
    @State private var totalDuration: Double = 0
    @State private var currentTime: Double = 0
    @State private var isFinished: Bool = false
    @State private var progressTimer: Timer?
    @State private var transitionSequence: [TransitionStyle] = []
    @State private var playerEndObserver: NSObjectProtocol? = nil
    @State private var currentImage: UIImage?
    @State private var imageAnimationProgress: CGFloat = 0
    @State private var imageAnimationDuration: Double = 0
    @State private var imageClipTotalDuration: Double = 0
    @State private var imageRemainingDuration: Double = 0
    @State private var imageClipStartTime: Date?
    @State private var imageClipWorkItem: DispatchWorkItem?
    
    let tape: Tape
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            videoPlayerView
                .ignoresSafeArea()

            if showingControls {
                VStack {
                    headerView
                        .padding(.top, 20)
                        .padding(.horizontal, 20)

                    Spacer()

                    controlsView
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: showingControls)
            }
        }
        .onAppear {
            Task { @MainActor in
                setupPlayer()
                setupControlsTimer()
            }
        }
        .onDisappear {
            // Stop all audio and clean up
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            player = nil
            resetImageState()
            controlsTimer?.invalidate()
            progressTimer?.invalidate()
            imageClipWorkItem?.cancel()
            detachPlayerEndObserver()
            cancelActiveTransition()
            cancelScheduledCrossfadeTrigger()
        }
        .onChange(of: tape.transition) { _ in
            configureTransitionSequence()
        }
        .onChange(of: tape.transitionDuration) { _ in
            configureTransitionSequence()
        }
        .onChange(of: transitionProgress) { progress in
            updateVolumes(progress: progress)
        }
        .onTapGesture {
            toggleControls()
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack(spacing: 16) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            Text("\(currentClipIndex + 1) of \(tape.clips.count)")
                .font(.headline)
                .foregroundColor(.white)
            
            AirPlayButton()
                .frame(width: 28, height: 28)
        }
        .padding()
    }
    
    // MARK: - Video Player View
    
    private var videoPlayerView: some View {
        GeometryReader { geometry in
            transitionCanvas(in: geometry)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
    }

    private func transitionCanvas(in geometry: GeometryProxy) -> some View {
        ZStack {
            if isTransitioning {
                if let outgoing = outgoingBundle {
                    render(bundle: outgoing, geometry: geometry, role: .outgoing)
                }
                if let incoming = incomingBundle {
                    render(bundle: incoming, geometry: geometry, role: .incoming)
                }
                if outgoingBundle == nil && incomingBundle == nil {
                    if let active = currentBundle {
                        render(bundle: active, geometry: geometry, role: .active)
                    }
                }
            } else if let active = currentBundle {
                render(bundle: active, geometry: geometry, role: .active)
            } else {
                placeholderCanvas
            }
        }
    }

    @ViewBuilder
    private func render(bundle: ClipPlaybackBundle, geometry: GeometryProxy, role: TransitionRenderRole) -> some View {
        let alpha = opacity(for: role)
        let offset = slideOffset(for: role, geometry: geometry)
        let rotation = rotationAngle(for: bundle.clip)
        let scaleMode = effectiveScaleMode(for: bundle.clip)

        switch bundle.media {
        case .video(let player):
            ZStack {
                videoPlaceholder(for: bundle.clip, scaleMode: scaleMode)
                PlayerSurface(player: player, scaleMode: scaleMode)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .id(bundle.id)
            .rotationEffect(rotation)
            .opacity(alpha)
            .offset(x: offset)
            .allowsHitTesting(false)
        case .image(let image):
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: scaleMode == .fill ? .fill : .fit)
                .scaleEffect(1 + 0.12 * CGFloat(imageAnimationProgress))
                .offset(x: -geometry.size.width * 0.04 * imageAnimationProgress,
                        y: -geometry.size.height * 0.05 * imageAnimationProgress)
                .animation(.linear(duration: imageAnimationDuration), value: imageAnimationProgress)
                .rotationEffect(rotation)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .opacity(alpha)
                .offset(x: offset)
                .id(bundle.id)
                .allowsHitTesting(false)
        }
    }

    private func opacity(for role: TransitionRenderRole) -> Double {
        switch transitionContext.style {
        case .crossfade:
            guard isTransitioning else { return 1.0 }
            let progress = Double(min(max(transitionProgress, 0), 1))
            switch role {
            case .incoming:
                return progress
            case .outgoing:
                return 1 - progress
            case .active:
                return 1
            }
        case .slideLR, .slideRL:
            return 1.0
        default:
            return 1.0
        }
    }

    private func slideOffset(for role: TransitionRenderRole, geometry: GeometryProxy) -> CGFloat {
        guard isTransitioning else { return 0 }
        let width = geometry.size.width
        let progress = CGFloat(min(max(transitionProgress, 0), 1))
        switch transitionContext.style {
        case .slideLR:
            switch role {
            case .outgoing:
                return -progress * width
            case .incoming:
                return (1 - progress) * width
            case .active:
                return 0
            }
        case .slideRL:
            switch role {
            case .outgoing:
                return progress * width
            case .incoming:
                return -(1 - progress) * width
            case .active:
                return 0
            }
        default:
            return 0
        }
    }

    private func effectiveScaleMode(for clip: Clip) -> ScaleMode {
        clip.overrideScaleMode ?? tape.scaleMode
    }

    private func rotationAngle(for clip: Clip) -> Angle {
        let turns = ((clip.rotateQuarterTurns % 4) + 4) % 4
        return .degrees(Double(turns) * 90)
    }

    @ViewBuilder
    private func videoPlaceholder(for clip: Clip, scaleMode: ScaleMode) -> some View {
        if let thumbnail = clip.thumbnailImage {
            Image(uiImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: scaleMode == .fill ? .fill : .fit)
                .clipped()
        } else {
            Color.clear
        }
    }

    private var placeholderCanvas: some View {
        VStack {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
            Text("Loading...")
                .foregroundColor(.white)
                .padding(.top)
        }
    }
    
    // MARK: - Controls View
    
    private var controlsView: some View {
        VStack(spacing: 20) {
            if isFinished {
                // Finished state - show play again button
                finishedView
            } else {
                // Global progress bar
                globalProgressView
                
                // Global control buttons
                globalControlButtons
            }
        }
        .padding()
    }
    
    // MARK: - Finished View
    
    private var finishedView: some View {
        VStack(spacing: 20) {
            Text("Playback Complete")
                .font(.title2)
                .foregroundColor(.white)
            
            Button(action: playAgain) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Play Again")
                }
                .font(.title2)
                .foregroundColor(.black)
                .padding()
                .background(Color.white)
                .cornerRadius(10)
            }
        }
    }
    
    // MARK: - Global Progress View
    
    private var globalProgressView: some View {
        VStack(spacing: 8) {
            // Interactive progress bar
            GeometryReader { geometry in
                let progressValue = totalDuration > 0 ? min(max(currentTime / totalDuration, 0), 1) : 0
                ZStack(alignment: .leading) {
                    // Background track
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 6)
                    
                    // Progress track
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: geometry.size.width * progressValue, height: 6)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let progress = max(0, min(1, value.location.x / geometry.size.width))
                            let targetTime = progress * totalDuration
                            currentTime = targetTime
                        }
                        .onEnded { value in
                            let progress = max(0, min(1, value.location.x / geometry.size.width))
                            let _ = progress * totalDuration
                            scrubToPosition(value.location.x, in: geometry.size.width)
                        }
                )
            }
            .frame(height: 6)
            
            // Time labels
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
    
    // MARK: - Global Control Buttons
    
    private var globalControlButtons: some View {
        HStack(spacing: 40) {
            // Previous button
            Button(action: previousClip) {
                Image(systemName: "backward.fill")
                    .font(.title)
                    .foregroundColor(.white)
            }
            .disabled(currentClipIndex == 0)
            
            // Play/Pause button
            Button(action: togglePlayPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.largeTitle)
                    .foregroundColor(.white)
            }
            
            // Next button
            Button(action: nextClip) {
                Image(systemName: "forward.fill")
                    .font(.title)
                    .foregroundColor(.white)
            }
            .disabled(currentClipIndex >= tape.clips.count - 1)
        }
    }
    
    // MARK: - Progress View
    
    private var progressView: some View {
        HStack {
            Text("\(currentClipIndex + 1) of \(tape.clips.count)")
                .foregroundColor(.white)
            
            Spacer()
            
            if let clip = currentClip {
                Text(formatTime(effectiveDuration(for: clip)))
                    .foregroundColor(.white)
            }
        }
        .font(.caption)
    }
    
    // MARK: - Current Clip
    
    private var currentClip: Clip? {
        guard currentClipIndex < tape.clips.count else { return nil }
        return tape.clips[currentClipIndex]
    }

    private func effectiveDuration(for clip: Clip) -> Double {
        if clip.clipType == .image {
            let base = clip.duration > 0 ? clip.duration : 4.0
            return max(base, 0.1)
        }
        return max(clip.duration, 0)
    }
    
    // MARK: - Setup
    
    private func setupPlayer() {
        guard !tape.clips.isEmpty else { return }
        configureTransitionSequence()
        currentClipIndex = 0
        transitionContext = ActiveTransition(style: .none, duration: 0)
        isFinished = false
        calculateTotalDuration()
        loadCurrentClip()
        startProgressTracking()
        updateCurrentTime()
    }
    
    private func calculateTotalDuration() {
        totalDuration = tape.clips.reduce(0) { total, clip in
            total + effectiveDuration(for: clip)
        }
    }

    private func configureTransitionSequence() {
        let boundaries = max(0, tape.clips.count - 1)
        switch tape.transition {
        case .randomise:
            transitionSequence = generateRandomTransitionSequence(boundaries: boundaries)
        case .none:
            transitionSequence = Array(repeating: .none, count: boundaries)
        case .crossfade:
            transitionSequence = Array(repeating: .crossfade, count: boundaries)
        case .slideLR:
            transitionSequence = Array(repeating: .slideLR, count: boundaries)
        case .slideRL:
            transitionSequence = Array(repeating: .slideRL, count: boundaries)
        }
    }

    private func generateRandomTransitionSequence(boundaries: Int) -> [TransitionStyle] {
        guard boundaries > 0 else { return [] }
        var generator = TapePlayerSeededGenerator(seed: UInt64(bitPattern: Int64(tape.id.hashValue)))
        let pool: [TransitionStyle] = [.none, .crossfade, .slideLR, .slideRL]
        return (0..<boundaries).map { _ in pool.randomElement(using: &generator)! }
    }

    
    private func loadCurrentClip() {
        prepareAndPlayBundle(at: currentClipIndex)
    }

    private func prepareAndPlayBundle(at index: Int) {
        guard tape.clips.indices.contains(index) else { return }
        let clip = tape.clips[index]
        let duration = effectiveDuration(for: clip)
        let previousBundle = currentBundle
        cancelScheduledCrossfadeTrigger()

        let descriptor = transitionDescriptor(incoming: index, previous: previousBundle)
        transitionContext = descriptor
        transitionStartDate = nil
        transitionProgress = descriptor.style == .none ? 1 : 0
        print("[Transition] context updated style=\(descriptor.style) progress=\(transitionProgress) incoming=\(incomingBundle?.index ?? -1) outgoing=\(outgoingBundle?.index ?? -1)")

        if let cached = upcomingBundle, cached.index == index {
            upcomingBundle = nil
            applyTransition(from: previousBundle, to: cached, descriptor: descriptor, at: index)
            return
        }

        currentTime = calculateElapsedTime(for: index)

        if descriptor.style != .crossfade || descriptor.duration <= 0 || previousBundle == nil {
            cancelActiveTransition()
            resetImageState()
            player?.pause()
        } else {
            cancelActiveTransition()
        }

        Task { @MainActor in
            let bundle = await makeBundle(for: clip, index: index, duration: duration)
            applyTransition(from: previousBundle, to: bundle, descriptor: descriptor, at: index)
        }
    }


    private func prefetchUpcoming(after index: Int) {
        let nextIndex = index + 1
        guard tape.clips.indices.contains(nextIndex) else {
            upcomingBundle = nil
            return
        }
        let nextClip = tape.clips[nextIndex]
        let nextDuration = effectiveDuration(for: nextClip)
        Task { @MainActor in
            upcomingBundle = await makeBundle(for: nextClip, index: nextIndex, duration: nextDuration)
        }
    }


    private func startImageClip(with image: UIImage, clip: Clip) {
        resetImageState()
        currentImage = image
        player = nil
        isPlaying = true

        let duration = effectiveDuration(for: clip)
        imageClipTotalDuration = duration
        imageRemainingDuration = duration
        imageClipStartTime = Date()
        imageAnimationProgress = 0
        imageAnimationDuration = duration

        withAnimation(.linear(duration: imageAnimationDuration)) {
            imageAnimationProgress = 1
        }

        scheduleImageClipCompletion(after: duration)
        updateCurrentTime()
    }

    private func scheduleImageClipCompletion(after duration: Double) {
        imageClipWorkItem?.cancel()
        guard duration > 0 else {
            onImageClipEnded()
            return
        }
        let workItem = DispatchWorkItem {
            onImageClipEnded()
        }
        imageClipWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func pauseImageClip() {
        guard let start = imageClipStartTime else { return }
        let elapsed = Date().timeIntervalSince(start)
        imageClipWorkItem?.cancel()
        imageClipWorkItem = nil
        imageRemainingDuration = max(0, imageClipTotalDuration - elapsed)
        imageClipStartTime = nil
        imageAnimationDuration = 0
        let progress = imageClipTotalDuration > 0 ? min(max(elapsed / imageClipTotalDuration, 0), 1) : 1
        withAnimation(.linear(duration: 0)) {
            imageAnimationProgress = CGFloat(progress)
        }
        isPlaying = false
        cancelScheduledCrossfadeTrigger()
    }

    private func resumeImageClip() {
        guard imageRemainingDuration > 0 else {
            onImageClipEnded()
            return
        }
        imageClipStartTime = Date()
        imageAnimationDuration = imageRemainingDuration
        withAnimation(.linear(duration: imageAnimationDuration)) {
            imageAnimationProgress = 1
        }
        scheduleImageClipCompletion(after: imageRemainingDuration)
        isPlaying = true
        updateCurrentTime()
        if let bundle = currentBundle {
            scheduleCrossfadeTrigger(for: bundle)
        }
    }

    private func onImageClipEnded() {
        imageClipWorkItem?.cancel()
        imageClipWorkItem = nil
        imageClipStartTime = nil
        imageRemainingDuration = 0
        imageClipTotalDuration = 0
        imageAnimationDuration = 0
        imageAnimationProgress = 0
        currentImage = nil
        isPlaying = false
        onVideoEnded()
    }

    private func resetImageState() {
        imageClipWorkItem?.cancel()
        imageClipWorkItem = nil
        imageClipStartTime = nil
        imageClipTotalDuration = 0
        imageRemainingDuration = 0
        imageAnimationDuration = 0
        imageAnimationProgress = 0
        currentImage = nil
        isPlaying = false
        cancelScheduledCrossfadeTrigger()
    }

    private func makeBundle(for clip: Clip, index: Int, duration: Double) async -> ClipPlaybackBundle {
        switch clip.clipType {
        case .image:
            if let image = await resolveImage(for: clip) {
                return ClipPlaybackBundle(index: index, clip: clip, media: .image(image), duration: duration)
            }
        case .video:
            if let player = await resolvePlayer(for: clip) {
                return ClipPlaybackBundle(index: index, clip: clip, media: .video(player), duration: duration)
            }
        }
        return ClipPlaybackBundle(index: index, clip: clip, media: .image(UIImage()), duration: duration)
    }


    private func transitionDescriptor(incoming index: Int, previous: ClipPlaybackBundle?) -> ActiveTransition {
        guard let previous = previous else { return ActiveTransition(style: .none, duration: 0) }
        guard index == previous.index + 1, previous.index >= 0 else {
            return ActiveTransition(style: .none, duration: 0)
        }
        guard transitionSequence.indices.contains(previous.index) else {
            return ActiveTransition(style: .none, duration: 0)
        }
        let style = transitionSequence[previous.index]
        let duration = style == .none ? 0 : max(0.1, min(tape.transitionDuration, 1.0))
        return ActiveTransition(style: style, duration: duration)
    }

    private func applyTransition(from previous: ClipPlaybackBundle?, to bundle: ClipPlaybackBundle, descriptor: ActiveTransition, at index: Int) {
        print("[Transition] apply style=\(descriptor.style) duration=\(descriptor.duration) index=\(index) previous=\(previous?.index ?? -1)")
        if isTransitioning {
            cancelActiveTransition()
        }
        switch descriptor.style {
        case .crossfade where descriptor.duration > 0 && previous != nil:
            incomingBundle = bundle
            isTransitioning = true
            transitionProgress = 0
            startIncomingPlayback(bundle)
            beginTransition(duration: descriptor.duration)
        case .slideLR, .slideRL where descriptor.duration > 0 && previous != nil:
            incomingBundle = bundle
            isTransitioning = true
            transitionProgress = 0
            startIncomingPlayback(bundle)
            beginTransition(duration: descriptor.duration)
        default:
            incomingBundle = nil
            activateBundle(bundle, restart: true)
        }
        prefetchUpcoming(after: index)
    }

    private func startIncomingPlayback(_ bundle: ClipPlaybackBundle) {
        print("[Transition] startIncoming index=\(bundle.index) clip=\(bundle.clip.id)")
        incomingBundle = bundle
        outgoingBundle = currentBundle
        play(bundle: bundle, asIncoming: true)
        isPlaying = true
        updateVolumes(progress: 0)
    }

    private func activateBundle(_ bundle: ClipPlaybackBundle, restart: Bool) {
        outgoingBundle = nil
        incomingBundle = nil
        currentBundle = bundle
        isTransitioning = false
        transitionProgress = 1

        if restart {
            play(bundle: bundle, asIncoming: false)
            isPlaying = true
        } else if case .video(let player) = bundle.media {
            player.volume = 1
            if isPlaying {
                player.play()
            }
        }
        scheduleCrossfadeTrigger(for: bundle)
    }

    private func beginTransition(duration: Double) {
        transitionTimer?.invalidate()
        transitionStartDate = Date()
        didLogTransitionTick = false
        print("[Transition] begin duration=\(duration) incoming=\(incomingBundle?.index ?? -1) outgoing=\(outgoingBundle?.index ?? -1)")
        transitionTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { timer in
            guard let start = transitionStartDate else {
                timer.invalidate()
                transitionTimer = nil
                return
            }
            let elapsed = Date().timeIntervalSince(start)
            let progress = min(max(elapsed / duration, 0), 1)
            transitionProgress = CGFloat(progress)
            if !didLogTransitionTick {
                didLogTransitionTick = true
                print("[Transition] first tick progress=\(progress) incoming=\(incomingBundle?.index ?? -1) outgoing=\(outgoingBundle?.index ?? -1)")
            }
            if progress >= 1 {
                timer.invalidate()
                transitionTimer = nil
            }
        }
        RunLoop.main.add(transitionTimer!, forMode: .common)
        transitionWorkItem?.cancel()
        let workItem = DispatchWorkItem { finishTransition() }
        transitionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func finishTransition() {
        print("[Transition] finish incoming=\(incomingBundle?.index ?? -1) outgoing=\(outgoingBundle?.index ?? -1) progress=\(transitionProgress)")
        transitionWorkItem?.cancel()
        transitionWorkItem = nil
        transitionTimer?.invalidate()
        transitionTimer = nil
        transitionStartDate = nil
        let previousActivePlayer = player
        if let incoming = incomingBundle {
            currentBundle = incoming
        }
        if let outgoing = outgoingBundle, case .video(let outgoingPlayer) = outgoing.media,
           previousActivePlayer === outgoingPlayer {
            detachPlayerEndObserver()
        }
        if let active = currentBundle {
            switch active.media {
            case .video(let incomingPlayer):
                currentImage = nil
                player = incomingPlayer
                attachPlayerEndObserver(to: incomingPlayer)
            case .image(let image):
                currentImage = image
                player = nil
                detachPlayerEndObserver()
            }
        } else {
            player = nil
            detachPlayerEndObserver()
            currentImage = nil
        }
        transitionProgress = 1
        updateVolumes(progress: 1)
        if let active = currentBundle, case .video(let player) = active.media {
            player.volume = 1
            if isPlaying {
                player.play()
            } else {
                player.pause()
            }
        }
        if let outgoing = outgoingBundle, case .video(let player) = outgoing.media {
            player.pause()
            player.volume = 0
        }
        incomingBundle = nil
        outgoingBundle = nil
        isTransitioning = false
        if let pending = pendingClipIndex {
            currentClipIndex = pending
        }
        pendingClipIndex = nil
        if let active = currentBundle {
            scheduleCrossfadeTrigger(for: active)
        }
    }

    private func cancelActiveTransition() {
        print("[Transition] cancel incoming=\(incomingBundle?.index ?? -1) outgoing=\(outgoingBundle?.index ?? -1) progress=\(transitionProgress)")
        cancelScheduledCrossfadeTrigger()
        transitionWorkItem?.cancel()
        transitionWorkItem = nil
        transitionTimer?.invalidate()
        transitionTimer = nil
        transitionStartDate = nil
        if let incoming = incomingBundle, case .video(let player) = incoming.media {
            player.pause()
            player.seek(to: .zero)
            player.volume = 1
        }
        if let outgoing = outgoingBundle, case .video(let player) = outgoing.media {
            player.pause()
            player.volume = 0
        }
        incomingBundle = nil
        outgoingBundle = nil
        isTransitioning = false
        transitionProgress = 1
        pendingClipIndex = nil
    }

    private func updateVolumes(progress: CGFloat) {
        guard isTransitioning else { return }
        let clamped = Float(min(max(progress, 0), 1))
        switch transitionContext.style {
        case .crossfade, .slideLR, .slideRL:
            if let incoming = incomingBundle, case .video(let player) = incoming.media {
                player.volume = clamped
            } else if let incoming = currentBundle, case .video(let player) = incoming.media {
                player.volume = clamped
            }
            if let outgoing = outgoingBundle, case .video(let player) = outgoing.media {
                player.volume = 1 - clamped
            }
        default:
            break
        }
    }

    private func detachPlayerEndObserver() {
        if let observer = playerEndObserver {
            NotificationCenter.default.removeObserver(observer)
            playerEndObserver = nil
        }
    }

    private func attachPlayerEndObserver(to player: AVPlayer) {
        detachPlayerEndObserver()
        if let item = player.currentItem {
            playerEndObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { _ in
                self.onVideoEnded()
            }
        }
    }

    private func cancelScheduledCrossfadeTrigger() {
        crossfadeTriggerWorkItem?.cancel()
        crossfadeTriggerWorkItem = nil
        if let observer = crossfadeBoundaryObserver, let boundaryPlayer = crossfadeBoundaryPlayer {
            boundaryPlayer.removeTimeObserver(observer)
        }
        crossfadeBoundaryObserver = nil
        crossfadeBoundaryPlayer = nil
    }

    private func effectiveCrossfade(from outgoing: ClipPlaybackBundle, to nextIndex: Int) -> (descriptor: ActiveTransition, duration: Double)? {
        guard tape.clips.indices.contains(nextIndex) else { return nil }
        let descriptor = transitionDescriptor(incoming: nextIndex, previous: outgoing)
        guard descriptor.style == .crossfade else { return nil }

        let incomingClip = tape.clips[nextIndex]
        let incomingDuration = effectiveDuration(for: incomingClip)
        let overlapLimit = min(outgoing.duration, incomingDuration)
        guard overlapLimit > 0 else { return nil }

        var duration = min(descriptor.duration, overlapLimit)
        if outgoing.duration < 6 || incomingDuration < 6 {
            duration = min(0.5, overlapLimit)
        }
        duration = max(duration, 0)
        guard duration > 0 else { return nil }

        let adjustedDescriptor = ActiveTransition(style: .crossfade, duration: duration)
        return (adjustedDescriptor, duration)
    }

    private func scheduleCrossfadeTrigger(for bundle: ClipPlaybackBundle) {
        cancelScheduledCrossfadeTrigger()
        let nextIndex = bundle.index + 1
        guard let (descriptor, duration) = effectiveCrossfade(from: bundle, to: nextIndex) else { return }
        prefetchUpcoming(after: bundle.index)

        let leadTime = max(bundle.duration - duration, 0)
        if case .video(let player) = bundle.media {
            crossfadeBoundaryPlayer = player
            let currentSeconds = max(CMTimeGetSeconds(player.currentTime()), 0)
            if leadTime <= currentSeconds {
                startScheduledCrossfade(to: nextIndex, descriptor: descriptor, duration: duration)
                return
            }
            let times = [NSValue(time: CMTime(seconds: leadTime, preferredTimescale: 600))]
            crossfadeBoundaryObserver = player.addBoundaryTimeObserver(forTimes: times, queue: .main) {
                self.startScheduledCrossfade(to: nextIndex, descriptor: descriptor, duration: duration)
            }
        } else {
            let elapsed: Double
            if let start = imageClipStartTime {
                elapsed = Date().timeIntervalSince(start)
            } else {
                elapsed = bundle.duration - imageRemainingDuration
            }
            let delay = max(leadTime - elapsed, 0)
            if delay <= 0 {
                startScheduledCrossfade(to: nextIndex, descriptor: descriptor, duration: duration)
                return
            }
            let workItem = DispatchWorkItem {
                self.startScheduledCrossfade(to: nextIndex, descriptor: descriptor, duration: duration)
            }
            crossfadeTriggerWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    private func startScheduledCrossfade(to index: Int, descriptor: ActiveTransition, duration: Double) {
        cancelScheduledCrossfadeTrigger()
        guard !isTransitioning else { return }
        guard let current = currentBundle else { return }
        guard index == current.index + 1 else { return }
        guard tape.clips.indices.contains(index) else { return }

        Task { @MainActor in
            await initiateCrossfade(to: index, descriptor: descriptor, from: current)
        }
    }

    @MainActor
    private func initiateCrossfade(to index: Int, descriptor: ActiveTransition, from outgoing: ClipPlaybackBundle) async {
        guard tape.clips.indices.contains(index) else { return }
        let clip = tape.clips[index]
        let duration = effectiveDuration(for: clip)
        let bundle = await incomingBundle(for: clip, index: index, duration: duration)
        pendingClipIndex = index
        transitionContext = descriptor
        applyTransition(from: outgoing, to: bundle, descriptor: descriptor, at: index)
    }

    @MainActor
    private func incomingBundle(for clip: Clip, index: Int, duration: Double) async -> ClipPlaybackBundle {
        if let cached = upcomingBundle, cached.index == index {
            upcomingBundle = nil
            return cached
        }
        return await makeBundle(for: clip, index: index, duration: duration)
    }

    private func play(bundle: ClipPlaybackBundle, asIncoming: Bool) {
        switch bundle.media {
        case .video(let activePlayer):
            if !asIncoming {
                currentImage = nil
                player?.pause()
            }
            player = activePlayer
            attachPlayerEndObserver(to: activePlayer)
            activePlayer.seek(to: .zero)
            activePlayer.volume = asIncoming ? 0 : 1
            activePlayer.play()
            isPlaying = true
        case .image(let image):
            detachPlayerEndObserver()
            if !asIncoming {
                player?.replaceCurrentItem(with: nil)
                currentImage = image
                startImageClip(with: image, clip: bundle.clip)
            } else {
                startImageClip(with: image, clip: bundle.clip)
            }
        }
    }

    private func resolvePlayer(for clip: Clip) async -> AVPlayer? {
        if let localURL = clip.localURL {
            let item = AVPlayerItem(url: localURL)
            let player = AVPlayer(playerItem: item)
            player.actionAtItemEnd = .pause
            return player
        }
        if let assetLocalId = clip.assetLocalId {
            if let asset = await fetchAVAssetAsync(localIdentifier: assetLocalId) {
                let item = AVPlayerItem(asset: asset)
                let player = AVPlayer(playerItem: item)
                player.actionAtItemEnd = .pause
                return player
            }
        }
        return nil
    }

    private func resolveImage(for clip: Clip) async -> UIImage? {
        if let data = clip.imageData, let image = UIImage(data: data) {
            return image
        }
        if let localURL = clip.localURL, let image = UIImage(contentsOfFile: localURL.path) {
            return image
        }
        if let assetLocalId = clip.assetLocalId {
            return await fetchImageAsync(localIdentifier: assetLocalId)
        }
        if let thumbData = clip.thumbnail, let image = UIImage(data: thumbData) {
            return image
        }
        return nil
    }

    private func fetchAVAssetAsync(localIdentifier: String) async -> AVAsset? {
        await withCheckedContinuation { continuation in
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
            guard let phAsset = fetchResult.firstObject else {
                continuation.resume(returning: nil)
                return
            }
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { asset, _, _ in
                continuation.resume(returning: asset)
            }
        }
    }

    private func fetchImageAsync(localIdentifier: String) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
            guard let phAsset = fetchResult.firstObject else {
                continuation.resume(returning: nil)
                return
            }
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            PHImageManager.default().requestImage(for: phAsset,
                                                   targetSize: PHImageManagerMaximumSize,
                                                   contentMode: .aspectFill,
                                                   options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    private func onVideoEnded() {
        detachPlayerEndObserver()
        cancelScheduledCrossfadeTrigger()
        resetImageState()
        player?.pause()
        player = nil

        if currentClipIndex < tape.clips.count - 1 {
            currentClipIndex += 1
            loadCurrentClip()
        } else {
            isPlaying = false
            isFinished = true
        }
    }

    private func playAgain() {
        cancelActiveTransition()
        resetImageState()
        player?.pause()
        currentClipIndex = 0
        currentTime = 0
        isFinished = false
        loadCurrentClip()
    }


    // MARK: - Controls
    
    private func togglePlayPause() {
        if let player = player {
            if isPlaying {
                player.pause()
                isPlaying = false
            } else {
                player.play()
                isPlaying = true
            }
        } else if currentImage != nil {
            if isPlaying {
                pauseImageClip()
            } else {
                resumeImageClip()
                setupControlsTimer()
            }
        }
    }
    
    private func nextClip() {
        guard currentClipIndex < tape.clips.count - 1 else { return }
        cancelActiveTransition()
        currentClipIndex += 1
        loadCurrentClip()
    }
    
    private func previousClip() {
        guard currentClipIndex > 0 else { return }
        cancelActiveTransition()
        currentClipIndex -= 1
        loadCurrentClip()
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
    
    // MARK: - Helper Functions
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - Progress Tracking
    
    private func startProgressTracking() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            updateCurrentTime()
        }
    }
    
    private func updateCurrentTime() {
        if let player = player, let currentItem = player.currentItem {
            let currentTimeInSeconds = CMTimeGetSeconds(currentItem.currentTime())
            let totalElapsedTime = calculateElapsedTime(for: currentClipIndex) + max(currentTimeInSeconds, 0)
            currentTime = min(totalElapsedTime, totalDuration)

            if totalElapsedTime >= totalDuration, !isFinished {
                currentTime = totalDuration
                isFinished = true
                player.pause()
                isPlaying = false
            }
        } else if currentImage != nil {
            let elapsed: Double
            if let start = imageClipStartTime {
                elapsed = Date().timeIntervalSince(start)
            } else {
                elapsed = imageClipTotalDuration - imageRemainingDuration
            }
            let clampedElapsed = min(max(elapsed, 0), imageClipTotalDuration)
            currentTime = min(calculateElapsedTime(for: currentClipIndex) + clampedElapsed, totalDuration)
        } else {
            currentTime = min(currentTime, totalDuration)
        }
    }

    private func calculateElapsedTime(for index: Int) -> Double {
        guard index > 0 else { return 0 }
        return tape.clips.prefix(index).reduce(0) { $0 + effectiveDuration(for: $1) }
    }

    private func scrubToPosition(_ x: CGFloat, in width: CGFloat) {
        guard totalDuration > 0 else { return }
        let progress = max(0, min(1, x / width))
        let targetTime = progress * totalDuration

        var accumulatedTime: Double = 0
        var targetClipIndex = 0

        for (index, clip) in tape.clips.enumerated() {
            let clipDuration = effectiveDuration(for: clip)
            if targetTime <= accumulatedTime + clipDuration {
                targetClipIndex = index
                break
            }
            accumulatedTime += clipDuration
        }

        if targetClipIndex != currentClipIndex {
            cancelActiveTransition()
            currentClipIndex = targetClipIndex
            loadCurrentClip()
        }

        let targetClip = tape.clips[currentClipIndex]
        let clipDuration = effectiveDuration(for: targetClip)
        let timeInCurrentClip = min(max(targetTime - accumulatedTime, 0), clipDuration)

        if let player = player {
            let targetCMTime = CMTime(seconds: timeInCurrentClip, preferredTimescale: 600)
            player.seek(to: targetCMTime)
        } else if currentImage != nil {
            imageClipStartTime = Date().addingTimeInterval(-timeInCurrentClip)
            imageRemainingDuration = max(clipDuration - timeInCurrentClip, 0)
            imageAnimationDuration = imageRemainingDuration
            let progress = clipDuration > 0 ? min(max(timeInCurrentClip / clipDuration, 0), 1) : 1
            withAnimation(.linear(duration: 0)) {
                imageAnimationProgress = CGFloat(progress)
            }
            if isPlaying {
                scheduleImageClipCompletion(after: imageRemainingDuration)
                withAnimation(.linear(duration: imageAnimationDuration)) {
                    imageAnimationProgress = 1
                }
            }
        }

        currentTime = min(targetTime, totalDuration)
    }

}

private struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    let scaleMode: ScaleMode

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.configure(with: player, scaleMode: scaleMode)
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.configure(with: player, scaleMode: scaleMode)
    }

    final class PlayerContainerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        func configure(with player: AVPlayer, scaleMode: ScaleMode) {
            if playerLayer.player !== player {
                playerLayer.player = player
            }
            playerLayer.videoGravity = (scaleMode == .fill) ? .resizeAspectFill : .resizeAspect
            playerLayer.masksToBounds = true
            playerLayer.backgroundColor = UIColor.black.cgColor
        }
    }
}

#Preview {
    TapePlayerView(
        tape: Tape.sampleTapes[0],
        onDismiss: {}
    )
}

private struct TapePlayerSeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 12345 : seed
    }

    mutating func next() -> UInt64 {
        state = (state &* 1103515245 &+ 12345) & 0x7fffffff
        return state
    }
}
