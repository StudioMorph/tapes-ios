import SwiftUI
import AVFoundation

struct ClipTrimView: View {
    @Binding var clip: Clip
    let onDismiss: () -> Void
    let onSave: (Clip) -> Void

    @State private var player: AVPlayer?
    @State private var asset: AVAsset?
    @State private var assetDuration: TimeInterval = 0
    @State private var trimStart: TimeInterval
    @State private var trimEnd: TimeInterval
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var timeObserver: Any?
    @State private var isDragging = false

    private var totalDuration: TimeInterval {
        assetDuration > 0 ? assetDuration : clip.duration
    }

    private var trimmedDuration: TimeInterval {
        max(0, totalDuration - trimStart - trimEnd)
    }

    private var trimEndTime: TimeInterval {
        totalDuration - trimEnd
    }

    init(clip: Binding<Clip>, onDismiss: @escaping () -> Void, onSave: @escaping (Clip) -> Void) {
        self._clip = clip
        self.onDismiss = onDismiss
        self.onSave = onSave
        self._trimStart = State(initialValue: clip.wrappedValue.trimStart)
        self._trimEnd = State(initialValue: clip.wrappedValue.trimEnd)
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    videoPreview
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    timeDisplay
                        .padding(.top, Tokens.Spacing.s)
                        .opacity(isDragging ? 0 : 1)

                    HStack(spacing: Tokens.Spacing.s) {
                        playButton

                        if asset != nil, totalDuration > 0 {
                            FrameTimelineView(
                                asset: asset!,
                                totalDuration: totalDuration,
                                trimStart: $trimStart,
                                trimEnd: $trimEnd,
                                currentTime: $currentTime,
                                isDragging: $isDragging,
                                onSeek: { seekTo($0) },
                                onDragStarted: { pauseIfPlaying() },
                                onHandleDragEnded: { seekTo(trimStart) }
                            )
                            .frame(height: 56)
                        } else {
                            loadingPlaceholder
                        }
                    }
                    .padding(.horizontal, Tokens.Spacing.m)
                    .padding(.bottom, Tokens.Spacing.xl)
                    .padding(.top, Tokens.Spacing.s)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { onDismiss() }
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .principal) {
                    Text("Trim Clip")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { save() }
                        .fontWeight(.semibold)
                        .foregroundColor(.yellow)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .task { await loadAsset() }
        .onDisappear { cleanup() }
    }

    // MARK: - Subviews

    private var videoPreview: some View {
        Group {
            if let player {
                TrimPlayerLayerView(player: player)
                    .clipped()
            } else {
                Color.black
                    .overlay {
                        if loadError != nil {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                        } else {
                            ProgressView().tint(.white)
                        }
                    }
            }
        }
    }

    private var timeDisplay: some View {
        Text(formatTrimTime(currentTime))
            .font(.system(size: 14, weight: .medium))
            .monospacedDigit()
            .foregroundColor(.white.opacity(0.7))
    }

    private var playButton: some View {
        Button { togglePlayback() } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(.white)
                .frame(width: Tokens.HitTarget.recommended, height: 56)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var loadingPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.white.opacity(0.1))
            .frame(height: 56)
            .overlay {
                if let loadError {
                    Text(loadError)
                        .font(.caption)
                        .foregroundColor(.red)
                } else {
                    ProgressView().tint(.white)
                }
            }
    }

    // MARK: - Asset Loading

    private func loadAsset() async {
        guard clip.clipType == .video else { return }

        do {
            let builder = TapeCompositionBuilder()
            let avAsset = try await builder.resolveVideoAsset(for: clip)

            let duration = try await avAsset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)

            let item = AVPlayerItem(asset: avAsset)
            let newPlayer = AVPlayer(playerItem: item)

            await MainActor.run {
                self.asset = avAsset
                self.assetDuration = durationSeconds.isNaN ? clip.duration : durationSeconds
                self.player = newPlayer
                self.isLoading = false
                self.currentTime = trimStart
                seekTo(trimStart)
                addTimeObserver()
            }
        } catch {
            TapesLog.player.error("ClipTrimView: failed to load asset: \(error.localizedDescription)")
            await MainActor.run { loadError = "Failed to load video" }
        }
    }

    // MARK: - Playback

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if currentTime >= trimEndTime {
                seekTo(trimStart)
            }
            player.play()
            isPlaying = true
        }
    }

    private func pauseIfPlaying() {
        guard isPlaying else { return }
        player?.pause()
        isPlaying = false
    }

    private func seekTo(_ time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
    }

    private func addTimeObserver() {
        guard let player else { return }
        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { cmTime in
            let t = cmTime.seconds
            if t.isNaN || t.isInfinite { return }

            currentTime = t
            if t >= trimEndTime && isPlaying {
                player.pause()
                isPlaying = false
                seekTo(trimStart)
            }
        }
    }

    private func cleanup() {
        if let observer = timeObserver, let player {
            player.removeTimeObserver(observer)
        }
        player?.pause()
        timeObserver = nil
    }

    // MARK: - Save

    private func save() {
        var updated = clip
        updated.setTrim(start: trimStart, end: trimEnd)
        onSave(updated)
        onDismiss()
    }
}

// MARK: - Time Formatting

private func formatTrimTime(_ seconds: TimeInterval) -> String {
    let clamped = max(0, seconds)
    let mins = Int(clamped) / 60
    let secs = Int(clamped) % 60
    let frac = Int((clamped.truncatingRemainder(dividingBy: 1)) * 100)
    return String(format: "%02d:%02d.%02d", mins, secs, frac)
}

// MARK: - Player Layer

private final class TrimPlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

private struct TrimPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> TrimPlayerContainerView {
        let view = TrimPlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: TrimPlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

// MARK: - Frame Timeline View

struct FrameTimelineView: View {
    let asset: AVAsset
    let totalDuration: TimeInterval
    @Binding var trimStart: TimeInterval
    @Binding var trimEnd: TimeInterval
    @Binding var currentTime: TimeInterval
    @Binding var isDragging: Bool
    let onSeek: (TimeInterval) -> Void
    let onDragStarted: () -> Void
    let onHandleDragEnded: () -> Void

    @State private var frameThumbnails: [UIImage] = []
    @State private var isExtracting = false
    @State private var isDraggingLeft = false
    @State private var isDraggingRight = false
    @State private var isDraggingPlayhead = false
    @State private var dragInitialTrimStart: TimeInterval = 0
    @State private var dragInitialTrimEnd: TimeInterval = 0

    private let handleWidth: CGFloat = 20
    private let borderThickness: CGFloat = 3
    private let cornerRadius: CGFloat = 10
    private let frameCount = 15

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let trackHeight = geometry.size.height
            let trackWidth = max(1, totalWidth - handleWidth * 2)

            let leftFrac = totalDuration > 0 ? trimStart / totalDuration : 0
            let rightFrac = totalDuration > 0 ? trimEnd / totalDuration : 0
            let leftHandleOffset = leftFrac * trackWidth
            let rightHandleOffset = rightFrac * trackWidth

            let selectedLeft = handleWidth + leftHandleOffset
            let selectedRight = totalWidth - handleWidth - rightHandleOffset
            let barWidth = max(0, selectedRight - selectedLeft)

            let playheadFrac = totalDuration > 0 ? max(0, min(1, currentTime / totalDuration)) : 0
            let playheadX = handleWidth + playheadFrac * trackWidth

            ZStack(alignment: .topLeading) {
                // 1. Thumbnail strip
                thumbnailStrip(trackWidth: trackWidth, trackHeight: trackHeight)
                    .offset(x: handleWidth)

                // 2. Dimmed overlays on excluded thumbnails
                if leftHandleOffset > 0.5 {
                    Rectangle()
                        .fill(Color.black.opacity(0.6))
                        .frame(width: leftHandleOffset, height: trackHeight)
                        .offset(x: handleWidth)
                        .allowsHitTesting(false)
                }
                if rightHandleOffset > 0.5 {
                    Rectangle()
                        .fill(Color.black.opacity(0.6))
                        .frame(width: rightHandleOffset, height: trackHeight)
                        .offset(x: selectedRight)
                        .allowsHitTesting(false)
                }

                // 3. Yellow frame borders (top + bottom between handles)
                Rectangle()
                    .fill(Color.yellow)
                    .frame(width: barWidth, height: borderThickness)
                    .offset(x: selectedLeft)
                    .allowsHitTesting(false)

                Rectangle()
                    .fill(Color.yellow)
                    .frame(width: barWidth, height: borderThickness)
                    .offset(x: selectedLeft, y: trackHeight - borderThickness)
                    .allowsHitTesting(false)

                // 4. Scrub gesture overlay (captures tap/drag for playhead)
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(scrubGesture(trackWidth: trackWidth))

                // 5. Playhead
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white)
                    .frame(width: 3, height: trackHeight + 10)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .offset(x: playheadX - 1.5, y: -5)
                    .allowsHitTesting(false)

                // 6. Handles (on top for gesture priority)
                trimHandleView(isLeft: true, trackHeight: trackHeight)
                    .frame(width: handleWidth, height: trackHeight)
                    .offset(x: leftHandleOffset)
                    .gesture(leftHandleDrag(trackWidth: trackWidth))

                trimHandleView(isLeft: false, trackHeight: trackHeight)
                    .frame(width: handleWidth, height: trackHeight)
                    .offset(x: totalWidth - handleWidth - rightHandleOffset)
                    .gesture(rightHandleDrag(trackWidth: trackWidth))

                // 7. Tooltips (above timeline)
                if isDraggingLeft {
                    timeTooltip(time: trimStart)
                        .position(x: leftHandleOffset + handleWidth / 2, y: -18)
                }
                if isDraggingRight {
                    timeTooltip(time: totalDuration - trimEnd)
                        .position(x: totalWidth - rightHandleOffset - handleWidth / 2, y: -18)
                }
                if isDraggingPlayhead {
                    timeTooltip(time: currentTime)
                        .position(x: playheadX, y: -18)
                }
            }
            .coordinateSpace(name: "timeline")
        }
        .task { await extractFrames() }
    }

    // MARK: - Thumbnail Strip

    private func thumbnailStrip(trackWidth: CGFloat, trackHeight: CGFloat) -> some View {
        HStack(spacing: 0) {
            if frameThumbnails.isEmpty {
                ForEach(0..<frameCount, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: trackWidth / CGFloat(frameCount), height: trackHeight)
                }
            } else {
                ForEach(Array(frameThumbnails.enumerated()), id: \.offset) { _, image in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: trackWidth / CGFloat(frameThumbnails.count), height: trackHeight)
                        .clipped()
                }
            }
        }
        .cornerRadius(cornerRadius)
    }

    // MARK: - Handle View

    private func trimHandleView(isLeft: Bool, trackHeight: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.yellow)
            Image(systemName: isLeft ? "chevron.compact.left" : "chevron.compact.right")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.black.opacity(0.6))
        }
        .clipShape(
            .rect(
                topLeadingRadius: isLeft ? cornerRadius : 0,
                bottomLeadingRadius: isLeft ? cornerRadius : 0,
                bottomTrailingRadius: isLeft ? 0 : cornerRadius,
                topTrailingRadius: isLeft ? 0 : cornerRadius
            )
        )
        .contentShape(Rectangle())
    }

    // MARK: - Gestures

    private func leftHandleDrag(trackWidth: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if !isDraggingLeft {
                    isDraggingLeft = true
                    isDragging = true
                    dragInitialTrimStart = trimStart
                    onDragStarted()
                }
                let delta = (value.translation.width / trackWidth) * totalDuration
                let maxTrim = totalDuration - trimEnd - 0.1
                trimStart = max(0, min(dragInitialTrimStart + delta, maxTrim))
                onSeek(trimStart)
            }
            .onEnded { _ in
                isDraggingLeft = false
                isDragging = false
                onHandleDragEnded()
            }
    }

    private func rightHandleDrag(trackWidth: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if !isDraggingRight {
                    isDraggingRight = true
                    isDragging = true
                    dragInitialTrimEnd = trimEnd
                    onDragStarted()
                }
                let delta = -(value.translation.width / trackWidth) * totalDuration
                let maxTrim = totalDuration - trimStart - 0.1
                trimEnd = max(0, min(dragInitialTrimEnd + delta, maxTrim))
                onSeek(totalDuration - trimEnd)
            }
            .onEnded { _ in
                isDraggingRight = false
                isDragging = false
                onHandleDragEnded()
            }
    }

    private func scrubGesture(trackWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("timeline"))
            .onChanged { value in
                if !isDraggingPlayhead {
                    isDraggingPlayhead = true
                    isDragging = true
                    onDragStarted()
                }
                let x = value.location.x - handleWidth
                let fraction = max(0, min(1, x / trackWidth))
                let time = fraction * totalDuration
                let clampedTime = max(trimStart, min(totalDuration - trimEnd, time))
                onSeek(clampedTime)
            }
            .onEnded { _ in
                isDraggingPlayhead = false
                isDragging = false
            }
    }

    // MARK: - Tooltip

    private func timeTooltip(time: TimeInterval) -> some View {
        Text(formatTrimTime(time))
            .font(.system(size: 12, weight: .semibold))
            .monospacedDigit()
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color(white: 0.15)))
            .allowsHitTesting(false)
    }

    // MARK: - Frame Extraction

    private func extractFrames() async {
        guard !isExtracting, totalDuration > 0 else { return }
        isExtracting = true

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 120, height: 80)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        var images: [UIImage] = []
        let step = totalDuration / Double(frameCount)

        for i in 0..<frameCount {
            let time = CMTime(seconds: step * Double(i) + 0.01, preferredTimescale: 600)
            do {
                let (cgImage, _) = try await generator.image(at: time)
                images.append(UIImage(cgImage: cgImage))
            } catch {
                let placeholder = UIImage(systemName: "film")?.withTintColor(.gray, renderingMode: .alwaysOriginal)
                images.append(placeholder ?? UIImage())
            }
        }

        await MainActor.run {
            frameThumbnails = images
            isExtracting = false
        }
    }
}
