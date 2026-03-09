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

    private var totalDuration: TimeInterval {
        assetDuration > 0 ? assetDuration : clip.duration
    }

    private var trimmedDuration: TimeInterval {
        max(0, totalDuration - trimStart - trimEnd)
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

                    VStack(spacing: Tokens.Spacing.m) {
                        timeLabel

                        if asset != nil, totalDuration > 0 {
                            FrameTimelineView(
                                asset: asset!,
                                totalDuration: totalDuration,
                                trimStart: $trimStart,
                                trimEnd: $trimEnd,
                                currentTime: $currentTime,
                                onSeek: { time in seekTo(time) }
                            )
                            .frame(height: 56)
                        } else {
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

                        playbackControls
                    }
                    .padding(.horizontal, Tokens.Spacing.l)
                    .padding(.bottom, Tokens.Spacing.xl)
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

    private var timeLabel: some View {
        HStack {
            Text(formatTime(max(0, currentTime - trimStart)))
                .monospacedDigit()
            Spacer()
            Text(formatTime(trimmedDuration))
                .monospacedDigit()
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundColor(.white.opacity(0.7))
    }

    private var playbackControls: some View {
        HStack(spacing: Tokens.Spacing.xl) {
            Spacer()
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
                    .frame(width: Tokens.HitTarget.recommended, height: Tokens.HitTarget.recommended)
            }
            Spacer()
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
            if currentTime >= totalDuration - trimEnd {
                seekTo(trimStart)
            }
            player.play()
            isPlaying = true
        }
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
            let endBound = totalDuration - trimEnd
            if t >= endBound && isPlaying {
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

    // MARK: - Helpers

    private func formatTime(_ seconds: TimeInterval) -> String {
        let clamped = max(0, seconds)
        let mins = Int(clamped) / 60
        let secs = Int(clamped) % 60
        let frac = Int((clamped.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", mins, secs, frac)
    }
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
    let onSeek: (TimeInterval) -> Void

    @State private var frameThumbnails: [UIImage] = []
    @State private var isExtracting = false
    @GestureState private var dragStartTrimStart: TimeInterval? = nil
    @GestureState private var dragStartTrimEnd: TimeInterval? = nil

    private let handleWidth: CGFloat = 16
    private let frameCount = 15

    var body: some View {
        GeometryReader { geometry in
            let trackWidth = max(1, geometry.size.width - handleWidth * 2)
            let trackHeight = geometry.size.height

            let leftFraction = totalDuration > 0 ? trimStart / totalDuration : 0
            let rightFraction = totalDuration > 0 ? trimEnd / totalDuration : 0
            let leftOffset = leftFraction * trackWidth
            let rightOffset = rightFraction * trackWidth

            ZStack(alignment: .leading) {
                thumbnailStrip(trackWidth: trackWidth, trackHeight: trackHeight)
                    .offset(x: handleWidth)

                dimmedOverlay(side: .leading, offset: leftOffset, trackHeight: trackHeight)
                dimmedOverlay(side: .trailing, offset: rightOffset, trackHeight: trackHeight, totalWidth: geometry.size.width)

                trimBorder(leftOffset: leftOffset, rightOffset: rightOffset, totalWidth: geometry.size.width, trackHeight: trackHeight)

                leftHandle(trackHeight: trackHeight, trackWidth: trackWidth)
                rightHandle(trackHeight: trackHeight, trackWidth: trackWidth, totalWidth: geometry.size.width)

                playheadIndicator(trackWidth: trackWidth, trackHeight: trackHeight)
            }
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
        .cornerRadius(6)
    }

    // MARK: - Dimmed Overlays

    private enum Side { case leading, trailing }

    private func dimmedOverlay(side: Side, offset: CGFloat, trackHeight: CGFloat, totalWidth: CGFloat = 0) -> some View {
        Group {
            switch side {
            case .leading:
                Rectangle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: handleWidth + offset, height: trackHeight)
                    .allowsHitTesting(false)
            case .trailing:
                Rectangle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: handleWidth + offset, height: trackHeight)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Trim Border

    private func trimBorder(leftOffset: CGFloat, rightOffset: CGFloat, totalWidth: CGFloat, trackHeight: CGFloat) -> some View {
        let x = handleWidth + leftOffset
        let w = totalWidth - handleWidth * 2 - leftOffset - rightOffset
        return RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Color.yellow, lineWidth: 3)
            .frame(width: max(0, w), height: trackHeight)
            .offset(x: x)
            .allowsHitTesting(false)
    }

    // MARK: - Handles (fixed drag logic)

    private func leftHandle(trackHeight: CGFloat, trackWidth: CGFloat) -> some View {
        let leftOffset = totalDuration > 0 ? (trimStart / totalDuration) * trackWidth : 0

        return handleView(systemName: "chevron.compact.left")
            .frame(width: handleWidth, height: trackHeight)
            .offset(x: leftOffset)
            .gesture(
                DragGesture()
                    .updating($dragStartTrimStart) { _, state, _ in
                        if state == nil { state = trimStart }
                    }
                    .onChanged { value in
                        guard let startValue = dragStartTrimStart else { return }
                        let delta = (value.translation.width / trackWidth) * totalDuration
                        let maxTrim = totalDuration - trimEnd - 0.1
                        trimStart = max(0, min(startValue + delta, maxTrim))
                    }
            )
    }

    private func rightHandle(trackHeight: CGFloat, trackWidth: CGFloat, totalWidth: CGFloat) -> some View {
        let rightOffset = totalDuration > 0 ? (trimEnd / totalDuration) * trackWidth : 0

        return handleView(systemName: "chevron.compact.right")
            .frame(width: handleWidth, height: trackHeight)
            .offset(x: totalWidth - handleWidth - rightOffset)
            .gesture(
                DragGesture()
                    .updating($dragStartTrimEnd) { _, state, _ in
                        if state == nil { state = trimEnd }
                    }
                    .onChanged { value in
                        guard let startValue = dragStartTrimEnd else { return }
                        let delta = -(value.translation.width / trackWidth) * totalDuration
                        let maxTrim = totalDuration - trimStart - 0.1
                        trimEnd = max(0, min(startValue + delta, maxTrim))
                    }
            )
    }

    private func handleView(systemName: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.yellow)
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.black)
        }
    }

    // MARK: - Playhead

    private func playheadIndicator(trackWidth: CGFloat, trackHeight: CGFloat) -> some View {
        let fraction = totalDuration > 0 ? currentTime / totalDuration : 0
        let x = handleWidth + fraction * trackWidth
        return Rectangle()
            .fill(Color.white)
            .frame(width: 2, height: trackHeight + 8)
            .offset(x: x - 1)
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
