import Foundation
import AVFoundation
import Photos
import OSLog

private let log = Logger(subsystem: "com.studiomorph.tapes", category: "Export")

public final class TapeExportSession: @unchecked Sendable {

    private(set) var isCancelled = false
    private var _progress: Float = 0
    private var reader: AVAssetReader?

    var sessionProgress: Float { _progress }

    func cancel() {
        isCancelled = true
        reader?.cancelReading()
        reader = nil
    }

    func run(tape: Tape) async throws -> (url: URL, assetIdentifier: String?) {
        guard !tape.clips.isEmpty else {
            throw ExportError.noClips
        }

        Self.cleanUpStaleExportFiles()

        let builder = TapeCompositionBuilder(
            imageConfiguration: .export,
            videoDeliveryMode: .highQualityFormat,
            livePhotosAsVideo: tape.livePhotosAsVideo,
            livePhotosMuted: tape.livePhotosMuted
        )
        let components = try await builder.buildExportComposition(for: tape)

        guard !isCancelled else { throw ExportError.exportCancelled }

        let composition = components.composition
        var allAudioParams = components.audioMix?.inputParameters ?? []
        let totalDuration = components.timeline.totalDuration

        log.info("Composition built: videoTracks=\(composition.tracks(withMediaType: .video).count), audioTracks=\(composition.tracks(withMediaType: .audio).count), audioMixParams=\(allAudioParams.count), musicMood=\(tape.musicMood.rawValue)")
        for (i, clip) in tape.clips.enumerated() {
            let kind = clip.isLivePhoto ? "livePhoto" : (clip.assetLocalId != nil ? "photo/video" : "image")
            log.info("  clip[\(i)] kind=\(kind), isLivePhoto=\(clip.isLivePhoto), duration=\(clip.duration)s, assetId=\(clip.assetLocalId ?? "nil")")
        }

        if tape.musicMood != .none {
            let musicURL = await MubertAPIClient.shared.cachedTrackURL(for: tape.id)
            if let musicURL {
                try await Self.addBackgroundMusic(
                    to: composition,
                    musicURL: musicURL,
                    tapeVolume: tape.musicVolume,
                    clips: tape.clips,
                    segments: components.timeline.segments,
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

        let renderSize = components.videoComposition.renderSize
        log.info("Starting export: \(tape.clips.count) clips, duration=\(CMTimeGetSeconds(totalDuration))s, size=\(Int(renderSize.width))x\(Int(renderSize.height))")

        guard !isCancelled else { throw ExportError.exportCancelled }

        try await runReaderWriter(
            asset: composition,
            videoComposition: components.videoComposition,
            audioMix: audioMix,
            totalDuration: totalDuration,
            outputURL: outURL
        )

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: outURL.path)[.size] as? Int) ?? 0
        log.info("Export complete, file size=\(fileSize) bytes, saving to Photos")

        let assetIdentifier = try await Self.saveToPhotos(url: outURL)
        log.info("Saved to Photos, assetIdentifier=\(assetIdentifier ?? "nil")")

        return (outURL, assetIdentifier)
    }

    // MARK: - Background Music

    private static func addBackgroundMusic(
        to composition: AVMutableComposition,
        musicURL: URL,
        tapeVolume: Float,
        clips: [Clip],
        segments: [TapeCompositionBuilder.Segment],
        totalDuration: CMTime,
        audioParams: inout [AVAudioMixInputParameters]
    ) async throws {
        let musicAsset = AVURLAsset(url: musicURL)
        let audioTracks = try await musicAsset.loadTracks(withMediaType: .audio)
        guard let musicSourceTrack = audioTracks.first else {
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

        let musicDuration = try await musicAsset.load(.duration)
        var cursor = CMTime.zero

        while CMTimeCompare(cursor, totalDuration) < 0 {
            let remaining = CMTimeSubtract(totalDuration, cursor)
            let insertDuration = CMTimeMinimum(musicDuration, remaining)
            let insertRange = CMTimeRange(start: .zero, duration: insertDuration)
            try? musicTrack.insertTimeRange(insertRange, of: musicSourceTrack, at: cursor)
            cursor = CMTimeAdd(cursor, insertDuration)
        }

        let musicParams = AVMutableAudioMixInputParameters(track: musicTrack)

        for segment in segments {
            let clipIndex = segment.clipIndex
            let effectiveVol = clipIndex < clips.count ? Float(clips[clipIndex].musicVolume ?? Double(tapeVolume)) : tapeVolume
            musicParams.setVolume(effectiveVol, at: segment.timeRange.start)
        }

        let fadeOutDuration = CMTime(seconds: 1.5, preferredTimescale: 600)
        if CMTimeCompare(totalDuration, fadeOutDuration) > 0 {
            let fadeStart = CMTimeSubtract(totalDuration, fadeOutDuration)
            let lastVol = segments.last.map { seg in
                let idx = seg.clipIndex
                return idx < clips.count ? Float(clips[idx].musicVolume ?? Double(tapeVolume)) : tapeVolume
            } ?? tapeVolume
            musicParams.setVolumeRamp(
                fromStartVolume: lastVol,
                toEndVolume: 0,
                timeRange: CMTimeRange(start: fadeStart, duration: fadeOutDuration)
            )
        }

        audioParams.append(musicParams)
        log.info("Added background music: tapeVolume=\(tapeVolume), per-clip volumes applied, looped to \(CMTimeGetSeconds(totalDuration))s")
    }

    // MARK: - Reader/Writer Export

    private func runReaderWriter(
        asset: AVMutableComposition,
        videoComposition: AVMutableVideoComposition,
        audioMix: AVMutableAudioMix,
        totalDuration: CMTime,
        outputURL: URL
    ) async throws {
        let renderSize = videoComposition.renderSize

        let assetReader = try AVAssetReader(asset: asset)
        self.reader = assetReader

        let videoTracks = asset.tracks(withMediaType: .video)
        let audioTracks = asset.tracks(withMediaType: .audio)
        log.info("Composition has \(videoTracks.count) video track(s), \(audioTracks.count) audio track(s)")

        for (i, vt) in videoTracks.enumerated() {
            let fds = vt.formatDescriptions as? [CMFormatDescription] ?? []
            log.info("  videoTrack[\(i)] id=\(vt.trackID), segments=\(vt.segments.count), formatDescriptions=\(fds.count)")
        }
        for (i, at) in audioTracks.enumerated() {
            let fds = at.formatDescriptions as? [CMFormatDescription] ?? []
            let fdDetails = fds.map { fd -> String in
                let mediaType = CMFormatDescriptionGetMediaType(fd)
                let mediaSubType = CMFormatDescriptionGetMediaSubType(fd)
                let fourCC = String(format: "%c%c%c%c",
                    (mediaSubType >> 24) & 0xFF,
                    (mediaSubType >> 16) & 0xFF,
                    (mediaSubType >> 8) & 0xFF,
                    mediaSubType & 0xFF)
                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee {
                    return "type=\(mediaType) subtype=\(fourCC) sampleRate=\(asbd.mSampleRate) channels=\(asbd.mChannelsPerFrame) bitsPerCh=\(asbd.mBitsPerChannel) formatID=\(asbd.mFormatID)"
                }
                return "type=\(mediaType) subtype=\(fourCC) (no ASBD)"
            }
            let tr = at.timeRange
            let trDesc = "start=\(CMTimeGetSeconds(tr.start))s, dur=\(CMTimeGetSeconds(tr.duration))s"
            log.info("  audioTrack[\(i)] id=\(at.trackID), segments=\(at.segments.count), timeRange=[\(trDesc)], formatDescriptions=\(fdDetails)")
        }
        log.info("  audioMix.inputParameters count=\(audioMix.inputParameters.count)")

        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: videoTracks,
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        videoOutput.videoComposition = videoComposition
        guard assetReader.canAdd(videoOutput) else {
            throw ExportError.exportFailed("Cannot add video output to reader")
        }
        assetReader.add(videoOutput)

        var audioOutput: AVAssetReaderAudioMixOutput?
        let populatedAudioTracks = audioTracks.filter { !(($0.formatDescriptions as? [CMFormatDescription]) ?? []).isEmpty }
        log.info("  Populated audio tracks (with format descriptions): \(populatedAudioTracks.count) of \(audioTracks.count)")

        if !populatedAudioTracks.isEmpty {
            let ao = AVAssetReaderAudioMixOutput(
                audioTracks: populatedAudioTracks,
                audioSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
            )
            ao.audioMix = audioMix
            let canAddAudio = assetReader.canAdd(ao)
            log.info("  canAdd audioMixOutput=\(canAddAudio)")
            if canAddAudio {
                assetReader.add(ao)
                audioOutput = ao
            } else {
                log.warning("  Skipping audio output — reader cannot add it")
            }
        } else {
            log.info("  No populated audio tracks, skipping audio reader")
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(renderSize.width),
            AVVideoHeightKey: Int(renderSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 10_000_000,
                AVVideoExpectedSourceFrameRateKey: 30
            ]
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else {
            throw ExportError.exportFailed("Cannot add video input to writer")
        }
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44100,
                AVEncoderBitRateKey: 128_000
            ]
            let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            ai.expectsMediaDataInRealTime = false
            if writer.canAdd(ai) {
                writer.add(ai)
                audioInput = ai
            }
        }

        log.info("About to call assetReader.startReading(), status=\(assetReader.status.rawValue)")
        guard assetReader.startReading() else {
            let readerErr = assetReader.error
            let message = readerErr?.localizedDescription ?? "Unknown reader error"
            let nsErr = readerErr as NSError?
            log.error("Reader failed to start: \(message), domain=\(nsErr?.domain ?? "nil"), code=\(nsErr?.code ?? 0), underlyingError=\(nsErr?.userInfo[NSUnderlyingErrorKey].map { String(describing: $0) } ?? "nil")")
            throw ExportError.exportFailed("Reader failed to start: \(message)")
        }
        guard writer.startWriting() else {
            let message = writer.error?.localizedDescription ?? "Unknown writer error"
            throw ExportError.exportFailed("Writer failed to start: \(message)")
        }
        writer.startSession(atSourceTime: .zero)

        let totalSeconds = CMTimeGetSeconds(totalDuration)

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    while !self.isCancelled {
                        if !videoInput.isReadyForMoreMediaData {
                            try await Task.sleep(nanoseconds: 10_000_000)
                            continue
                        }
                        guard let buffer = videoOutput.copyNextSampleBuffer() else { break }
                        videoInput.append(buffer)

                        if totalSeconds > 0 {
                            let pts = CMSampleBufferGetPresentationTimeStamp(buffer)
                            self._progress = Float(CMTimeGetSeconds(pts) / totalSeconds)
                        }
                    }
                    videoInput.markAsFinished()
                }

                if let audioOutput, let audioInput {
                    group.addTask {
                        while !self.isCancelled {
                            if !audioInput.isReadyForMoreMediaData {
                                try await Task.sleep(nanoseconds: 10_000_000)
                                continue
                            }
                            guard let buffer = audioOutput.copyNextSampleBuffer() else { break }
                            audioInput.append(buffer)
                        }
                        audioInput.markAsFinished()
                    }
                }

                try await group.waitForAll()
            }
        } catch {
            assetReader.cancelReading()
            writer.cancelWriting()
            self.reader = nil
            throw error
        }

        guard !isCancelled else {
            assetReader.cancelReading()
            writer.cancelWriting()
            self.reader = nil
            throw ExportError.exportCancelled
        }

        if assetReader.status == .failed {
            let message = assetReader.error?.localizedDescription ?? "Unknown reader error"
            writer.cancelWriting()
            self.reader = nil
            throw ExportError.exportFailed("Reader failed: \(message)")
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                continuation.resume()
            }
        }

        self.reader = nil

        guard writer.status == .completed else {
            let message = writer.error?.localizedDescription ?? "Unknown writer error"
            throw ExportError.exportFailed("Writer failed: \(message)")
        }

        self._progress = 1.0
    }

    // MARK: - Save to Photos

    private static let maxSaveRetries = 3
    private static let saveRetryDelay: UInt64 = 2_000_000_000 // 2 seconds

    private static func saveToPhotos(url: URL) async throws -> String? {
        var lastError: Error?

        for attempt in 1...maxSaveRetries {
            do {
                let identifier = try await attemptSaveToPhotos(url: url)
                if attempt > 1 {
                    log.info("Save to Photos succeeded on attempt \(attempt)")
                }
                return identifier
            } catch {
                lastError = error
                log.error("Save to Photos attempt \(attempt)/\(maxSaveRetries) failed: \(error.localizedDescription, privacy: .public)")
                if attempt < maxSaveRetries {
                    try? await Task.sleep(nanoseconds: saveRetryDelay)
                }
            }
        }

        throw lastError ?? ExportError.saveToPhotosFailed("All save attempts failed")
    }

    private static func attemptSaveToPhotos(url: URL) async throws -> String? {
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

    // MARK: - Temp File Cleanup

    static func cleanUpStaleExportFiles() {
        let tmpDir = FileManager.default.temporaryDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: tmpDir, includingPropertiesForKeys: nil
        ) else { return }

        for file in contents where file.lastPathComponent.hasPrefix("Tape_") && file.pathExtension == "mp4" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: - Errors

    enum ExportError: LocalizedError {
        case noClips
        case exportFailed(String)
        case exportCancelled
        case saveToPhotosFailed(String)

        var errorDescription: String? {
            switch self {
            case .noClips:
                return "Tape has no clips to export."
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
