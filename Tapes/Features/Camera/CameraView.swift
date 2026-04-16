import SwiftUI
import AVFoundation

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

    @State private var focusPoint: CGPoint?
    @State private var showFocusSquare = false
    @State private var lastThumbnail: UIImage?
    @State private var pinchBaseZoom: CGFloat = 1.0
    @State private var showOptions = false

    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    topToolbar
                    viewfinder
                    bottomPanel
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

    // MARK: - Top Toolbar

    private var topToolbar: some View {
        HStack(spacing: 0) {
            Button {
                if capture.capturedCount > 0 {
                    capture.discardSession()
                }
                coordinator.isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showOptions.toggle()
                }
            } label: {
                Image(systemName: showOptions ? "chevron.up" : "chevron.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.15), in: Circle())
            }

            Spacer()

            torchIndicator
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(Color.black)
    }

    @ViewBuilder
    private var torchIndicator: some View {
        if !showOptions {
            Image(systemName: capture.torchEnabled ? "bolt.fill" : "bolt.slash.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(capture.torchEnabled ? .yellow : .white.opacity(0.5))
        }
    }

    // MARK: - Viewfinder

    private var viewfinder: some View {
        ZStack {
            CameraPreviewView(
                session: capture.session,
                onTap: { devicePoint, viewPoint in
                    capture.focus(at: devicePoint)
                    showFocus(at: viewPoint)
                }
            )
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

            focusSquareOverlay

            if capture.isRecording {
                VStack {
                    recordingBadge
                        .padding(.top, 12)
                    Spacer()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 2)
    }

    // MARK: - Bottom Panel

    private var bottomPanel: some View {
        VStack(spacing: 0) {
            if showOptions {
                optionsTray
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if capture.currentPosition == .back
                && !capture.availableZoomPresets.isEmpty
                && !capture.isRecording {
                zoomPill
                    .padding(.top, 14)
            }

            if !capture.isRecording {
                modePicker
                    .padding(.top, 14)
            }

            shutterRow
                .padding(.top, 20)
                .padding(.bottom, 24)
        }
        .padding(.bottom, 4)
        .background(Color.black)
    }

    // MARK: - Options Tray

    private var optionsTray: some View {
        HStack(spacing: 20) {
            optionButton(
                icon: capture.torchEnabled ? "bolt.fill" : "bolt.slash.fill",
                label: "Flash",
                isActive: capture.torchEnabled
            ) {
                capture.toggleTorch()
            }

            if capture.captureMode == .photo && capture.isLivePhotoSupported {
                optionButton(
                    icon: capture.livePhotoEnabled ? "livephoto" : "livephoto.slash",
                    label: "Live",
                    isActive: capture.livePhotoEnabled
                ) {
                    capture.livePhotoEnabled.toggle()
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private func optionButton(
        icon: String,
        label: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(isActive ? .yellow : .white)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(width: 64, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isActive ? Color.yellow.opacity(0.15) : Color.white.opacity(0.08))
            )
        }
    }

    // MARK: - Zoom Pill

    private var zoomPill: some View {
        HStack(spacing: 0) {
            ForEach(capture.availableZoomPresets) { preset in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        capture.rampZoom(to: preset.factor)
                        pinchBaseZoom = preset.factor
                    }
                } label: {
                    let isActive = isZoomPresetActive(preset)
                    Text(zoomLabel(for: preset, isActive: isActive))
                        .font(.system(size: isActive ? 13 : 12, weight: .bold, design: .rounded))
                        .foregroundStyle(isActive ? .yellow : .white.opacity(0.6))
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(isActive ? Color.white.opacity(0.2) : Color.clear)
                        )
                }
            }
        }
        .padding(.horizontal, 6)
        .background(
            Capsule()
                .fill(.black.opacity(0.5))
        )
    }

    private func isZoomPresetActive(_ preset: CaptureService.ZoomPreset) -> Bool {
        let tolerance: CGFloat = 0.15 * (preset.factor > 1 ? preset.factor : 1)
        return abs(capture.currentZoomFactor - preset.factor) < tolerance
    }

    private func zoomLabel(for preset: CaptureService.ZoomPreset, isActive: Bool) -> String {
        if isActive {
            let display = capture.displayZoomFactor
            if abs(display - round(display)) < 0.05 {
                if display < 1 { return ".5" }
                return String(format: "%.0f", display)
            }
            return String(format: "%.1f", display)
        }
        return preset.label
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        HStack(spacing: 24) {
            ForEach(CaptureService.CaptureMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        capture.captureMode = mode
                    }
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(capture.captureMode == mode ? .yellow : .white.opacity(0.4))
                }
            }
        }
    }

    // MARK: - Shutter Row

    private var shutterRow: some View {
        HStack(alignment: .center) {
            thumbnailPreview
                .frame(width: 52, alignment: .center)

            Spacer()

            shutterButton

            Spacer()

            trailingControl
                .frame(width: 52, alignment: .center)
        }
        .padding(.horizontal, 24)
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
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.white.opacity(0.35), lineWidth: 1.5)
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
                    .fill(.white.opacity(0.08))
                    .frame(width: 48, height: 48)
            }
        }
    }

    // MARK: - Trailing Control (Flip / Done)

    @ViewBuilder
    private var trailingControl: some View {
        if capture.capturedCount > 0 && !capture.isRecording {
            Button {
                let items = capture.capturedItems
                capture.discardSession()
                coordinator.handleMultiCapture(items)
            } label: {
                Text("Done")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        } else if !capture.isRecording {
            Button {
                capture.switchCamera()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
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
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
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
