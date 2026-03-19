import Foundation
import AVFoundation
import Photos
import OSLog

private let log = Logger(subsystem: "com.studiomorph.tapes", category: "Export")

public final class TapeExportSession: @unchecked Sendable {

    private(set) var avExportSession: AVAssetExportSession?
    private(set) var isCancelled = false

    var sessionProgress: Float {
        avExportSession?.progress ?? 0
    }

    func cancel() {
        isCancelled = true
        avExportSession?.cancelExport()
    }

    func run(tape: Tape) async throws -> (url: URL, assetIdentifier: String?) {
        guard !tape.clips.isEmpty else {
            throw ExportError.noClips
        }

        let builder = TapeCompositionBuilder(
            imageConfiguration: .export,
            videoDeliveryMode: .automatic
        )
        let components = try await builder.buildExportComposition(for: tape)

        guard !isCancelled else { throw ExportError.exportCancelled }

        let composition = components.composition
        var allAudioParams = components.audioMix?.inputParameters ?? []
        let totalDuration = components.timeline.totalDuration

        if tape.musicMood != .none {
            let musicURL = await MubertAPIClient.shared.cachedTrackURL(for: tape.id)
            if let musicURL {
                try Self.addBackgroundMusic(
                    to: composition,
                    musicURL: musicURL,
                    volume: tape.musicVolume,
                    totalDuration: totalDuration,
                    audioParams: &allAudioParams
                )
            } else {
                log.warning("No cached music track, skipping music")
            }
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = allAudioParams

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Tape_\(UUID().uuidString).mp4")

        log.info("Starting export: \(tape.clips.count) clips, duration=\(CMTimeGetSeconds(totalDuration))s")

        guard !isCancelled else { throw ExportError.exportCancelled }

        try await runExportSession(
            asset: composition,
            videoComposition: components.videoComposition,
            audioMix: audioMix,
            outputURL: outURL
        )

        log.info("Export session complete, saving to Photos")

        let assetIdentifier = try await Self.saveToPhotos(url: outURL)

        return (outURL, assetIdentifier)
    }

    // MARK: - Background Music

    private static func addBackgroundMusic(
        to composition: AVMutableComposition,
        musicURL: URL,
        volume: Float,
        totalDuration: CMTime,
        audioParams: inout [AVAudioMixInputParameters]
    ) throws {
        let musicAsset = AVURLAsset(url: musicURL)
        guard let musicSourceTrack = musicAsset.tracks(withMediaType: .audio).first else {
            log.warning("Music file has no audio track, skipping")
            return
        }

        guard let musicTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            log.warning("Could not add music track to composition, skipping")
            return
        }

        let musicDuration = musicAsset.duration
        var cursor = CMTime.zero

        while CMTimeCompare(cursor, totalDuration) < 0 {
            let remaining = CMTimeSubtract(totalDuration, cursor)
            let insertDuration = CMTimeMinimum(musicDuration, remaining)
            let insertRange = CMTimeRange(start: .zero, duration: insertDuration)
            try? musicTrack.insertTimeRange(insertRange, of: musicSourceTrack, at: cursor)
            cursor = CMTimeAdd(cursor, insertDuration)
        }

        let musicParams = AVMutableAudioMixInputParameters(track: musicTrack)
        musicParams.setVolume(volume, at: .zero)

        let fadeOutDuration = CMTime(seconds: 1.5, preferredTimescale: 600)
        if CMTimeCompare(totalDuration, fadeOutDuration) > 0 {
            let fadeStart = CMTimeSubtract(totalDuration, fadeOutDuration)
            musicParams.setVolumeRamp(
                fromStartVolume: volume,
                toEndVolume: 0,
                timeRange: CMTimeRange(start: fadeStart, duration: fadeOutDuration)
            )
        }

        audioParams.append(musicParams)
        log.info("Added background music: volume=\(volume), looped to \(CMTimeGetSeconds(totalDuration))s")
    }

    // MARK: - Export Session

    private func runExportSession(
        asset: AVMutableComposition,
        videoComposition: AVMutableVideoComposition,
        audioMix: AVMutableAudioMix,
        outputURL: URL
    ) async throws {
        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHEVC1920x1080
        ) else {
            throw ExportError.exportSessionUnavailable
        }

        self.avExportSession = session

        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.videoComposition = videoComposition
        session.audioMix = audioMix

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously {
                continuation.resume()
            }
        }

        switch session.status {
        case .completed:
            return
        case .failed:
            let message = session.error?.localizedDescription ?? "Unknown error"
            log.error("Export failed: \(message)")
            throw ExportError.exportFailed(message)
        case .cancelled:
            throw ExportError.exportCancelled
        default:
            throw ExportError.exportFailed("Unexpected status: \(session.status.rawValue)")
        }
    }

    // MARK: - Save to Photos

    private static func saveToPhotos(url: URL) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            var placeholderIdentifier: String?
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                placeholderIdentifier = request?.placeholderForCreatedAsset?.localIdentifier
            }) { success, error in
                if success {
                    continuation.resume(returning: placeholderIdentifier)
                } else {
                    let message = error?.localizedDescription ?? "Unknown Photos error"
                    log.error("Failed to save to Photos: \(message)")
                    continuation.resume(throwing: ExportError.saveToPhotosFailed(message))
                }
            }
        }
    }

    // MARK: - Errors

    enum ExportError: LocalizedError {
        case noClips
        case exportSessionUnavailable
        case exportFailed(String)
        case exportCancelled
        case saveToPhotosFailed(String)

        var errorDescription: String? {
            switch self {
            case .noClips:
                return "Tape has no clips to export."
            case .exportSessionUnavailable:
                return "Could not create export session."
            case .exportFailed(let message):
                return "Export failed: \(message)"
            case .exportCancelled:
                return "Export was cancelled."
            case .saveToPhotosFailed(let message):
                return "Failed to save to Photos: \(message)"
            }
        }
    }
}
