import AVFoundation
import OSLog
import SwiftUI

private let log = TapesLog.music

@MainActor
final class TrackGenerationManager: ObservableObject {

    enum State: Equatable {
        case idle
        case generating
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var isPreviewing = false

    private var generationTask: Task<Void, Never>?
    private var previewPlayer: AVAudioPlayer?
    private var cachedTrackURL: URL?
    private var tapeID: UUID?

    // MARK: - Generate

    func generate(mood: MubertAPIClient.Mood, tapeID: UUID, api: TapesAPIClient) {
        cancel()
        self.tapeID = tapeID

        guard mood != .none else {
            state = .idle
            progress = 0
            return
        }

        state = .generating
        progress = 0

        generationTask = Task {
            do {
                let url = try await MubertAPIClient.shared.generateTrack(
                    mood: mood,
                    tapeID: tapeID,
                    api: api,
                    onProgress: { [weak self] fraction in
                        Task { @MainActor [weak self] in
                            self?.progress = fraction
                        }
                    }
                )

                guard !Task.isCancelled else { return }

                self.cachedTrackURL = url
                self.state = .ready
                self.progress = 1.0
                log.info("Track generation complete for tape=\(tapeID.uuidString.prefix(8))")
            } catch {
                guard !Task.isCancelled else { return }
                self.state = .failed(error.localizedDescription)
                log.error("Track generation failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Regenerate

    func regenerate(mood: MubertAPIClient.Mood, tapeID: UUID, api: TapesAPIClient) {
        stopPreview()
        Task {
            await MubertAPIClient.shared.clearCache(for: tapeID)
        }
        cachedTrackURL = nil
        generate(mood: mood, tapeID: tapeID, api: api)
    }

    // MARK: - Cancel

    func cancel() {
        generationTask?.cancel()
        generationTask = nil
        stopPreview()
        state = .idle
        progress = 0
        cachedTrackURL = nil
    }

    // MARK: - Preview

    func togglePreview(volume: Float = 0.8) {
        if isPreviewing {
            stopPreview()
        } else {
            startPreview(volume: volume)
        }
    }

    private func startPreview(volume: Float) {
        guard let url = cachedTrackURL else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = volume
            player.prepareToPlay()
            player.play()

            previewPlayer = player
            isPreviewing = true
            log.info("Preview started at volume=\(volume)")
        } catch {
            log.error("Preview failed: \(error.localizedDescription)")
        }
    }

    func stopPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
        isPreviewing = false
    }

    func updatePreviewVolume(_ volume: Float) {
        previewPlayer?.volume = volume
    }

    // MARK: - Query

    var isGenerating: Bool { state == .generating }
    var isReady: Bool { state == .ready }

    var trackURL: URL? { cachedTrackURL }

    /// Checks if this tape already has a cached track on disk.
    func loadCachedState(for tapeID: UUID) {
        self.tapeID = tapeID
        Task {
            if let url = await MubertAPIClient.shared.cachedTrackURL(for: tapeID) {
                self.cachedTrackURL = url
                self.state = .ready
                self.progress = 1.0
            }
        }
    }
}
