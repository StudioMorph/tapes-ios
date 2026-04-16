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

    enum CaptureMode: String, CaseIterable {
        case photo = "Photo"
        case video = "Video"
    }

    // MARK: - Session

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.studiomorph.tapes.capture")

    private var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()

    private var recordingTimer: Timer?
    private var recordingStartTime: Date?

    var onPhotoCaptured: ((UIImage) -> Void)?
    var onVideoCaptured: ((URL, TimeInterval) -> Void)?

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

    // MARK: - Session Configuration

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        guard let videoDevice = wideAngleDevice(for: .back) else {
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
        }

        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
            if let connection = movieOutput.connection(with: .video),
               connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
            }
        }

        session.commitConfiguration()
    }

    /// Explicitly request the wide-angle lens to avoid the slow
    /// dual/triple camera negotiation that plagues UIImagePickerController.
    private func wideAngleDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    // MARK: - Camera Switch

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let newPosition: AVCaptureDevice.Position = self.currentPosition == .back ? .front : .back
            guard let newDevice = self.wideAngleDevice(for: newPosition) else { return }

            self.session.beginConfiguration()

            if let current = self.videoDeviceInput {
                self.session.removeInput(current)
            }

            do {
                let newInput = try AVCaptureDeviceInput(device: newDevice)
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

            DispatchQueue.main.async {
                self.currentPosition = newPosition
                self.torchEnabled = false
            }
        }
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

    // MARK: - Torch

    private func setTorch(_ on: Bool) {
        guard let device = videoDeviceInput?.device,
              device.hasTorch,
              device.isTorchAvailable else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
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
            self?.onPhotoCaptured?(image)
        }
    }
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
                self.onVideoCaptured?(outputFileURL, duration)
            }
        }
    }
}
