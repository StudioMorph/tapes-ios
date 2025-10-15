import Foundation
import AVFoundation
import Photos
import CoreGraphics

/// Builds timeline metadata for tape playback using AVComposable assets.
/// The builder does not mutate the UI; it prepares the information required to render transitions.
struct TapeCompositionBuilder {

    // MARK: - Nested Types

    enum BuilderError: Error, LocalizedError {
        case unsupportedClipType(ClipType)
        case assetUnavailable(clipID: UUID)
        case photosAccessDenied
        case photosAssetMissing
        case missingVideoTrack

        var errorDescription: String? {
            switch self {
            case .unsupportedClipType(let type):
                return "Unsupported clip type for composition: \(type)"
            case .assetUnavailable(let clipID):
                return "Unable to resolve AVAsset for clip \(clipID)"
            case .photosAccessDenied:
                return "Photos access denied."
            case .photosAssetMissing:
                return "Requested Photos asset could not be found."
            case .missingVideoTrack:
                return "Video track is missing from the resolved asset."
            }
        }
    }

    struct TransitionDescriptor {
        let style: TransitionType
        let duration: CMTime
    }

    struct ClipAssetContext {
        let index: Int
        let clip: Clip
        let asset: AVAsset
        let duration: CMTime
        let naturalSize: CGSize
        let preferredTransform: CGAffineTransform
        let hasAudio: Bool
        let videoTrack: AVAssetTrack
        let audioTrack: AVAssetTrack?
    }

    struct Segment {
        let clipIndex: Int
        let assetContext: ClipAssetContext
        let timeRange: CMTimeRange
        let incomingTransition: TransitionDescriptor?
        let outgoingTransition: TransitionDescriptor?
    }

    struct Timeline {
        let segments: [Segment]
        let renderSize: CGSize
        let totalDuration: CMTime
        let transitionSequence: [TransitionDescriptor?] // matches clip boundaries (count = clips.count - 1)
    }

    struct PlayerComposition {
        let playerItem: AVPlayerItem
        let timeline: Timeline
    }

    // MARK: - Public API

    func prepareTimeline(for tape: Tape) async throws -> Timeline {
        guard !tape.clips.isEmpty else {
            return Timeline(
                segments: [],
                renderSize: renderSize(for: tape.orientation),
                totalDuration: .zero,
                transitionSequence: []
            )
        }

        let assetContexts = try await loadAssets(for: tape.clips)
        let transitionDescriptors = buildTransitionDescriptors(for: tape, assets: assetContexts)
        let segments = buildSegments(for: assetContexts, transitions: transitionDescriptors)

        let totalDuration = segments.last.map { CMTimeAdd($0.timeRange.start, $0.timeRange.duration) } ?? .zero

        return Timeline(
            segments: segments,
            renderSize: renderSize(for: tape.orientation),
            totalDuration: totalDuration,
            transitionSequence: transitionDescriptors
        )
    }

    @MainActor
    func buildPlayerItem(for tape: Tape) async throws -> PlayerComposition {
        let timeline = try await prepareTimeline(for: tape)
        let composition = AVMutableComposition()

        let videoTracks = try createCompositionTracks(for: composition, mediaType: .video)
        let audioTracks = try createCompositionTracks(for: composition, mediaType: .audio)

        var videoTrackMap: [Int: AVMutableCompositionTrack] = [:]
        var audioTrackMap: [Int: AVMutableCompositionTrack] = [:]

        var audioMixParameters: [CMPersistentTrackID: AVMutableAudioMixInputParameters] = [:]

        for segment in timeline.segments {
            let trackIndex = segment.clipIndex % videoTracks.count
            let videoTrack = videoTracks[trackIndex]
            let sourceRange = CMTimeRange(start: .zero, duration: segment.assetContext.duration)
            try videoTrack.insertTimeRange(sourceRange, of: segment.assetContext.videoTrack, at: segment.timeRange.start)
            videoTrackMap[segment.clipIndex] = videoTrack

            if segment.assetContext.hasAudio,
               let sourceAudioTrack = segment.assetContext.audioTrack,
               trackIndex < audioTracks.count {
                let audioTrack = audioTracks[trackIndex]
                try audioTrack.insertTimeRange(sourceRange, of: sourceAudioTrack, at: segment.timeRange.start)
                audioTrackMap[segment.clipIndex] = audioTrack

                let key = audioTrack.trackID
                let params = audioMixParameters[key] ?? AVMutableAudioMixInputParameters(track: audioTrack)
                params.setVolume(1.0, at: segment.timeRange.start)

                if let incoming = segment.incomingTransition, incoming.style == .crossfade {
                    let rampRange = CMTimeRange(start: segment.timeRange.start, duration: incoming.duration)
                    params.setVolumeRamp(fromStartVolume: 0, toEndVolume: 1, timeRange: rampRange)
                }
                if let outgoing = segment.outgoingTransition, outgoing.style == .crossfade {
                    let rampStart = CMTimeSubtract(CMTimeAdd(segment.timeRange.start, segment.timeRange.duration), outgoing.duration)
                    let rampRange = CMTimeRange(start: rampStart, duration: outgoing.duration)
                    params.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0, timeRange: rampRange)
                }

                audioMixParameters[key] = params
            }
        }

        let instructions = buildVideoInstructions(
            for: timeline,
            videoTrackMap: videoTrackMap,
            renderSize: timeline.renderSize,
            tapeScaleMode: tape.scaleMode
        )

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = instructions
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.renderSize = timeline.renderSize

        let playerItem = AVPlayerItem(asset: composition)
        playerItem.videoComposition = videoComposition

        if !audioMixParameters.isEmpty {
            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = Array(audioMixParameters.values)
            playerItem.audioMix = audioMix
        }

        return PlayerComposition(playerItem: playerItem, timeline: timeline)
    }

    // MARK: - Asset Loading

    private func loadAssets(for clips: [Clip]) async throws -> [ClipAssetContext] {
        try await withThrowingTaskGroup(of: ClipAssetContext.self) { group in
            for (index, clip) in clips.enumerated() {
                group.addTask {
                    let asset = try await resolveAsset(for: clip)
                    guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                        throw BuilderError.missingVideoTrack
                    }
                    let duration = try await asset.load(.duration)
                    let naturalSize = try await videoTrack.load(.naturalSize)
                    let preferredTransform = try await videoTrack.load(.preferredTransform)
                    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
                    let audioTrack = audioTracks.first
                    let hasAudio = !audioTracks.isEmpty
                    return ClipAssetContext(
                        index: index,
                        clip: clip,
                        asset: asset,
                        duration: duration,
                        naturalSize: naturalSize,
                        preferredTransform: preferredTransform,
                        hasAudio: hasAudio,
                        videoTrack: videoTrack,
                        audioTrack: audioTrack
                    )
                }
            }

            var contexts: [ClipAssetContext] = []
            for try await context in group {
                contexts.append(context)
            }

            return contexts.sorted { $0.index < $1.index }
        }
    }

    private func resolveAsset(for clip: Clip) async throws -> AVAsset {
        switch clip.clipType {
        case .video:
            if let url = clip.localURL {
                return AVURLAsset(url: url)
            }
            if let assetLocalId = clip.assetLocalId {
                return try await fetchAVAssetFromPhotos(localIdentifier: assetLocalId)
            }
            throw BuilderError.assetUnavailable(clipID: clip.id)
        case .image:
            throw BuilderError.unsupportedClipType(.image)
        }
    }

    private func fetchAVAssetFromPhotos(localIdentifier: String) async throws -> AVAsset {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw BuilderError.photosAccessDenied
        }

        return try await withCheckedThrowingContinuation { continuation in
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
            guard let phAsset = fetchResult.firstObject else {
                continuation.resume(throwing: BuilderError.photosAssetMissing)
                return
            }

            let options = PHVideoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { asset, _, _ in
                if let asset = asset {
                    continuation.resume(returning: asset)
                } else {
                    continuation.resume(throwing: BuilderError.assetUnavailable(clipID: UUID()))
                }
            }
        }
    }

    // MARK: - Transition Handling

    private func buildTransitionDescriptors(for tape: Tape, assets: [ClipAssetContext]) -> [TransitionDescriptor?] {
        guard assets.count > 1 else { return [] }

        let baseStyle = tape.transition
        let styles: [TransitionType]
        switch baseStyle {
        case .none, .crossfade, .slideLR, .slideRL:
            styles = Array(repeating: baseStyle, count: assets.count - 1)
        case .randomise:
            styles = generateRandomSequence(boundaries: assets.count - 1, tapeID: tape.id)
        }

        var descriptors: [TransitionDescriptor?] = []
        descriptors.reserveCapacity(styles.count)

        for index in 0..<styles.count {
            let style = styles[index]
            if style == .none {
                descriptors.append(nil)
                continue
            }

            let currentAsset = assets[index]
            let nextAsset = assets[index + 1]

            let maxDurationCurrent = CMTimeMultiplyByFloat64(currentAsset.duration, multiplier: 0.5)
            let maxDurationNext = CMTimeMultiplyByFloat64(nextAsset.duration, multiplier: 0.5)
            let rawDuration = CMTime(seconds: tape.transitionDuration, preferredTimescale: 600)
            let capped = minTime(rawDuration, maxDurationCurrent, maxDurationNext)
            if CMTimeCompare(capped, .zero) <= 0 {
                descriptors.append(nil)
            } else {
                descriptors.append(TransitionDescriptor(style: style, duration: capped))
            }
        }

        return descriptors
    }

    private func buildSegments(for assets: [ClipAssetContext], transitions: [TransitionDescriptor?]) -> [Segment] {
        var segments: [Segment] = []
        segments.reserveCapacity(assets.count)

        var currentStart = CMTime.zero

        for index in 0..<assets.count {
            let assetContext = assets[index]
            let incomingTransition = index > 0 ? transitions[index - 1] : nil
            let outgoingTransition = index < transitions.count ? transitions[index] : nil

            let duration = assetContext.duration
            let timeRange = CMTimeRange(start: currentStart, duration: duration)

            let segment = Segment(
                clipIndex: index,
                assetContext: assetContext,
                timeRange: timeRange,
                incomingTransition: incomingTransition,
                outgoingTransition: outgoingTransition
            )
            segments.append(segment)

            if let outgoing = outgoingTransition {
                currentStart = CMTimeAdd(currentStart, duration)
                currentStart = CMTimeSubtract(currentStart, outgoing.duration)
            } else {
                currentStart = CMTimeAdd(currentStart, duration)
            }
        }

        return segments
    }

    private func generateRandomSequence(boundaries: Int, tapeID: UUID) -> [TransitionType] {
        guard boundaries > 0 else { return [] }
        var generator = SeededGenerator(seed: UInt64(bitPattern: Int64(tapeID.hashValue)))
        let pool: [TransitionType] = [.none, .crossfade, .slideLR, .slideRL]
        return (0..<boundaries).map { _ in pool.randomElement(using: &generator)! }
    }

    // MARK: - Helpers

    private func renderSize(for orientation: TapeOrientation) -> CGSize {
        switch orientation {
        case .portrait:
            return CGSize(width: 1080, height: 1920)
        case .landscape:
            return CGSize(width: 1920, height: 1080)
        }
    }

    private func minTime(_ values: CMTime...) -> CMTime {
        guard var minimum = values.first else { return .zero }
        for value in values.dropFirst() {
            if CMTimeCompare(value, minimum) < 0 {
                minimum = value
            }
        }
        return minimum
    }

    private func createCompositionTracks(for composition: AVMutableComposition, mediaType: AVMediaType) throws -> [AVMutableCompositionTrack] {
        var tracks: [AVMutableCompositionTrack] = []
        let trackCount = 2
        for _ in 0..<trackCount {
            if let track = composition.addMutableTrack(withMediaType: mediaType, preferredTrackID: kCMPersistentTrackID_Invalid) {
                tracks.append(track)
            }
        }
        return tracks
    }

    private func buildVideoInstructions(
        for timeline: Timeline,
        videoTrackMap: [Int: AVMutableCompositionTrack],
        renderSize: CGSize,
        tapeScaleMode: ScaleMode
    ) -> [AVVideoCompositionInstructionProtocol] {
        var instructions: [AVMutableVideoCompositionInstruction] = []

        for (index, segment) in timeline.segments.enumerated() {
            guard let track = videoTrackMap[segment.clipIndex] else { continue }

            let incomingDuration = segment.incomingTransition?.duration ?? .zero
            let outgoingDuration = segment.outgoingTransition?.duration ?? .zero
            var passThroughStart = segment.timeRange.start
            var passThroughDuration = segment.timeRange.duration

            if CMTimeCompare(incomingDuration, .zero) > 0 {
                passThroughStart = CMTimeAdd(passThroughStart, incomingDuration)
                passThroughDuration = CMTimeSubtract(passThroughDuration, incomingDuration)
            }
            if CMTimeCompare(outgoingDuration, .zero) > 0 {
                passThroughDuration = CMTimeSubtract(passThroughDuration, outgoingDuration)
            }

            if CMTimeCompare(passThroughDuration, .zero) > 0 {
                let instruction = AVMutableVideoCompositionInstruction()
                instruction.timeRange = CMTimeRange(start: passThroughStart, duration: passThroughDuration)

                let layerInstruction = baseLayerInstruction(
                    for: segment,
                    track: track,
                    renderSize: renderSize,
                    scaleMode: segment.assetContext.clip.overrideScaleMode ?? tapeScaleMode,
                    at: passThroughStart
                )
                instruction.layerInstructions = [layerInstruction]
                instructions.append(instruction)
            }

            if let transition = segment.outgoingTransition,
               let nextSegment = timeline.segments[safe: index + 1],
               let nextTrack = videoTrackMap[nextSegment.clipIndex] {

                let transitionStart = CMTimeSubtract(CMTimeAdd(segment.timeRange.start, segment.timeRange.duration), transition.duration)
                let transitionRange = CMTimeRange(start: transitionStart, duration: transition.duration)

                let fromLayer = baseLayerInstruction(
                    for: segment,
                    track: track,
                    renderSize: renderSize,
                    scaleMode: segment.assetContext.clip.overrideScaleMode ?? tapeScaleMode,
                    at: transitionRange.start
                )

                let toLayer = baseLayerInstruction(
                    for: nextSegment,
                    track: nextTrack,
                    renderSize: renderSize,
                    scaleMode: nextSegment.assetContext.clip.overrideScaleMode ?? tapeScaleMode,
                    at: transitionRange.start
                )

                configureTransition(
                    transition,
                    fromLayer: fromLayer,
                    toLayer: toLayer,
                    fromBaseTransform: baseTransform(
                        for: segment.assetContext,
                        renderSize: renderSize,
                        scaleMode: segment.assetContext.clip.overrideScaleMode ?? tapeScaleMode
                    ),
                    toBaseTransform: baseTransform(
                        for: nextSegment.assetContext,
                        renderSize: renderSize,
                        scaleMode: nextSegment.assetContext.clip.overrideScaleMode ?? tapeScaleMode
                    ),
                    transitionRange: transitionRange,
                    renderSize: renderSize
                )

                let transitionInstruction = AVMutableVideoCompositionInstruction()
                transitionInstruction.timeRange = transitionRange
                transitionInstruction.layerInstructions = [toLayer, fromLayer]
                instructions.append(transitionInstruction)
            }
        }

        instructions.sort { CMTimeCompare($0.timeRange.start, $1.timeRange.start) < 0 }
        return instructions
    }

    private func baseLayerInstruction(
        for segment: Segment,
        track: AVMutableCompositionTrack,
        renderSize: CGSize,
        scaleMode: ScaleMode,
        at time: CMTime
    ) -> AVMutableVideoCompositionLayerInstruction {
        let instruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        let transform = baseTransform(for: segment.assetContext, renderSize: renderSize, scaleMode: scaleMode)
        instruction.setTransform(transform, at: time)
        instruction.setOpacity(1.0, at: time)
        return instruction
    }

    private func configureTransition(
        _ descriptor: TransitionDescriptor,
        fromLayer: AVMutableVideoCompositionLayerInstruction,
        toLayer: AVMutableVideoCompositionLayerInstruction,
        fromBaseTransform: CGAffineTransform,
        toBaseTransform: CGAffineTransform,
        transitionRange: CMTimeRange,
        renderSize: CGSize
    ) {
        switch descriptor.style {
        case .crossfade:
            fromLayer.setOpacityRamp(fromStartOpacity: 1.0, toEndOpacity: 0.0, timeRange: transitionRange)
            toLayer.setOpacityRamp(fromStartOpacity: 0.0, toEndOpacity: 1.0, timeRange: transitionRange)
            fromLayer.setTransform(fromBaseTransform, at: transitionRange.start)
            toLayer.setTransform(toBaseTransform, at: transitionRange.start)
        case .slideLR:
            applySlideTransition(
                fromLayer: fromLayer,
                toLayer: toLayer,
                fromBaseTransform: fromBaseTransform,
                toBaseTransform: toBaseTransform,
                transitionRange: transitionRange,
                renderSize: renderSize,
                direction: .leftToRight
            )
        case .slideRL:
            applySlideTransition(
                fromLayer: fromLayer,
                toLayer: toLayer,
                fromBaseTransform: fromBaseTransform,
                toBaseTransform: toBaseTransform,
                transitionRange: transitionRange,
                renderSize: renderSize,
                direction: .rightToLeft
            )
        case .none, .randomise:
            break
        }
    }

    private enum SlideDirection {
        case leftToRight
        case rightToLeft
    }

    private func applySlideTransition(
        fromLayer: AVMutableVideoCompositionLayerInstruction,
        toLayer: AVMutableVideoCompositionLayerInstruction,
        fromBaseTransform: CGAffineTransform,
        toBaseTransform: CGAffineTransform,
        transitionRange: CMTimeRange,
        renderSize: CGSize,
        direction: SlideDirection
    ) {
        let offset = direction == .leftToRight ? renderSize.width : -renderSize.width
        let outgoingEndTransform = fromBaseTransform.concatenating(CGAffineTransform(translationX: -offset, y: 0))
        let incomingStartTransform = toBaseTransform.concatenating(CGAffineTransform(translationX: offset, y: 0))

        fromLayer.setOpacityRamp(fromStartOpacity: 1.0, toEndOpacity: 1.0, timeRange: transitionRange)
        toLayer.setOpacityRamp(fromStartOpacity: 1.0, toEndOpacity: 1.0, timeRange: transitionRange)

        fromLayer.setTransform(fromBaseTransform, at: transitionRange.start)
        toLayer.setTransform(incomingStartTransform, at: transitionRange.start)

        fromLayer.setTransformRamp(fromStart: fromBaseTransform, toEnd: outgoingEndTransform, timeRange: transitionRange)
        toLayer.setTransformRamp(fromStart: incomingStartTransform, toEnd: toBaseTransform, timeRange: transitionRange)
    }

    private func baseTransform(
        for context: ClipAssetContext,
        renderSize: CGSize,
        scaleMode: ScaleMode
    ) -> CGAffineTransform {
        // TODO: refine scaling/rotation handling; for now rely on preferredTransform.
        let preferred = context.preferredTransform
        // Basic scaling to fit render size.
        let naturalSize = context.naturalSize.applying(preferred)
        let absWidth = abs(naturalSize.width)
        let absHeight = abs(naturalSize.height)
        guard absWidth > 0, absHeight > 0 else { return preferred }

        let renderWidth = renderSize.width
        let renderHeight = renderSize.height

        let scaleX = renderWidth / absWidth
        let scaleY = renderHeight / absHeight

        let scale: CGFloat
        switch scaleMode {
        case .fit:
            scale = min(scaleX, scaleY)
        case .fill:
            scale = max(scaleX, scaleY)
        }

        var transform = preferred.scaledBy(x: scale, y: scale)
        // Center the video.
        let translatedX = (renderWidth - absWidth * scale) / 2
        let translatedY = (renderHeight - absHeight * scale) / 2
        transform = transform.translatedBy(x: translatedX / scale, y: translatedY / scale)
        return transform
    }
}

// MARK: - Deterministic RNG

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x4d595df4d0f33173 : seed
    }

    mutating func next() -> UInt64 {
        state &*= 2862933555777941757
        state &+= 3037000493
        return state
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
