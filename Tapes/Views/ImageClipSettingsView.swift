import SwiftUI
import Photos
import AVFoundation

struct ImageClipSettingsView: View {
    @Binding var tape: Tape
    let clipID: UUID
    let onDismiss: () -> Void
    @EnvironmentObject var tapesStore: TapesStore

    @State private var selectedMotion: MotionStyle
    @State private var duration: Double
    @State private var livePhotoAsVideo: Bool
    @State private var livePhotoMuted: Bool
    @State private var clipVolume: Double
    @State private var clipMusicVolume: Double
    @State private var hasChanges = false
    @State private var clipImage: UIImage?
    @State private var showLivePhotoToast = false
    @State private var showMotionMenu = false
    @State private var livePhotoCollapseTask: Task<Void, Never>?

    // Motion preview
    @State private var motionAnimationID = UUID()

    // Live Photo video preview
    @State private var livePhotoPlayer: AVPlayer?
    @State private var livePhotoVideoURL: URL?
    @State private var loopObserver: Any?

    // Background music
    @State private var bgMusic = BackgroundMusicPlayer()

    private var clip: Clip? {
        tape.clips.first(where: { $0.id == clipID })
    }

    private var isLivePhoto: Bool {
        clip?.isLivePhoto ?? false
    }

    private var livePhotoIsOn: Bool {
        isLivePhoto && livePhotoAsVideo
    }

    private var hasBackgroundMusic: Bool { tape.musicMood != .none }

    init(tape: Binding<Tape>, clipID: UUID, onDismiss: @escaping () -> Void) {
        self._tape = tape
        self.clipID = clipID
        self.onDismiss = onDismiss

        if let clip = tape.wrappedValue.clips.first(where: { $0.id == clipID }) {
            self._selectedMotion = State(initialValue: clip.motionStyle)
            self._duration = State(initialValue: clip.imageDuration)
            let tapeDefault = tape.wrappedValue.livePhotosAsVideo
            self._livePhotoAsVideo = State(initialValue: clip.livePhotoAsVideo ?? tapeDefault)
            let muteDefault = tape.wrappedValue.livePhotosMuted
            self._livePhotoMuted = State(initialValue: clip.livePhotoMuted ?? muteDefault)
            self._clipVolume = State(initialValue: clip.volume ?? 1.0)
            self._clipMusicVolume = State(initialValue: clip.musicVolume ?? Double(tape.wrappedValue.musicVolume))
        } else {
            self._selectedMotion = State(initialValue: .kenBurns)
            self._duration = State(initialValue: 4.0)
            self._livePhotoAsVideo = State(initialValue: tape.wrappedValue.livePhotosAsVideo)
            self._livePhotoMuted = State(initialValue: tape.wrappedValue.livePhotosMuted)
            self._clipVolume = State(initialValue: 1.0)
            self._clipMusicVolume = State(initialValue: Double(tape.wrappedValue.musicVolume))
        }
    }

    var body: some View {
        ZStack {
            previewBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                settingsHeader
                    .padding(.top, 8)

                Spacer()

                controlsPills
                    .padding(.bottom, 16)

                bottomBar
            }
            .background(alignment: .top) {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.8), location: 0),
                        .init(color: .black.opacity(0.3), location: 0.4),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 300)
                .ignoresSafeArea()
            }

        }
        .task {
            await loadClipImage()
            if livePhotoIsOn { startLivePhotoPlayback() }
            if hasBackgroundMusic {
                await bgMusic.prepare(
                    mood: tape.musicMood,
                    tapeID: tape.id,
                    volume: Float(clipMusicVolume)
                )
                bgMusic.syncPlay()
            }
        }
        .onChange(of: livePhotoAsVideo) { _, isOn in
            if isOn { startLivePhotoPlayback() } else { stopLivePhotoPlayback() }
        }
        .onChange(of: clipVolume) { _, vol in
            livePhotoPlayer?.volume = Float(vol)
        }
        .onChange(of: clipMusicVolume) { _, vol in
            bgMusic.setVolume(Float(vol))
        }
        .onChange(of: selectedMotion) { _, _ in
            motionAnimationID = UUID()
        }
        .onChange(of: duration) { _, _ in
            motionAnimationID = UUID()
        }
        .onDisappear {
            stopLivePhotoPlayback()
            bgMusic.syncStop()
        }
    }

    // MARK: - Preview Background

    private var previewBackground: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                if livePhotoIsOn, let player = livePhotoPlayer {
                    LivePhotoPlayerLayerView(player: player)
                        .frame(width: geo.size.width, height: geo.size.height)
                } else if let clipImage {
                    MotionPreviewImage(
                        image: clipImage,
                        style: selectedMotion,
                        cycleDuration: duration,
                        size: geo.size
                    )
                    .id(motionAnimationID)
                }
            }
        }
    }

    // MARK: - Header

    private var settingsHeader: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.2))
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .contentShape(Circle())
            }

            Spacer()

            Text("Image settings")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            Button(action: { save() }) {
                Text("Done")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(.black.opacity(0.2))
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .contentShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Controls Pills (floating above bottom bar)

    private var controlsPills: some View {
        HStack(alignment: .bottom) {
            if isLivePhoto {
                livePhotoButton
            }

            Spacer()

            HStack(alignment: .bottom, spacing: 16) {
                if livePhotoIsOn {
                    VerticalVolumeSlider(
                        value: $clipVolume,
                        icon: "speaker.wave.2.fill"
                    )
                }

                if hasBackgroundMusic {
                    VerticalVolumeSlider(
                        value: $clipMusicVolume,
                        icon: "music.note"
                    )
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Live Photo Toggle Pill

    private var livePhotoButton: some View {
        Button {
            toggleLivePhoto()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: livePhotoAsVideo ? "livephoto.play" : "livephoto")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(livePhotoAsVideo ? .yellow : .white)
                    .frame(width: 24, height: 24)

                if showLivePhotoToast {
                    Text("Live photo **\(livePhotoAsVideo ? "ON" : "OFF")**")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize()
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0, anchor: .leading).combined(with: .opacity),
                                removal: .scale(scale: 0, anchor: .leading).combined(with: .opacity)
                            )
                        )
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, showLivePhotoToast ? 14 : 10)
            .frame(height: 44)
            .background(.black.opacity(0.2))
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 4) {
            Text("Image play Duration")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)

            HStack(spacing: 12) {
                Text("3s")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(livePhotoIsOn ? 0.3 : 0.6))
                    .monospacedDigit()

                Slider(value: $duration, in: 3.0...10.0, step: 0.5)
                    .tint(Color(red: 0, green: 0.478, blue: 1))
                    .disabled(livePhotoIsOn)
                    .opacity(livePhotoIsOn ? 0.4 : 1)
                    .onChange(of: duration) { _, _ in hasChanges = true }

                Text("10s")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(livePhotoIsOn ? 0.3 : 0.6))
                    .monospacedDigit()

                Button {
                    showMotionMenu = true
                } label: {
                    Image(systemName: "circle.dotted.and.circle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(selectedMotion == .none ? .white : Color(red: 0, green: 0.478, blue: 1))
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.2))
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .contentShape(Circle())
                }
                .disabled(livePhotoIsOn)
                .opacity(livePhotoIsOn ? 0.4 : 1)
                .popover(isPresented: $showMotionMenu) {
                    motionOptionsList
                        .presentationCompactAdaptation(.popover)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
        .background(
            Color.black.opacity(0.4)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
        )
    }

    private func motionIcon(for style: MotionStyle) -> String {
        switch style {
        case .none: return "rectangle.slash"
        case .kenBurns: return "camera.metering.matrix"
        case .pan: return "arrow.left.and.right"
        case .zoomIn: return "plus.magnifyingglass"
        case .zoomOut: return "minus.magnifyingglass"
        case .drift: return "wind"
        }
    }

    // MARK: - Motion Options List

    private var motionOptionsList: some View {
        VStack(spacing: 0) {
            ForEach(MotionStyle.allCases, id: \.self) { style in
                Button {
                    selectedMotion = style
                    hasChanges = true
                    showMotionMenu = false
                    provideHaptic()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: motionIcon(for: style))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 24)

                        Text(style.displayName)
                            .font(.system(size: 16))
                            .foregroundStyle(.white)

                        Spacer()

                        if selectedMotion == style {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }

                if style != MotionStyle.allCases.last {
                    Divider()
                }
            }
        }
        .frame(width: 200)
    }

    // MARK: - Actions

    private func toggleLivePhoto() {
        livePhotoAsVideo.toggle()
        hasChanges = true

        if livePhotoAsVideo {
            duration = 3.0
            livePhotoMuted = false
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showLivePhotoToast = true
        }

        livePhotoCollapseTask?.cancel()
        livePhotoCollapseTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                showLivePhotoToast = false
            }
        }

        provideHaptic()
    }

    private func save() {
        guard var clip = tape.clips.first(where: { $0.id == clipID }) else { return }
        clip.motionStyle = selectedMotion
        clip.imageDuration = duration
        clip.duration = duration

        if clip.isLivePhoto {
            let tapeDefault = tape.livePhotosAsVideo
            clip.livePhotoAsVideo = (livePhotoAsVideo == tapeDefault) ? nil : livePhotoAsVideo
            let muteDefault = tape.livePhotosMuted
            clip.livePhotoMuted = (livePhotoMuted == muteDefault) ? nil : livePhotoMuted
        }

        clip.volume = clipVolume < 0.99 ? clipVolume : nil
        let tapeDefault = Double(tape.musicVolume)
        clip.musicVolume = abs(clipMusicVolume - tapeDefault) > 0.01 ? clipMusicVolume : nil

        clip.updatedAt = Date()
        tape.updateClip(clip)
        tapesStore.updateTape(tape)
        onDismiss()
    }

    // MARK: - Image Loading

    private func loadClipImage() async {
        guard let clip else { return }

        if let imageData = clip.imageData, let image = UIImage(data: imageData) {
            await MainActor.run { clipImage = image }
            return
        }

        guard let assetId = clip.assetLocalId else { return }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        guard let asset = result.firstObject else { return }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        let targetSize = CGSize(width: UIScreen.main.bounds.width * UIScreen.main.scale,
                                height: UIScreen.main.bounds.height * UIScreen.main.scale)

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            if let image {
                Task { @MainActor in clipImage = image }
            }
        }
    }

    // MARK: - Live Photo Video Playback

    private func startLivePhotoPlayback() {
        stopLivePhotoPlayback()
        guard let clip, let assetId = clip.assetLocalId else { return }

        Task {
            guard let result = await extractLivePhotoVideo(assetIdentifier: assetId) else { return }
            let player = AVPlayer(url: result.url)
            player.volume = Float(clipVolume)

            let observer = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { _ in
                player.seek(to: .zero)
                player.play()
            }

            await MainActor.run {
                self.livePhotoVideoURL = result.url
                self.livePhotoPlayer = player
                self.loopObserver = observer
                player.play()
            }
        }
    }

    private func stopLivePhotoPlayback() {
        livePhotoPlayer?.pause()
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        livePhotoPlayer = nil
        loopObserver = nil

        if let url = livePhotoVideoURL {
            try? FileManager.default.removeItem(at: url)
            livePhotoVideoURL = nil
        }
    }

    private func provideHaptic() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

// MARK: - Motion Preview Image

private struct MotionPreviewImage: View {
    let image: UIImage
    let style: MotionStyle
    let cycleDuration: Double
    let size: CGSize

    @State private var progress: CGFloat = 0
    @State private var animationStartDate = Date()

    var body: some View {
        let effect = motionValues
        let t = progress
        let scale = effect.startScale + (effect.endScale - effect.startScale) * t
        let ox = (effect.startOffset.x + (effect.endOffset.x - effect.startOffset.x) * t) * size.width
        let oy = (effect.startOffset.y + (effect.endOffset.y - effect.startOffset.y) * t) * size.height

        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size.width, height: size.height)
            .scaleEffect(scale)
            .offset(x: ox, y: oy)
            .clipped()
            .onAppear { startCycle() }
    }

    private func startCycle() {
        guard style != .none else { return }
        progress = 0
        animationStartDate = Date()
        withAnimation(.easeInOut(duration: cycleDuration)) {
            progress = 1
        }
        scheduleReset()
    }

    private func scheduleReset() {
        let cycleStart = animationStartDate
        DispatchQueue.main.asyncAfter(deadline: .now() + cycleDuration + 0.3) {
            guard cycleStart == animationStartDate else { return }
            withAnimation(.none) {
                progress = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard cycleStart == animationStartDate else { return }
                animationStartDate = Date()
                withAnimation(.easeInOut(duration: cycleDuration)) {
                    progress = 1
                }
                scheduleReset()
            }
        }
    }

    private var motionValues: (startScale: CGFloat, endScale: CGFloat, startOffset: CGPoint, endOffset: CGPoint) {
        switch style {
        case .none:
            return (1, 1, .zero, .zero)
        case .kenBurns:
            return (1.0, 1.2, CGPoint(x: -0.05, y: 0.03), CGPoint(x: 0.05, y: -0.03))
        case .pan:
            return (1.2, 1.2, CGPoint(x: -0.10, y: 0.0), CGPoint(x: 0.10, y: 0.0))
        case .zoomIn:
            return (1.0, 1.3, .zero, .zero)
        case .zoomOut:
            return (1.3, 1.0, .zero, .zero)
        case .drift:
            return (1.03, 1.09, CGPoint(x: 0.02, y: -0.02), CGPoint(x: -0.02, y: 0.02))
        }
    }
}

// MARK: - Live Photo Player Layer

private final class LivePhotoPlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

private struct LivePhotoPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> LivePhotoPlayerContainerView {
        let view = LivePhotoPlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: LivePhotoPlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
    }
}
