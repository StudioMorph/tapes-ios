import AVFoundation
import OSLog

/// Renders a composition with the BlurredBackgroundCompositor baked in,
/// producing a clean intermediate .mp4 (H.264) that needs no custom
/// compositor for the final export pass. Runs entirely in-process so it
/// survives app suspension (the OS freezes / unfreezes the process).
final class BlurPrerenderer: @unchecked Sendable {

    private let log = Logger(subsystem: "com.studiomorph.tapes", category: "BlurPrerender")

    /// Written from the render queue, read from the main-thread progress timer.
    private(set) var progress: Float = 0
    private(set) var isCancelled = false
    private var reader: AVAssetReader?

    func cancel() {
        isCancelled = true
        reader?.cancelReading()
    }

    /// Pre-renders blur into an intermediate H.264 file.
    /// The intermediate is fast to encode and small on disk (heavy blur
    /// produces smooth gradients that compress extremely well).
    func prerender(
        composition: AVMutableComposition,
        videoComposition: AVMutableVideoComposition,
        audioMix: AVMutableAudioMix?,
        outputURL: URL
    ) async throws {
        let reader = try AVAssetReader(asset: composition)
        self.reader = reader

        // Video — composed through the blur compositor
        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: composition.tracks(withMediaType: .video),
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        videoOutput.videoComposition = videoComposition
        reader.add(videoOutput)

        // Audio — decoded to PCM so the mix (volume ramps, music) is applied
        let audioTracks = composition.tracks(withMediaType: .audio)
        let hasAudio = !audioTracks.isEmpty
        var audioOutput: AVAssetReaderAudioMixOutput?
        if hasAudio {
            let output = AVAssetReaderAudioMixOutput(
                audioTracks: audioTracks,
                audioSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 44100,
                    AVNumberOfChannelsKey: 2,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
            )
            if let audioMix { output.audioMix = audioMix }
            reader.add(output)
            audioOutput = output
        }

        // Writer — H.264 intermediate with quality-based encoding.
        // Heavy blur = smooth gradients = tiny files.
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let renderSize = videoComposition.renderSize

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(renderSize.width),
            AVVideoHeightKey: Int(renderSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoQualityKey: 0.8
            ]
        ])
        videoInput.expectsMediaDataInRealTime = false
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if hasAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000
            ])
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            audioInput = input
        }

        // Start pipeline
        guard reader.startReading() else {
            let msg = reader.error?.localizedDescription ?? "Unknown reader error"
            log.error("Reader failed to start: \(msg, privacy: .public)")
            throw PrerenderError.readerFailed(msg)
        }
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let totalSeconds = CMTimeGetSeconds(composition.duration)
        log.info("Pre-render starting: \(Int(renderSize.width))x\(Int(renderSize.height)), duration=\(totalSeconds)s")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let videoQueue = DispatchQueue(label: "tapes.prerender.video", qos: .userInitiated)
            let audioQueue = DispatchQueue(label: "tapes.prerender.audio", qos: .userInitiated)
            let lock = NSLock()
            var videoFinished = false
            var audioFinished = !hasAudio
            var resumed = false

            func completeIfReady() {
                lock.lock()
                defer { lock.unlock() }
                guard videoFinished, audioFinished, !resumed else { return }
                resumed = true

                if self.isCancelled {
                    reader.cancelReading()
                    writer.cancelWriting()
                    continuation.resume(throwing: PrerenderError.cancelled)
                    return
                }

                if reader.status == .failed {
                    let msg = reader.error?.localizedDescription ?? "Unknown reader error"
                    continuation.resume(throwing: PrerenderError.readerFailed(msg))
                    return
                }

                writer.finishWriting {
                    if writer.status == .failed {
                        let msg = writer.error?.localizedDescription ?? "Unknown writer error"
                        continuation.resume(throwing: PrerenderError.writerFailed(msg))
                    } else {
                        continuation.resume()
                    }
                }
            }

            // Video — each copyNextSampleBuffer invokes the blur compositor in-process
            videoInput.requestMediaDataWhenReady(on: videoQueue) { [weak self] in
                guard let self else { return }
                while videoInput.isReadyForMoreMediaData {
                    if self.isCancelled {
                        videoInput.markAsFinished()
                        lock.lock(); videoFinished = true; lock.unlock()
                        completeIfReady()
                        return
                    }
                    let sample: CMSampleBuffer? = autoreleasepool {
                        videoOutput.copyNextSampleBuffer()
                    }
                    guard let sample else {
                        videoInput.markAsFinished()
                        lock.lock(); videoFinished = true; lock.unlock()
                        completeIfReady()
                        return
                    }
                    videoInput.append(sample)

                    if totalSeconds > 0 {
                        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                        self.progress = Float(CMTimeGetSeconds(pts) / totalSeconds)
                    }
                }
            }

            // Audio
            if let audioOutput, let audioInput {
                audioInput.requestMediaDataWhenReady(on: audioQueue) { [weak self] in
                    guard let self else { return }
                    while audioInput.isReadyForMoreMediaData {
                        if self.isCancelled {
                            audioInput.markAsFinished()
                            lock.lock(); audioFinished = true; lock.unlock()
                            completeIfReady()
                            return
                        }
                        guard let sample = audioOutput.copyNextSampleBuffer() else {
                            audioInput.markAsFinished()
                            lock.lock(); audioFinished = true; lock.unlock()
                            completeIfReady()
                            return
                        }
                        audioInput.append(sample)
                    }
                }
            }
        }

        progress = 1.0
        log.info("Pre-render complete")
    }

    // MARK: - Errors

    enum PrerenderError: LocalizedError {
        case readerFailed(String)
        case writerFailed(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .readerFailed(let msg): return "Pre-render failed: \(msg)"
            case .writerFailed(let msg): return "Pre-render write failed: \(msg)"
            case .cancelled: return "Export was cancelled."
            }
        }
    }
}
