import AVFoundation
import SwiftUI

@MainActor
final class MusicPreviewManager: ObservableObject {

    @Published private(set) var previewingTapeID: UUID?
    @Published private(set) var audioLevel: CGFloat = 0

    private var audioPlayer: AVAudioPlayer?
    private var meterTimer: Timer?

    var isPreviewingTape: UUID? { previewingTapeID }

    func isActive(for tapeID: UUID) -> Bool {
        previewingTapeID == tapeID
    }

    func toggle(tapeID: UUID, cachedURL: URL?, volume: Float) {
        if previewingTapeID == tapeID {
            stop()
            return
        }

        stop()

        guard let url = cachedURL else { return }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = volume
            player.isMeteringEnabled = true
            player.prepareToPlay()
            player.play()
            audioPlayer = player
            previewingTapeID = tapeID
            startMeterPolling()
        } catch {
            TapesLog.music.error("Preview failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        meterTimer?.invalidate()
        meterTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        previewingTapeID = nil
        audioLevel = 0
    }

    func stopIfActive(for tapeID: UUID) {
        guard previewingTapeID == tapeID else { return }
        stop()
    }

    private func startMeterPolling() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.audioPlayer, player.isPlaying else { return }
                player.updateMeters()
                let power = player.averagePower(forChannel: 0)
                self.audioLevel = CGFloat(max(0, min(1, (power + 50) / 50)))
            }
        }
    }
}
