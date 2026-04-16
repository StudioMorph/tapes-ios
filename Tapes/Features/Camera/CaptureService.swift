import AVFoundation
import UIKit

final class CaptureService: NSObject, ObservableObject {

    // MARK: - Published State

    @Published private(set) var isSessionRunning = false
    @Published var captureMode: CaptureMode = .video
    @Published private(set) var isRecording = false
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published var torchEnabled = false
    @Published private(set) var currentPosition: AVCaptureDevice.Position = .back
    @Published private(set) var currentZoomFactor: CGFloat = 2.0
    @Published var livePhotoEnabled = true
    @Published private(set) var isLivePhotoSupported = false
    @Published private(set) var capturedCount = 0

    enum CaptureMode: String, CaseIterable {
        case video = "VIDEO"
        case photo = "PHOTO"
    }

    struct ZoomPreset: Identifiable {
        let id: String
        let label: String
        let factor: CGFloat
    }

    private(set) var availableZoomPresets: [ZoomPreset] = []
    private(set) var primarySwitchOverFactor: CGFloat = 1.0

    /// User-facing zoom multiplier (0.5x, 1x, 2x, etc.)
    var displayZoomFactor: CGFloat {
        guard primarySwitchOverFactor > 1.0 else { return currentZoomFactor }
        return currentZoomFactor / primarySwitchOverFactor
    }

    // MARK: - Session

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.studiomorph.tapes.capture")

    private var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?
    let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()

    private var recordingTimer: Timer?
    private var recordingStartTime: Date?

    // MARK: - Multi-capture

    private(set) var capturedItems: [PickedMedia] = []

    // MARK: - Callbacks

    var onPhotoCaptured: ((UIImage) -> Void)?
    var onVideoCaptured: ((URL, TimeInterval) -> Void)?
    var onSessionComplete: (([PickedMedia]) -> Void)?
    var onThumbnailUpdated: ((UIImage) -> Void)?

    // MARK: - Lifecycle

    func configure() {
        sessionQueue.async { [weak self] in
            self?.configureSession()
        }
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = self.session.isRunning
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }
            self.session.stopRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = false
                self.isRecording = false
                self.cleanupRecordingTimer()
            }
        }
    }

    func finishSession() {
        let items = capturedItems
        capturedItems = []
        DispatchQueue.main.async { [weak self] in
            self?.capturedCount = 0
            self?.onSessionComplete?(items)
        }
    }

    func discardSession() {
        capturedItems = []
        DispatchQueue.main.async { [weak self] in
            self?.capturedCount = 0
        }
    }

    // MARK: - Session Configuration

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let videoDevice = bestBackDevice() else {
            session.commitConfiguration()
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: videoDevice)
            if session.canAddInput(input) {
                session.addInput(input)
                videoDeviceInput = input
            }
        } catch {
            session.commitConfiguration()
            return
        }

        if let audioDevice = AVCaptureDevice.default(for: .audio) {
            if let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
               session.canAddInput(audioInput) {
                session.addInput(audioInput)
                audioDeviceInput = audioInput
            }
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
            if photoOutput.isLivePhotoCaptureSupported {
                photoOutput.isLivePhotoCaptureEnabled = true
            }
        }

        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
            if let connection = movieOutput.connection(with: .video),
               connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
            }
        }

        let switchOvers = videoDevice.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat($0.doubleValue) }
        let switchFactor = switchOvers.first ?? 1.0

        if switchFactor > 1.0 {
            do {
                try videoDevice.lockForConfiguration()
                videoDevice.videoZoomFactor = switchFactor
                videoDevice.unlockForConfiguration()
            } catch {}
        }

        session.commitConfiguration()

        let presets = buildZoomPresets(for: videoDevice)
        DispatchQueue.main.async { [weak self] in
            self?.availableZoomPresets = presets
            self?.primarySwitchOverFactor = switchFactor
            self?.currentZoomFactor = switchFactor
            self?.isLivePhotoSupported = self?.photoOutput.isLivePhotoCaptureSupported ?? false
        }
    }

    private func bestBackDevice() -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInDualCamera,
                .builtInWideAngleCamera
            ],
            mediaType: .video,
            position: .back
        )
        return discovery.devices.first
    }

    private func bestFrontDevice() -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
    }

    /// Maps physical lens switchover points to user-facing zoom labels (.5x, 1x, 2x).
    private func buildZoomPresets(for device: AVCaptureDevice) -> [ZoomPreset] {
        let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat($0.doubleValue) }
        var presets: [ZoomPreset] = []

        if let wideSwitch = switchOvers.first {
            presets.append(ZoomPreset(id: "0.5", label: ".5", factor: 1.0))
            presets.append(ZoomPreset(id: "1", label: "1", factor: wideSwitch))
            let twoX = wideSwitch * 2.0
            if twoX <= device.maxAvailableVideoZoomFactor {
                presets.append(ZoomPreset(id: "2", label: "2", factor: twoX))
            }
        } else {
            presets.append(ZoomPreset(id: "1", label: "1", factor: 1.0))
            if device.maxAvailableVideoZoomFactor >= 2.0 {
                presets.append(ZoomPreset(id: "2", label: "2", factor: 2.0))
            }
        }

        return presets
    }

    // MARK: - Zoom

    func setZoom(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDeviceInput?.device else { return }
            let clamped = max(device.minAvailableVideoZoomFactor, min(factor, device.maxAvailableVideoZoomFactor))
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    self.currentZoomFactor = clamped
                }
            } catch {}
        }
    }

    func rampZoom(to factor: CGFloat, rate: Float = 4.0) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDeviceInput?.device else { return }
            let clamped = max(device.minAvailableVideoZoomFactor, min(factor, device.maxAvailableVideoZoomFactor))
            do {
                try device.lockForConfiguration()
                device.ramp(toVideoZoomFactor: clamped, withRate: rate)
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    self.currentZoomFactor = clamped
                }
            } catch {}
        }
    }

    // MARK: - Focus & Exposure

    func focus(at point: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDeviceInput?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = point
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = point
                    device.exposureMode = .autoExpose
                }
                device.unlockForConfiguration()
            } catch {}
        }
    }

    // MARK: - Camera Switch

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let newPosition: AVCaptureDevice.Position = self.currentPosition == .back ? .front : .back

            let newDevice: AVCaptureDevice?
            if newPosition == .back {
                newDevice = self.bestBackDevice()
            } else {
                newDevice = self.bestFrontDevice()
            }

            guard let device = newDevice else { return }

            self.session.beginConfiguration()

            if let current = self.videoDeviceInput {
                self.session.removeInput(current)
            }

            do {
                let newInput = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(newInput) {
                    self.session.addInput(newInput)
                    self.videoDeviceInput = newInput
                }
            } catch {
                if let old = self.videoDeviceInput, self.session.canAddInput(old) {
                    self.session.addInput(old)
                }
            }

            self.session.commitConfiguration()

            let presets: [ZoomPreset]
            let switchFactor: CGFloat

            if newPosition == .back {
                presets = self.buildZoomPresets(for: device)
                let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat($0.doubleValue) }
                switchFactor = switchOvers.first ?? 1.0

                if switchFactor > 1.0 {
                    do {
                        try device.lockForConfiguration()
                        device.videoZoomFactor = switchFactor
                        device.unlockForConfiguration()
                    } catch {}
                }
            } else {
                presets = []
                switchFactor = 1.0
            }

            DispatchQueue.main.async {
                self.currentPosition = newPosition
                self.torchEnabled = false
                self.currentZoomFactor = switchFactor
                self.primarySwitchOverFactor = switchFactor
                self.availableZoomPresets = presets
            }
        }
    }

    // MARK: - Torch

    func toggleTorch() {
        torchEnabled.toggle()
        if captureMode == .video {
            sessionQueue.async { [weak self] in
                guard let self else { return }
                self.setTorch(self.torchEnabled)
            }
        }
    }

    func ensureTorchOff() {
        sessionQueue.async { [weak self] in
            self?.setTorch(false)
        }
    }

    private func setTorch(_ on: Bool) {
        guard let device = videoDeviceInput?.device,
              device.hasTorch,
              device.isTorchAvailable else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    // MARK: - Photo Capture

    func capturePhoto() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            let settings = AVCapturePhotoSettings()

            if let device = self.videoDeviceInput?.device,
               device.position == .back,
               self.photoOutput.supportedFlashModes.contains(.on),
               self.torchEnabled {
                settings.flashMode = .on
            }

            if self.livePhotoEnabled,
               self.photoOutput.isLivePhotoCaptureSupported {
                let movieURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("mov")
                settings.livePhotoMovieFileURL = movieURL
            }

            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: - Video Recording

    func startRecording() {
        guard !isRecording else { return }
        sessionQueue.async { [weak self] in
            guard let self, !self.movieOutput.isRecording else { return }

            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")

            if let connection = self.movieOutput.connection(with: .video) {
                connection.videoRotationAngle = 90
                if connection.isVideoMirroringSupported && self.currentPosition == .front {
                    connection.isVideoMirrored = true
                }
            }

            self.setTorch(self.torchEnabled)
            self.movieOutput.startRecording(to: outputURL, recordingDelegate: self)

            DispatchQueue.main.async {
                self.isRecording = true
                self.recordingStartTime = Date()
                self.recordingDuration = 0
                self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    guard let self, let start = self.recordingStartTime else { return }
                    self.recordingDuration = Date().timeIntervalSince(start)
                }
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        sessionQueue.async { [weak self] in
            self?.movieOutput.stopRecording()
            self?.setTorch(false)
        }
    }

    // MARK: - Timer

    private func cleanupRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingStartTime = nil
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CaptureService: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.capturedItems.append(.photo(image: image, assetIdentifier: nil))
            self.capturedCount = self.capturedItems.count
            self.onPhotoCaptured?(image)
            self.onThumbnailUpdated?(image)
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL,
        duration: CMTime,
        photoDisplayTime: CMTime,
        resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {}
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CaptureService: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let duration = self.recordingDuration
            self.isRecording = false
            self.cleanupRecordingTimer()

            if error == nil {
                self.capturedItems.append(.video(url: outputFileURL, duration: duration, assetIdentifier: nil))
                self.capturedCount = self.capturedItems.count
                self.onVideoCaptured?(outputFileURL, duration)

                if let thumb = self.generateVideoThumbnail(from: outputFileURL) {
                    self.onThumbnailUpdated?(thumb)
                }
            }
        }
    }

    private func generateVideoThumbnail(from url: URL) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 200, height: 200)
        guard let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
