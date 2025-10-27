import Foundation
import AVFoundation
import Photos
import CoreGraphics
import UIKit

/// Builds timeline metadata for tape playback using AVComposable assets.
/// The builder does not mutate the UI; it prepares the information required to render transitions.
struct TapeCompositionBuilder {

    typealias AssetResolver = (Clip) async throws -> AVAsset

    private let assetResolver: AssetResolver
    private let imageConfiguration: ImageClipConfiguration

    init(
        assetResolver: @escaping AssetResolver = TapeCompositionBuilder.defaultAssetResolver,
        imageConfiguration: ImageClipConfiguration = .default
    ) {
        self.assetResolver = assetResolver
        self.imageConfiguration = imageConfiguration
    }

    // MARK: - Nested Types

    enum BuilderError: Error, LocalizedError {
        case unsupportedClipType(ClipType)
        case assetUnavailable(clipID: UUID)
        case photosAccessDenied
        case photosAssetMissing
        case missingVideoTrack
        case imageEncodingFailed

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
            case .imageEncodingFailed:
                return "Unable to encode still image into video."
            }
        }
    }

    struct TransitionDescriptor {
        let style: TransitionType
        let duration: CMTime
    }

    struct MotionEffect {
        let startScale: CGFloat
        let endScale: CGFloat
        let startOffset: CGPoint // fraction of render size (0-1)
        let endOffset: CGPoint

        static let defaultKenBurns = MotionEffect(
            startScale: 1.05,
            endScale: 1.1,
            startOffset: CGPoint(x: 0.0, y: 0.0),
            endOffset: CGPoint(x: 0.05, y: -0.05)
        )
    }

    struct ImageClipConfiguration {
        let defaultDuration: Double
        let defaultMotionEffect: MotionEffect
        let baseScaleMode: ScaleMode

        static let `default` = ImageClipConfiguration(
            defaultDuration: 4.0,
            defaultMotionEffect: MotionEffect.defaultKenBurns,
            baseScaleMode: .fill
        )
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
        let motionEffect: MotionEffect?
        let isTemporaryAsset: Bool
    }

    struct Segment {
        let clipIndex: Int
        let assetContext: ClipAssetContext
        let timeRange: CMTimeRange
        let incomingTransition: TransitionDescriptor?
        let outgoingTransition: TransitionDescriptor?
        let motionEffect: MotionEffect?
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

    struct ResolvedAsset {
        let asset: AVAsset
        let isTemporary: Bool
        let motionEffect: MotionEffect?
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

        let contexts = try await loadAssets(for: tape.clips, startIndex: 0)
        return makeTimeline(for: tape, contexts: contexts)
    }

    func makeTimeline(for tape: Tape, contexts: [ClipAssetContext]) -> Timeline {
        guard !contexts.isEmpty else {
            return Timeline(
                segments: [],
                renderSize: renderSize(for: tape.orientation),
                totalDuration: .zero,
                transitionSequence: []
            )
        }

        let transitionDescriptors = buildTransitionDescriptors(for: tape, assets: contexts)
        let segments = buildSegments(for: contexts, transitions: transitionDescriptors)
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
        let contexts = try await loadAssets(for: tape.clips, startIndex: 0)
        let timeline = makeTimeline(for: tape, contexts: contexts)
        return try buildPlayerComposition(for: tape, timeline: timeline)
    }

    @MainActor
    func buildPlayerItem(for tape: Tape, contexts: [ClipAssetContext]) throws -> PlayerComposition {
        let timeline = makeTimeline(for: tape, contexts: contexts)
        return try buildPlayerComposition(for: tape, timeline: timeline)
    }

    func resolveClipContext(for clip: Clip, index: Int) async throws -> ClipAssetContext {
        let contexts = try await loadAssets(for: [clip], startIndex: index)
        guard let context = contexts.first else {
            throw BuilderError.assetUnavailable(clipID: clip.id)
        }
        return context
    }

    @MainActor
    private func buildPlayerComposition(
        for tape: Tape,
        timeline: Timeline
    ) throws -> PlayerComposition {
        let composition = AVMutableComposition()
        let videoTracks = try createCompositionTracks(for: composition, mediaType: .video)
        let audioTracks = try createCompositionTracks(for: composition, mediaType: .audio)

        var videoTrackMap: [Int: AVMutableCompositionTrack] = [:]
        var audioTrackMap: [Int: AVMutableCompositionTrack] = [:]
        var audioMixParameters: [CMPersistentTrackID: AVMutableAudioMixInputParameters] = [:]

        for segment in timeline.segments {
            let trackIndex = videoTracks.isEmpty ? 0 : segment.clipIndex % videoTracks.count
            if trackIndex < videoTracks.count {
                let videoTrack = videoTracks[trackIndex]
                let sourceRange = CMTimeRange(start: .zero, duration: segment.assetContext.duration)
                try videoTrack.insertTimeRange(sourceRange, of: segment.assetContext.videoTrack, at: segment.timeRange.start)
                videoTrackMap[segment.clipIndex] = videoTrack
            }

            if segment.assetContext.hasAudio,
               let sourceAudioTrack = segment.assetContext.audioTrack,
               trackIndex < audioTracks.count {
                let audioTrack = audioTracks[trackIndex]
                let sourceRange = CMTimeRange(start: .zero, duration: segment.assetContext.duration)
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
        try await loadAssets(for: clips, startIndex: 0)
    }

    private func loadAssets(for clips: [Clip], startIndex: Int) async throws -> [ClipAssetContext] {
        try await withThrowingTaskGroup(of: ClipAssetContext.self) { group in
            for (offset, clip) in clips.enumerated() {
                let index = startIndex + offset
                group.addTask {
                    let resolved = try await resolveAsset(for: clip)
                    let asset = resolved.asset
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
                        audioTrack: audioTrack,
                        motionEffect: resolved.motionEffect,
                        isTemporaryAsset: resolved.isTemporary
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

    private func resolveAsset(for clip: Clip) async throws -> ResolvedAsset {
        switch clip.clipType {
        case .video:
            let asset = try await resolveVideoAsset(for: clip)
            return ResolvedAsset(asset: asset, isTemporary: false, motionEffect: nil)
        case .image:
            let image = try await loadImage(for: clip)
            let durationSeconds = clip.duration > 0 ? clip.duration : imageConfiguration.defaultDuration
            let asset = try createVideoAsset(from: image, clip: clip, duration: durationSeconds)
            return ResolvedAsset(
                asset: asset,
                isTemporary: true,
                motionEffect: imageConfiguration.defaultMotionEffect
            )
        }
    }

    private static func fetchAVAssetFromPhotos(localIdentifier: String) async throws -> AVAsset {
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

    private static func defaultAssetResolver(_ clip: Clip) async throws -> AVAsset {
        switch clip.clipType {
        case .video:
            if let url = clip.localURL {
                let accessibleURL = try accessibleURL(for: clip, url: url)
                return AVURLAsset(url: accessibleURL)
            }
            if let assetLocalId = clip.assetLocalId {
                return try await fetchAVAssetFromPhotos(localIdentifier: assetLocalId)
            }
            throw BuilderError.assetUnavailable(clipID: clip.id)
        case .image:
            throw BuilderError.unsupportedClipType(.image)
        }
    }

    private func resolveVideoAsset(for clip: Clip) async throws -> AVAsset {
        let fileManager = FileManager.default

        if let localURL = clip.localURL {
            if fileManager.fileExists(atPath: localURL.path) {
                let accessibleURL = try Self.accessibleURL(for: clip, url: localURL)
                return AVURLAsset(url: accessibleURL)
            } else {
                let cachedURL = Self.cachedURL(for: clip, originalURL: localURL)
                if fileManager.fileExists(atPath: cachedURL.path) {
                    return AVURLAsset(url: cachedURL)
                }
            }
        }

        if let assetLocalId = clip.assetLocalId {
            return try await Self.fetchAVAssetFromPhotos(localIdentifier: assetLocalId)
        }

        throw BuilderError.assetUnavailable(clipID: clip.id)
    }

    private static func accessibleURL(for clip: Clip, url: URL) throws -> URL {
        var didAccessSecurityScope = false
        if url.startAccessingSecurityScopedResource() {
            didAccessSecurityScope = true
        }
        defer {
            if didAccessSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let fileManager = FileManager.default
        let cacheDirectory = fileManager.temporaryDirectory.appendingPathComponent("PlaybackCache", isDirectory: true)
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
        }

        let destinationURL = cachedURL(for: clip, originalURL: url)

        if fileManager.fileExists(atPath: destinationURL.path) {
            return destinationURL
        }

        try fileManager.copyItem(at: url, to: destinationURL)
        return destinationURL
    }

    private static func cachedURL(for clip: Clip, originalURL: URL) -> URL {
        let fileManager = FileManager.default
        let cacheDirectory = fileManager.temporaryDirectory.appendingPathComponent("PlaybackCache", isDirectory: true)
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
        }
        let fileExtension = originalURL.pathExtension.isEmpty ? "mov" : originalURL.pathExtension
        let updatedAt = clip.updatedAt ?? Date.distantPast
        let timestamp = Int((updatedAt.timeIntervalSince1970 * 1_000).rounded())
        let versionComponent = "\(clip.id.uuidString)-\(timestamp)"
        return cacheDirectory.appendingPathComponent(versionComponent).appendingPathExtension(fileExtension)
    }

    private func makeAccessibleCopyIfNeeded(for clip: Clip, sourceURL: URL) throws -> URL {
        return try Self.accessibleURL(for: clip, url: sourceURL)
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
                outgoingTransition: outgoingTransition,
                motionEffect: assetContext.motionEffect
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

    private func transform(
        for segment: Segment,
        renderSize: CGSize,
        scaleMode: ScaleMode,
        at time: CMTime
    ) -> CGAffineTransform {
        let base = baseTransform(
            for: segment.assetContext,
            renderSize: renderSize,
            scaleMode: scaleMode
        )

        guard let effect = segment.motionEffect,
              CMTimeCompare(segment.timeRange.duration, .zero) > 0 else {
            return base
        }

        let progress = normalizedProgress(for: segment, at: time)
        return apply(effect: effect, to: base, renderSize: renderSize, progress: progress)
    }

    private func normalizedProgress(for segment: Segment, at time: CMTime) -> CGFloat {
        let durationSeconds = CMTimeGetSeconds(segment.timeRange.duration)
        guard durationSeconds.isFinite, durationSeconds > 0 else { return 0 }

        let elapsed = CMTimeGetSeconds(CMTimeSubtract(time, segment.timeRange.start))
        guard elapsed.isFinite else { return 0 }

        let clamped = max(0, min(elapsed, durationSeconds))
        return CGFloat(clamped / durationSeconds)
    }

    private func apply(
        effect: MotionEffect,
        to base: CGAffineTransform,
        renderSize: CGSize,
        progress: CGFloat
    ) -> CGAffineTransform {
        let scale = lerp(effect.startScale, effect.endScale, progress: progress)
        let offsetX = lerp(effect.startOffset.x, effect.endOffset.x, progress: progress) * renderSize.width
        let offsetY = lerp(effect.startOffset.y, effect.endOffset.y, progress: progress) * renderSize.height

        var effectTransform = CGAffineTransform.identity
        let renderCenter = CGPoint(x: renderSize.width * 0.5, y: renderSize.height * 0.5)
        effectTransform = effectTransform.translatedBy(x: renderCenter.x, y: renderCenter.y)
        effectTransform = effectTransform.scaledBy(x: scale, y: scale)
        effectTransform = effectTransform.translatedBy(x: -renderCenter.x, y: -renderCenter.y)
        effectTransform = effectTransform.translatedBy(x: offsetX, y: offsetY)

        return base.concatenating(effectTransform)
    }

    private func applyTransformRampIfNeeded(
        on instruction: AVMutableVideoCompositionLayerInstruction,
        for segment: Segment,
        renderSize: CGSize,
        scaleMode: ScaleMode,
        startTime: CMTime,
        endTime: CMTime
    ) {
        guard CMTimeCompare(endTime, startTime) > 0 else { return }
        let startTransform = transform(for: segment, renderSize: renderSize, scaleMode: scaleMode, at: startTime)
        let endTransform = transform(for: segment, renderSize: renderSize, scaleMode: scaleMode, at: endTime)

        guard startTransform != endTransform else { return }

        let duration = CMTimeSubtract(endTime, startTime)
        let timeRange = CMTimeRange(start: startTime, duration: duration)
        instruction.setTransformRamp(fromStart: startTransform, toEnd: endTransform, timeRange: timeRange)
    }

    private func lerp(_ start: CGFloat, _ end: CGFloat, progress: CGFloat) -> CGFloat {
        start + (end - start) * max(0, min(progress, 1))
    }

    private func effectiveScaleMode(for segment: Segment, tapeScaleMode: ScaleMode) -> ScaleMode {
        if let override = segment.assetContext.clip.overrideScaleMode {
            return override
        }
        if segment.motionEffect != nil {
            return imageConfiguration.baseScaleMode
        }
        return tapeScaleMode
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
            let segmentScaleMode = effectiveScaleMode(for: segment, tapeScaleMode: tapeScaleMode)

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
                    scaleMode: segmentScaleMode,
                    at: passThroughStart
                )
                let passThroughEnd = CMTimeAdd(passThroughStart, passThroughDuration)
                applyTransformRampIfNeeded(
                    on: layerInstruction,
                    for: segment,
                    renderSize: renderSize,
                    scaleMode: segmentScaleMode,
                    startTime: passThroughStart,
                    endTime: passThroughEnd
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
                    scaleMode: segmentScaleMode,
                    at: transitionRange.start
                )

                let nextScaleMode = effectiveScaleMode(for: nextSegment, tapeScaleMode: tapeScaleMode)
                let toLayer = baseLayerInstruction(
                    for: nextSegment,
                    track: nextTrack,
                    renderSize: renderSize,
                    scaleMode: nextScaleMode,
                    at: transitionRange.start
                )

                configureTransition(
                    transition,
                    fromSegment: segment,
                    toSegment: nextSegment,
                    fromLayer: fromLayer,
                    toLayer: toLayer,
                    transitionRange: transitionRange,
                    renderSize: renderSize,
                    fromScaleMode: segmentScaleMode,
                    toScaleMode: nextScaleMode
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
        let transform = transform(for: segment, renderSize: renderSize, scaleMode: scaleMode, at: time)
        instruction.setTransform(transform, at: time)
        instruction.setOpacity(1.0, at: time)
        return instruction
    }

    private func configureTransition(
        _ descriptor: TransitionDescriptor,
        fromSegment: Segment,
        toSegment: Segment,
        fromLayer: AVMutableVideoCompositionLayerInstruction,
        toLayer: AVMutableVideoCompositionLayerInstruction,
        transitionRange: CMTimeRange,
        renderSize: CGSize,
        fromScaleMode: ScaleMode,
        toScaleMode: ScaleMode
    ) {
        let transitionEnd = CMTimeAdd(transitionRange.start, transitionRange.duration)
        let fromStartTransform = transform(for: fromSegment, renderSize: renderSize, scaleMode: fromScaleMode, at: transitionRange.start)
        let fromEndTransform = transform(for: fromSegment, renderSize: renderSize, scaleMode: fromScaleMode, at: transitionEnd)
        let toStartTransform = transform(for: toSegment, renderSize: renderSize, scaleMode: toScaleMode, at: transitionRange.start)
        let toEndTransform = transform(for: toSegment, renderSize: renderSize, scaleMode: toScaleMode, at: transitionEnd)

        switch descriptor.style {
        case .crossfade:
            fromLayer.setOpacityRamp(fromStartOpacity: 1.0, toEndOpacity: 0.0, timeRange: transitionRange)
            toLayer.setOpacityRamp(fromStartOpacity: 0.0, toEndOpacity: 1.0, timeRange: transitionRange)
            fromLayer.setTransform(fromStartTransform, at: transitionRange.start)
            toLayer.setTransform(toStartTransform, at: transitionRange.start)

            if CMTimeCompare(transitionRange.duration, .zero) > 0 {
                if fromStartTransform != fromEndTransform {
                    fromLayer.setTransformRamp(fromStart: fromStartTransform, toEnd: fromEndTransform, timeRange: transitionRange)
                }
                if toStartTransform != toEndTransform {
                    toLayer.setTransformRamp(fromStart: toStartTransform, toEnd: toEndTransform, timeRange: transitionRange)
                }
            }
        case .slideLR:
            applySlideTransition(
                fromLayer: fromLayer,
                toLayer: toLayer,
                fromTransform: fromStartTransform,
                toTransform: toStartTransform,
                transitionRange: transitionRange,
                renderSize: renderSize,
                direction: .leftToRight
            )
        case .slideRL:
            applySlideTransition(
                fromLayer: fromLayer,
                toLayer: toLayer,
                fromTransform: fromStartTransform,
                toTransform: toStartTransform,
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
        fromTransform: CGAffineTransform,
        toTransform: CGAffineTransform,
        transitionRange: CMTimeRange,
        renderSize: CGSize,
        direction: SlideDirection
    ) {
        let offset = direction == .leftToRight ? renderSize.width : -renderSize.width
        let outgoingEndTransform = prependTranslation(to: fromTransform, dx: -offset, dy: 0)
        let incomingStartTransform = prependTranslation(to: toTransform, dx: offset, dy: 0)

        fromLayer.setOpacityRamp(fromStartOpacity: 1.0, toEndOpacity: 1.0, timeRange: transitionRange)
        toLayer.setOpacityRamp(fromStartOpacity: 1.0, toEndOpacity: 1.0, timeRange: transitionRange)

        fromLayer.setTransform(fromTransform, at: transitionRange.start)
        toLayer.setTransform(incomingStartTransform, at: transitionRange.start)

        if CMTimeCompare(transitionRange.duration, .zero) > 0 {
            fromLayer.setTransformRamp(fromStart: fromTransform, toEnd: outgoingEndTransform, timeRange: transitionRange)
            toLayer.setTransformRamp(fromStart: incomingStartTransform, toEnd: toTransform, timeRange: transitionRange)
        }
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

    private func prependTranslation(to transform: CGAffineTransform, dx: CGFloat, dy: CGFloat) -> CGAffineTransform {
        var result = transform
        result.tx += dx
        result.ty += dy
        return result
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

private extension TapeCompositionBuilder {
    func loadImage(for clip: Clip) async throws -> UIImage {
        if let data = clip.imageData, let image = UIImage(data: data) {
            return image
        }
        if let url = clip.localURL, let image = UIImage(contentsOfFile: url.path) {
            return image
        }
        if let assetLocalId = clip.assetLocalId {
            return try await fetchImageFromPhotos(localIdentifier: assetLocalId)
        }
        throw BuilderError.assetUnavailable(clipID: clip.id)
    }

    func fetchImageFromPhotos(localIdentifier: String) async throws -> UIImage {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw BuilderError.photosAccessDenied
        }

        return try await withCheckedThrowingContinuation { continuation in
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
            guard let asset = fetchResult.firstObject else {
                continuation.resume(throwing: BuilderError.photosAssetMissing)
                return
            }
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                if let data = data, let image = UIImage(data: data) {
                    continuation.resume(returning: image)
                } else if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                } else if let cancelled = info?[PHImageCancelledKey] as? NSNumber, cancelled.boolValue {
                    continuation.resume(throwing: BuilderError.photosAssetMissing)
                } else {
                    continuation.resume(throwing: BuilderError.photosAssetMissing)
                }
            }
        }
    }

    func createVideoAsset(from image: UIImage, clip: Clip, duration: Double) throws -> AVAsset {
        let cgImage = try normalizedCGImage(from: image, clip: clip)
        let rotationTurns = ((clip.rotateQuarterTurns % 4) + 4) % 4
        let targetSize = normalizedVideoSize(for: cgImage, rotationTurns: rotationTurns)
        let targetWidth = Int(targetSize.width)
        let targetHeight = Int(targetSize.height)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: targetWidth,
            AVVideoHeightKey: targetHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2_000_000
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: targetWidth,
                kCVPixelBufferHeightKey as String: targetHeight,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
        )

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frameDuration = CMTime(value: 1, timescale: 30)
        let totalFrames = max(1, Int(duration * 30))
        guard let pixelBufferPool = adaptor.pixelBufferPool else {
            throw BuilderError.imageEncodingFailed
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        for frameIndex in 0..<totalFrames {
            let time = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.001)
            }

            var pixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &pixelBuffer)
            guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
                continue
            }

            render(
                cgImage: cgImage,
                into: buffer,
                targetSize: targetSize,
                rotationTurns: rotationTurns,
                colorSpace: colorSpace
            )

            adaptor.append(buffer, withPresentationTime: time)
        }

        input.markAsFinished()
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            semaphore.signal()
        }
        semaphore.wait()
        return AVURLAsset(url: url)
    }

    func normalizedCGImage(from image: UIImage, clip: Clip) throws -> CGImage {
        if image.imageOrientation == .up, let cgImage = image.cgImage {
            return cgImage
        }

        let pixelSize = CGSize(
            width: max(image.size.width * image.scale, 1),
            height: max(image.size.height * image.scale, 1)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard

        let renderer = UIGraphicsImageRenderer(size: pixelSize, format: format)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: pixelSize))
        }

        guard let cgImage = rendered.cgImage else {
            throw BuilderError.assetUnavailable(clipID: clip.id)
        }
        return cgImage
    }

    func normalizedVideoSize(for cgImage: CGImage, rotationTurns: Int) -> CGSize {
        let swapAxes = rotationTurns % 2 != 0
        let baseWidth = CGFloat(cgImage.width)
        let baseHeight = CGFloat(cgImage.height)

        let rotatedWidth = swapAxes ? baseHeight : baseWidth
        let rotatedHeight = swapAxes ? baseWidth : baseHeight

        let maxLongSide: CGFloat = 1920
        let maxShortSide: CGFloat = 1080
        let longSide = max(rotatedWidth, rotatedHeight)
        let shortSide = min(rotatedWidth, rotatedHeight)

        let longScale = maxLongSide / longSide
        let shortScale = maxShortSide / shortSide
        let scale = min(min(longScale, shortScale), 1.0)

        let scaledWidth = rotatedWidth * scale
        let scaledHeight = rotatedHeight * scale

        let width = makeEvenDimension(scaledWidth)
        let height = makeEvenDimension(scaledHeight)
        return CGSize(width: CGFloat(width), height: CGFloat(height))
    }

    func makeEvenDimension(_ value: CGFloat) -> Int {
        var intValue = max(2, Int(round(value)))
        if intValue % 2 != 0 {
            intValue -= 1
        }
        if intValue < 2 {
            intValue = 2
        }
        return intValue
    }

    func render(
        cgImage: CGImage,
        into pixelBuffer: CVPixelBuffer,
        targetSize: CGSize,
        rotationTurns: Int,
        colorSpace: CGColorSpace
    ) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        }

        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: Int(targetSize.width),
            height: Int(targetSize.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return
        }

        context.clear(CGRect(origin: .zero, size: targetSize))
        context.interpolationQuality = .high

        context.saveGState()
        context.translateBy(x: targetSize.width / 2, y: targetSize.height / 2)
        if rotationTurns != 0 {
            let angle = CGFloat(rotationTurns) * (.pi / 2)
            context.rotate(by: angle)
        }

        let sourceWidth = CGFloat(cgImage.width)
        let sourceHeight = CGFloat(cgImage.height)
        let rotatedWidth = rotationTurns % 2 == 0 ? sourceWidth : sourceHeight
        let rotatedHeight = rotationTurns % 2 == 0 ? sourceHeight : sourceWidth
        let scale = min(targetSize.width / rotatedWidth, targetSize.height / rotatedHeight)
        context.scaleBy(x: scale, y: scale)

        let drawRect = CGRect(
            x: -sourceWidth / 2,
            y: -sourceHeight / 2,
            width: sourceWidth,
            height: sourceHeight
        )
        context.draw(cgImage, in: drawRect)
        context.restoreGState()
    }
}
