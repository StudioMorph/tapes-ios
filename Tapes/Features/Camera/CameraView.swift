import SwiftUI
import AVFoundation

// MARK: - Camera Preview

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - Camera View

struct CameraView: View {
    @ObservedObject var coordinator: CameraCoordinator
    @StateObject private var capture = CaptureService()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreviewView(session: capture.session)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomControls
            }

            if capture.isRecording {
                recordingBadge
            }
        }
        .onAppear {
            capture.onPhotoCaptured = { image in
                coordinator.handleCapturedMedia([
                    .photo(image: image, assetIdentifier: nil)
                ])
            }
            capture.onVideoCaptured = { url, duration in
                coordinator.handleCapturedMedia([
                    .video(url: url, duration: duration, assetIdentifier: nil)
                ])
            }
            capture.configure()
            capture.start()
        }
        .onDisappear {
            capture.stop()
        }
        .statusBarHidden()
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                coordinator.isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial.opacity(0.6))
                    .clipShape(Circle())
            }

            Spacer()

            Button {
                capture.torchEnabled.toggle()
            } label: {
                Image(systemName: capture.torchEnabled ? "bolt.fill" : "bolt.slash.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(capture.torchEnabled ? .yellow : .white)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial.opacity(0.6))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 20) {
            if !capture.isRecording {
                modePicker
            }

            HStack {
                Color.clear.frame(width: 48, height: 48)

                Spacer()
                shutterButton
                Spacer()

                flipButton
            }
            .padding(.horizontal, 32)
        }
        .padding(.bottom, 44)
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
                    Text(mode.rawValue.uppercased())
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(capture.captureMode == mode ? .yellow : .white.opacity(0.6))
                }
            }
        }
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

    // MARK: - Flip Button

    private var flipButton: some View {
        Button {
            capture.switchCamera()
        } label: {
            Image(systemName: "camera.rotate.fill")
                .font(.system(size: 20))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial.opacity(0.6))
                .clipShape(Circle())
        }
        .disabled(capture.isRecording)
        .opacity(capture.isRecording ? 0.3 : 1)
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
            .background(.black.opacity(0.55))
            .clipShape(Capsule())
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
