import SwiftUI
import AVFoundation

// MARK: - Camera Preview

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var onTap: ((CGPoint) -> Void)?

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
        var onTap: ((CGPoint) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            addGestureRecognizer(tap)
        }

        required init?(coder: NSCoder) { fatalError() }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            let location = gesture.location(in: self)
            let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: location)
            onTap?(devicePoint)
        }
    }
}

// MARK: - Camera View

struct CameraView: View {
    @ObservedObject var coordinator: CameraCoordinator
    @StateObject private var capture = CaptureService()

    @State private var focusPoint: CGPoint?
    @State private var showFocusSquare = false
    @State private var lastThumbnail: UIImage?
    @State private var pinchBaseZoom: CGFloat = 1.0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                CameraPreviewView(
                    session: capture.session,
                    onTap: { devicePoint in
                        capture.focus(at: devicePoint)
                        let screenPoint = CGPoint(
                            x: devicePoint.y * geo.size.width,
                            y: (1 - devicePoint.x) * geo.size.height
                        )
                        showFocus(at: screenPoint)
                    }
                )
                .ignoresSafeArea()
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let newZoom = pinchBaseZoom * value.magnification
                            capture.setZoom(newZoom)
                        }
                        .onEnded { value in
                            pinchBaseZoom = capture.currentZoomFactor
                        }
                )

                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    zoomBar
                        .padding(.bottom, 16)
                    bottomControls
                }

                focusSquareOverlay

                if capture.isRecording {
                    recordingBadge
                }
            }
        }
        .onAppear {
            capture.onThumbnailUpdated = { image in
                lastThumbnail = image
            }
            capture.configure()
            capture.start()
            pinchBaseZoom = capture.currentZoomFactor
        }
        .onDisappear {
            capture.stop()
        }
        .statusBarHidden()
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                if capture.capturedCount > 0 {
                    capture.discardSession()
                }
                coordinator.isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }

            Spacer()

            if capture.captureMode == .photo && capture.isLivePhotoSupported {
                Button {
                    capture.livePhotoEnabled.toggle()
                } label: {
                    Image(systemName: capture.livePhotoEnabled ? "livephoto" : "livephoto.slash")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(capture.livePhotoEnabled ? .yellow : .white)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }

            Button {
                capture.torchEnabled.toggle()
            } label: {
                Image(systemName: capture.torchEnabled ? "bolt.fill" : "bolt.slash.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(capture.torchEnabled ? .yellow : .white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Zoom Bar

    @ViewBuilder
    private var zoomBar: some View {
        if capture.currentPosition == .back && !capture.availableZoomPresets.isEmpty && !capture.isRecording {
            HStack(spacing: 0) {
                ForEach(capture.availableZoomPresets) { preset in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            capture.rampZoom(to: preset.factor)
                            pinchBaseZoom = preset.factor
                        }
                    } label: {
                        let isActive = isZoomPresetActive(preset)
                        Text(preset.label)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(isActive ? .yellow : .white)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(isActive ? .white.opacity(0.25) : .clear)
                            )
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private func isZoomPresetActive(_ preset: CaptureService.ZoomPreset) -> Bool {
        abs(capture.currentZoomFactor - preset.factor) < 0.1
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 16) {
            if !capture.isRecording {
                modePicker
            }

            HStack(alignment: .center) {
                thumbnailPreview
                    .frame(width: 48)

                Spacer()
                shutterButton
                Spacer()

                flipOrDoneButton
                    .frame(width: 48)
            }
            .padding(.horizontal, 28)
        }
        .padding(.bottom, 36)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(CaptureService.CaptureMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        capture.captureMode = mode
                    }
                } label: {
                    Text(mode.rawValue.uppercased())
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(capture.captureMode == mode ? .yellow : .white.opacity(0.5))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
            }
        }
        .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: - Shutter Button

    private var shutterButton: some View {
        Button {
            switch capture.captureMode {
            case .photo:
                capture.capturePhoto()
            case .video:
                if capture.isRecording {
                    capture.stopRecording()
                } else {
                    capture.startRecording()
                }
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 74, height: 74)

                if capture.captureMode == .photo {
                    Circle()
                        .fill(.white)
                        .frame(width: 62, height: 62)
                } else {
                    if capture.isRecording {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.red)
                            .frame(width: 30, height: 30)
                    } else {
                        Circle()
                            .fill(.red)
                            .frame(width: 62, height: 62)
                    }
                }
            }
        }
    }

    // MARK: - Thumbnail Preview

    private var thumbnailPreview: some View {
        Group {
            if let thumb = lastThumbnail {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.white.opacity(0.4), lineWidth: 1.5)
                    )
                    .overlay(alignment: .topTrailing) {
                        if capture.capturedCount > 1 {
                            Text("\(capture.capturedCount)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(.red, in: Circle())
                                .offset(x: 6, y: -6)
                        }
                    }
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(0.1))
                    .frame(width: 44, height: 44)
            }
        }
    }

    // MARK: - Flip / Done Button

    @ViewBuilder
    private var flipOrDoneButton: some View {
        if capture.capturedCount > 0 && !capture.isRecording {
            Button {
                let items = capture.capturedItems
                capture.discardSession()
                coordinator.handleMultiCapture(items)
            } label: {
                Text("Done")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.yellow, in: Capsule())
            }
        } else {
            Button {
                capture.switchCamera()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .disabled(capture.isRecording)
            .opacity(capture.isRecording ? 0.3 : 1)
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
        VStack {
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
            .padding(.top, 64)

            Spacer()
        }
    }

    private var formattedDuration: String {
        let total = Int(capture.recordingDuration)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Focus Square

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
