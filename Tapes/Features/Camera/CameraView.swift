import SwiftUI
import AVFoundation
import CoreMotion

// MARK: - Device Orientation Observer

private final class DeviceOrientationObserver: ObservableObject {
    @Published var iconRotation: Angle = .zero
    @Published var videoRotationAngle: CGFloat = 90

    private let motionManager = CMMotionManager()

    func start() {
        guard motionManager.isAccelerometerAvailable else { return }
        motionManager.accelerometerUpdateInterval = 0.3
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let data else { return }
            let (icon, video) = Self.angles(from: data.acceleration)
            withAnimation(.easeInOut(duration: 0.25)) {
                self?.iconRotation = icon
            }
            self?.videoRotationAngle = video
        }
    }

    func stop() {
        motionManager.stopAccelerometerUpdates()
    }

    private static func angles(from acceleration: CMAcceleration) -> (icon: Angle, video: CGFloat) {
        let x = acceleration.x
        let y = acceleration.y

        if abs(y) > abs(x) {
            if y < 0 {
                return (.zero, 90)           // Portrait
            } else {
                return (.degrees(180), 270)  // Upside down
            }
        } else {
            if x > 0 {
                return (.degrees(-90), 180)  // Landscape right (home left)
            } else {
                return (.degrees(90), 0)     // Landscape left (home right)
            }
        }
    }
}

// MARK: - Camera Preview

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var onTap: ((_ devicePoint: CGPoint, _ viewPoint: CGPoint) -> Void)?

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onTap = onTap
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.onTap = onTap
    }

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var onTap: ((_ devicePoint: CGPoint, _ viewPoint: CGPoint) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            addGestureRecognizer(tap)
        }

        required init?(coder: NSCoder) { fatalError() }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            let location = gesture.location(in: self)
            let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: location)
            onTap?(devicePoint, location)
        }
    }
}

// MARK: - Camera View

struct CameraView: View {
    @ObservedObject var coordinator: CameraCoordinator
    @StateObject private var capture = CaptureService()
    @StateObject private var orientationObserver = DeviceOrientationObserver()

    @State private var focusPoint: CGPoint?
    @State private var showFocusSquare = false
    @State private var lastThumbnail: UIImage?
    @State private var pinchBaseZoom: CGFloat = 1.0
    @State private var showOptions = false
    @State private var shutterFlash = false
    @State private var showCarousel = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                CameraPreviewView(
                    session: capture.session,
                    onTap: { devicePoint, viewPoint in
                        if showOptions {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showOptions = false
                            }
                            return
                        }
                        if capture.isCountingDown { return }
                        capture.focus(at: devicePoint)
                        showFocus(at: viewPoint)
                    }
                )
                .ignoresSafeArea()
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let newZoom = pinchBaseZoom * value.magnification
                            capture.setZoom(newZoom)
                        }
                        .onEnded { _ in
                            pinchBaseZoom = capture.currentZoomFactor
                        }
                )

                if shutterFlash {
                    Color.black
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                focusSquareOverlay
                    .ignoresSafeArea()

                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 300)
                }
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)

                if showCarousel {
                    sessionCarouselOverlay
                        .transition(.opacity)
                } else if capture.isCountingDown {
                    countdownOverlay
                } else {
                    VStack(spacing: 0) {
                        Spacer()

                        if showOptions {
                            optionsPanel
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else {
                            defaultBottomControls
                        }
                    }
                }

            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !capture.isCountingDown {
                        Button {
                            if capture.capturedCount > 0 {
                                capture.discardSession()
                            }
                            coordinator.isPresented = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .rotationEffect(orientationObserver.iconRotation)
                        }
                    }
                }
                ToolbarItem(placement: .principal) {
                    if capture.isRecording {
                        recordingBadge
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !capture.isCountingDown {
                        topTrailingToolbar
                    }
                }
            }
        }
        .onChange(of: capture.captureMode) { _, newMode in
            if newMode == .photo {
                capture.ensureTorchOff()
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                showOptions = false
            }
        }
        .onChange(of: orientationObserver.videoRotationAngle) { _, newAngle in
            capture.videoRotationAngle = newAngle
        }
        .onAppear {
            AppDelegate.orientationLock = .portrait
            if let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first {
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            }

            capture.onShutterFired = {
                withAnimation(.easeIn(duration: 0.05)) {
                    shutterFlash = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        shutterFlash = false
                    }
                }
            }
            capture.onThumbnailUpdated = { image in
                lastThumbnail = image
            }
            capture.configure()
            capture.start()
            pinchBaseZoom = capture.currentZoomFactor
            orientationObserver.start()
        }
        .onDisappear {
            capture.stop()
            orientationObserver.stop()
            AppDelegate.orientationLock = .allButUpsideDown
        }
        .statusBarHidden()
    }

    private var flashIconName: String {
        capture.torchEnabled ? "bolt.fill" : "bolt.slash.fill"
    }

    // MARK: - Top Trailing Toolbar

    @ViewBuilder
    private var topTrailingToolbar: some View {
        if capture.captureMode == .video {
            Button {
                capture.toggleTorch()
            } label: {
                Image(systemName: flashIconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(capture.torchEnabled ? .yellow : .white)
                    .rotationEffect(orientationObserver.iconRotation)
                    .frame(width: 36, height: 34)
            }
            .padding(.horizontal, 4)
            .background(.ultraThinMaterial, in: Capsule())
        } else {
            HStack(spacing: 4) {
                Button {
                    capture.toggleTorch()
                } label: {
                    Image(systemName: flashIconName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(capture.torchEnabled ? .yellow : .white)
                        .rotationEffect(orientationObserver.iconRotation)
                        .frame(width: 36, height: 34)
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showOptions.toggle()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .rotationEffect(orientationObserver.iconRotation)
                        .frame(width: 36, height: 34)
                }
            }
            .padding(.horizontal, 4)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }

    // MARK: - Default Bottom Controls

    private var defaultBottomControls: some View {
        VStack(spacing: 0) {
            if capture.currentPosition == .back
                && !capture.availableZoomPresets.isEmpty
                && !capture.isRecording {
                zoomPill
                    .padding(.bottom, 16)
            }

            HStack {
                Spacer()
                shutterButton
                Spacer()
                    .overlay {
                        if !capture.isRecording {
                            flipCameraButton
                        }
                    }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)

            ZStack {
                if !capture.isRecording {
                    modePicker
                }

                HStack {
                    thumbnailPreview
                    Spacer()
                    doneButton
                }
                .padding(.horizontal, 20)
            }
            .frame(height: 48)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Zoom Pill

    private var zoomPill: some View {
        HStack(spacing: 0) {
            ForEach(capture.availableZoomPresets) { preset in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        capture.rampZoom(to: preset.factor)
                        pinchBaseZoom = preset.factor
                    }
                } label: {
                    let isActive = isZoomPresetActive(preset)
                    Text(zoomLabel(for: preset))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(isActive ? .yellow : .white.opacity(0.5))
                        .rotationEffect(orientationObserver.iconRotation)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(isActive ? Color(white: 0.22) : Color.clear)
                        )
                }
            }
        }
        .padding(.horizontal, 4)
        .background(Capsule().fill(Color.black.opacity(0.25)))
    }

    private func isZoomPresetActive(_ preset: CaptureService.ZoomPreset) -> Bool {
        let tolerance: CGFloat = 0.2 * max(preset.factor, 1)
        return abs(capture.currentZoomFactor - preset.factor) < tolerance
    }

    private func zoomLabel(for preset: CaptureService.ZoomPreset) -> String {
        if preset.id == "1" { return "1\u{00D7}" }
        return preset.label
    }

    // MARK: - Shutter Button

    private var shutterButton: some View {
        Button {
            switch capture.captureMode {
            case .photo:
                capture.capturePhotoWithTimer()
            case .video:
                if capture.isRecording {
                    capture.stopRecording()
                } else {
                    capture.startRecording()
                }
            }
        } label: {
            ZStack {
                if capture.captureMode == .photo {
                    Circle()
                        .stroke(.white, lineWidth: 4)
                        .frame(width: 76, height: 76)
                    Circle()
                        .fill(.white)
                        .frame(width: 64, height: 64)
                } else {
                    Circle()
                        .stroke(Color(white: 0.35), lineWidth: 5)
                        .frame(width: 76, height: 76)
                    if capture.isRecording {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.red)
                            .frame(width: 32, height: 32)
                    } else {
                        Circle()
                            .fill(.red)
                            .frame(width: 64, height: 64)
                    }
                }
            }
        }
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        HStack(spacing: 2) {
            ForEach(CaptureService.CaptureMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        capture.applyCaptureMode(mode)
                    }
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(capture.captureMode == mode ? .black : .white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background {
                            if capture.captureMode == mode {
                                Capsule().fill(Color.yellow)
                            }
                        }
                }
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.25), in: Capsule())
    }

    // MARK: - Thumbnail

    private var thumbnailPreview: some View {
        Group {
            if let thumb = lastThumbnail, capture.capturedCount > 0 {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showCarousel = true
                    }
                } label: {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(0.3), lineWidth: 1.5)
                        )
                        .overlay(alignment: .topTrailing) {
                            if capture.capturedCount > 1 {
                                Text("\(capture.capturedCount)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 20, height: 20)
                                    .background(.red, in: Circle())
                                    .offset(x: 4, y: -4)
                            }
                        }
                        .rotationEffect(orientationObserver.iconRotation)
                }
            } else {
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 44, height: 44)
            }
        }
    }

    // MARK: - Flip Camera

    private var flipCameraButton: some View {
        Button {
            capture.switchCamera()
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .rotationEffect(orientationObserver.iconRotation)
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    // MARK: - Done Button

    @ViewBuilder
    private var doneButton: some View {
        if capture.capturedCount > 0 && !capture.isRecording {
            Button {
                let items = capture.capturedItems
                capture.discardSession()
                coordinator.handleMultiCapture(items)
            } label: {
                Text("Done")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.yellow)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
    }

    // MARK: - Options Panel (Photo mode only)

    private var optionsPanel: some View {
        VStack {
            Spacer()

            HStack(spacing: 24) {
                cameraOptionButton(
                    icon: flashIconName,
                    label: "FLASH",
                    isActive: capture.torchEnabled
                ) {
                    capture.toggleTorch()
                }

                cameraOptionButton(
                    icon: capture.livePhotoEnabled ? "livephoto" : "livephoto.slash",
                    label: "LIVE",
                    isActive: capture.livePhotoEnabled && capture.isLivePhotoSupported,
                    disabled: !capture.isLivePhotoSupported
                ) {
                    capture.livePhotoEnabled.toggle()
                }

                timerOptionButton
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 20)
            .padding(.bottom, 60)
        }
    }

    private var timerOptionButton: some View {
        Button {
            capture.timerDelay = capture.timerDelay.next
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color(white: 0.2))
                        .frame(width: 64, height: 64)

                    if capture.timerDelay != .off {
                        Circle()
                            .stroke(Color.yellow, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                            .frame(width: 52, height: 52)
                        Text("\(capture.timerDelay.rawValue)")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.yellow)
                    } else {
                        Image(systemName: "timer")
                            .font(.system(size: 22))
                            .foregroundStyle(.white)
                    }
                }
                Text("TIMER")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private func cameraOptionButton(
        icon: String,
        label: String,
        isActive: Bool,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color(white: 0.2))
                        .frame(width: 64, height: 64)

                    if isActive && !disabled {
                        Circle()
                            .stroke(Color.yellow, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                            .frame(width: 52, height: 52)
                    }

                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundStyle(isActive && !disabled ? .yellow : .white)
                }
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }

    // MARK: - Session Carousel

    private var sessionCarouselOverlay: some View {
        GeometryReader { geo in
            let itemHeight = geo.size.height / 2

            ZStack {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showCarousel = false
                        }
                    }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 32) {
                        ForEach(Array(capture.capturedItems.enumerated()), id: \.offset) { index, item in
                            carouselItem(item, at: index, height: itemHeight)
                        }
                    }
                    .padding(.horizontal, 32)
                }
                .frame(height: itemHeight)
            }
        }
    }

    @ViewBuilder
    private func carouselItem(_ item: PickedMedia, at index: Int, height: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                switch item {
                case let .photo(image, _, _, _, _):
                    let ratio = image.size.width / max(image.size.height, 1)
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: height * ratio, height: height)
                        .clipped()

                case let .video(url, _, _):
                    if let url, let thumb = videoThumbnail(from: url) {
                        let ratio = thumb.size.width / max(thumb.size.height, 1)
                        ZStack {
                            Image(uiImage: thumb)
                                .resizable()
                                .scaledToFill()
                                .frame(width: height * ratio, height: height)
                                .clipped()
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(white: 0.2))
                            .frame(width: height * 16 / 9, height: height)
                            .overlay {
                                Image(systemName: "video.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    capture.removeItem(at: index)
                    if capture.capturedItems.isEmpty {
                        showCarousel = false
                        lastThumbnail = nil
                    }
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.6), in: Circle())
            }
            .offset(x: -4, y: 4)
        }
    }

    private func videoThumbnail(from url: URL) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 600, height: 600)
        if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
            return UIImage(cgImage: cgImage)
        }
        return nil
    }

    // MARK: - Countdown Overlay

    private var countdownOverlay: some View {
        VStack {
            HStack {
                Text("\(capture.countdownRemaining)")
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .padding(.leading, 24)
                    .padding(.top, 80)
                Spacer()
            }

            Spacer()

            Button {
                capture.cancelCountdown()
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color(white: 0.35), lineWidth: 5)
                        .frame(width: 76, height: 76)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.white)
                        .frame(width: 28, height: 28)
                }
            }
            .padding(.bottom, 60)
        }
    }

    // MARK: - Focus Square

    @ViewBuilder
    private var focusSquareOverlay: some View {
        if showFocusSquare, let point = focusPoint {
            FocusSquare()
                .position(point)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    private func showFocus(at point: CGPoint) {
        focusPoint = point
        withAnimation(.easeIn(duration: 0.15)) {
            showFocusSquare = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.3)) {
                showFocusSquare = false
            }
        }
    }

    // MARK: - Recording Badge

    private var recordingBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
            Text(formattedDuration)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var formattedDuration: String {
        let total = Int(capture.recordingDuration)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Focus Square Shape

private struct FocusSquare: View {
    @State private var scale: CGFloat = 1.4
    @State private var opacity: Double = 1

    var body: some View {
        Rectangle()
            .stroke(Color.yellow, lineWidth: 1.5)
            .frame(width: 80, height: 80)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.25)) {
                    scale = 1.0
                }
                withAnimation(.easeInOut(duration: 0.8).delay(0.8)) {
                    opacity = 0.4
                }
            }
    }
}
