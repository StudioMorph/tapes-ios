import Foundation
import AVFoundation
import Photos
import CoreGraphics
import UIKit

/// Builds timeline metadata for tape playback using AVComposable assets.
/// The builder does not mutate the UI; it prepares the information required to render transitions.
struct TapeCompositionBuilder {

    typealias AssetResolver = (Clip) async throws -> AVAsset

    let assetResolver: AssetResolver
    let imageConfiguration: ImageClipConfiguration
    let videoDeliveryMode: PHVideoRequestOptionsDeliveryMode
    let livePhotosAsVideo: Bool
    let livePhotosMuted: Bool
    let sharedCIContext = CIContext(options: [.useSoftwareRenderer: false])

    init(
        assetResolver: @escaping AssetResolver = TapeCompositionBuilder.defaultAssetResolver,
        imageConfiguration: ImageClipConfiguration = .default,
        videoDeliveryMode: PHVideoRequestOptionsDeliveryMode = .highQualityFormat,
        livePhotosAsVideo: Bool = true,
        livePhotosMuted: Bool = true
    ) {
        self.assetResolver = assetResolver
        self.imageConfiguration = imageConfiguration
        self.videoDeliveryMode = videoDeliveryMode
        self.livePhotosAsVideo = livePhotosAsVideo
        self.livePhotosMuted = livePhotosMuted
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

        // MARK: - Motion Style Presets

        /// Cinematic slow zoom + diagonal pan, classic documentary feel.
        static let kenBurns = MotionEffect(
            startScale: 1.05,
            endScale: 1.2,
            startOffset: CGPoint(x: -0.05, y: 0.03),
            endOffset: CGPoint(x: 0.05, y: -0.03)
        )

        /// Smooth horizontal glide across the image.
        static let pan = MotionEffect(
            startScale: 1.2,
            endScale: 1.2,
            startOffset: CGPoint(x: -0.10, y: 0.0),
            endOffset: CGPoint(x: 0.10, y: 0.0)
        )

        /// Gradual zoom into the centre of the image.
        static let zoomIn = MotionEffect(
            startScale: 1.0,
            endScale: 1.3,
            startOffset: .zero,
            endOffset: .zero
        )

        /// Start cropped tight, gradually reveal the full image.
        static let zoomOut = MotionEffect(
            startScale: 1.3,
            endScale: 1.0,
            startOffset: .zero,
            endOffset: .zero
        )

        /// Subtle floating diagonal drift with gentle scale breathing.
        static let drift = MotionEffect(
            startScale: 1.03,
            endScale: 1.09,
            startOffset: CGPoint(x: 0.02, y: -0.02),
            endOffset: CGPoint(x: -0.02, y: 0.02)
        )

        static func from(style: MotionStyle) -> MotionEffect? {
            switch style {
            case .none: return nil
            case .kenBurns: return .kenBurns
            case .pan: return .pan
            case .zoomIn: return .zoomIn
            case .zoomOut: return .zoomOut
            case .drift: return .drift
            }
        }
    }

    struct ImageClipConfiguration {
        let defaultDuration: Double
        let defaultMotionEffect: MotionEffect
        let baseScaleMode: ScaleMode
        let encodingFrameRate: Int
        let bakeMotionEffect: Bool

        static let `default` = ImageClipConfiguration(
            defaultDuration: 4.0,
            defaultMotionEffect: MotionEffect.defaultKenBurns,
            baseScaleMode: .fill,
            encodingFrameRate: 30,
            bakeMotionEffect: true
        )

        static let export = ImageClipConfiguration(
            defaultDuration: 4.0,
            defaultMotionEffect: MotionEffect.defaultKenBurns,
            baseScaleMode: .fill,
            encodingFrameRate: 1,
            bakeMotionEffect: false
        )
    }

    // MARK: - Metadata (Lightweight - for timeline building)
    
    struct ClipMetadata {
        let index: Int
        let clip: Clip
        let duration: CMTime
        let naturalSize: CGSize? // Optional - can be nil for timeline, resolved later for playback
        let motionEffect: MotionEffect?
    }
    
    // MARK: - Asset Context (Full - for playback building)
    
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
        let metadata: ClipMetadata // TIMELINE FIX: Use lightweight metadata instead of full asset context
        let assetContext: ClipAssetContext? // Optional - only set when building playback
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

    struct PlayerComposition: @unchecked Sendable {
        let playerItem: AVPlayerItem
        let timeline: Timeline
    }

    struct ExportableComposition: @unchecked Sendable {
        let composition: AVMutableComposition
        let videoComposition: AVMutableVideoComposition
        let audioMix: AVMutableAudioMix?
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

        // TIMELINE FIX: Load only metadata (fast) instead of full AVAssets (slow)
        // This is now synchronous - just reading clip properties, no async work
        let metadata = loadMetadata(for: tape.clips, startIndex: 0)
        return makeTimeline(for: tape, metadata: metadata)
    }

    func makeTimeline(for tape: Tape, metadata: [ClipMetadata]) -> Timeline {
        guard !metadata.isEmpty else {
            return Timeline(
                segments: [],
                renderSize: renderSize(for: tape.orientation),
                totalDuration: .zero,
                transitionSequence: []
            )
        }

        let transitionDescriptors = buildTransitionDescriptors(for: tape, metadata: metadata)
        let segments = buildSegments(for: metadata, transitions: transitionDescriptors)
        let totalDuration = segments.last.map { CMTimeAdd($0.timeRange.start, $0.timeRange.duration) } ?? .zero

        return Timeline(
            segments: segments,
            renderSize: renderSize(for: tape.orientation),
            totalDuration: totalDuration,
            transitionSequence: transitionDescriptors
        )
    }
    
    // Legacy method for backward compatibility - now resolves full contexts
    func makeTimeline(for tape: Tape, contexts: [ClipAssetContext]) -> Timeline {
        let metadata = contexts.map { context in
            let clip = context.clip
            let effectiveDuration: CMTime
            if clip.isTrimmed {
                let trimmed = CMTimeGetSeconds(context.duration) - clip.trimStart - clip.trimEnd
                effectiveDuration = CMTime(seconds: max(0.1, trimmed), preferredTimescale: 600)
            } else {
                effectiveDuration = context.duration
            }
            return ClipMetadata(
                index: context.index,
                clip: clip,
                duration: effectiveDuration,
                naturalSize: context.naturalSize,
                motionEffect: context.motionEffect
            )
        }
        let transitionDescriptors = buildTransitionDescriptors(for: tape, metadata: metadata)
        let segments = buildSegments(for: metadata, contexts: contexts, transitions: transitionDescriptors)
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
        return try await buildPlayerComposition(for: tape, timeline: timeline)
    }

    @MainActor
    func buildPlayerItem(for tape: Tape, contexts: [ClipAssetContext]) async throws -> PlayerComposition {
        let timeline = makeTimeline(for: tape, contexts: contexts)
        return try await buildPlayerComposition(for: tape, timeline: timeline)
    }

    @MainActor
    func buildExportComposition(for tape: Tape) async throws -> ExportableComposition {
        let contexts = try await loadAssets(for: tape.clips, startIndex: 0)
        var exportTape = tape
        exportTape.orientation = resolveExportOrientation(tape: tape, contexts: contexts)
        let timeline = makeTimeline(for: exportTape, contexts: contexts)
        return try await buildCompositionComponents(for: exportTape, timeline: timeline, enableBlurBackground: tape.blurExportBackground)
    }

    private func resolveExportOrientation(tape: Tape, contexts: [ClipAssetContext]) -> TapeOrientation {
        switch tape.exportOrientation {
        case .portrait: return .portrait
        case .landscape: return .landscape
        case .auto:
            var portraitCount = 0
            var landscapeCount = 0
            for ctx in contexts {
                let size = ctx.naturalSize.applying(ctx.preferredTransform)
                if abs(size.width) > abs(size.height) {
                    landscapeCount += 1
                } else {
                    portraitCount += 1
                }
            }
            return landscapeCount > portraitCount ? .landscape : .portrait
        }
    }

    @MainActor
    func buildSingleClipPlayerItem(
        for tape: Tape,
        clipIndex: Int,
        timeline: Timeline
    ) async throws -> PlayerComposition {
        guard clipIndex >= 0, clipIndex < tape.clips.count else {
            throw BuilderError.assetUnavailable(clipID: UUID())
        }
        let clip = tape.clips[clipIndex]
        let isLiveVideo = clip.shouldPlayAsLiveVideo(tapeDefault: livePhotosAsVideo)
        if clip.clipType == .image && !isLiveVideo {
            let image = try await loadImage(for: clip)
            let durationSeconds = clip.duration > 0 ? clip.duration : imageConfiguration.defaultDuration
            let duration = CMTime(seconds: durationSeconds, preferredTimescale: 600)
            let cgImage = try normalizedCGImage(from: image, clip: clip)
            let naturalSize = CGSize(width: cgImage.width, height: cgImage.height)
            let motionEffect = MotionEffect.from(style: clip.motionStyle)

            let metadata = ClipMetadata(
                index: clipIndex,
                clip: clip,
                duration: duration,
                naturalSize: naturalSize,
                motionEffect: motionEffect
            )
            let segment = Segment(
                clipIndex: clipIndex,
                metadata: metadata,
                assetContext: nil,
                timeRange: CMTimeRange(start: .zero, duration: duration),
                incomingTransition: nil,
                outgoingTransition: nil,
                motionEffect: motionEffect
            )

            let singleTimeline = Timeline(
                segments: [segment],
                renderSize: timeline.renderSize,
                totalDuration: duration,
                transitionSequence: []
            )

            let effectiveScaleMode: ScaleMode
            if let override = clip.overrideScaleMode {
                effectiveScaleMode = override
            } else {
                let imageIsLandscape = naturalSize.width > naturalSize.height
                let renderIsLandscape = timeline.renderSize.width > timeline.renderSize.height
                effectiveScaleMode = (imageIsLandscape == renderIsLandscape) ? .fill : .fit
            }

            let playerItem = try await makeStillImagePlayerItem(
                cgImage: cgImage,
                clip: clip,
                duration: duration,
                renderSize: timeline.renderSize,
                motionEffect: motionEffect,
                scaleMode: effectiveScaleMode
            )
            return PlayerComposition(playerItem: playerItem, timeline: singleTimeline)
        }

        let context = try await resolveClipContext(for: clip, index: clipIndex)

        let effectiveDuration: CMTime
        if clip.isTrimmed && clip.trimmedDuration > 0 {
            effectiveDuration = CMTime(seconds: clip.trimmedDuration, preferredTimescale: 600)
        } else {
            effectiveDuration = context.duration
        }

        let metadata = ClipMetadata(
            index: clipIndex,
            clip: clip,
            duration: effectiveDuration,
            naturalSize: context.naturalSize,
            motionEffect: context.motionEffect
        )
        let segment = Segment(
            clipIndex: clipIndex,
            metadata: metadata,
            assetContext: context,
            timeRange: CMTimeRange(start: .zero, duration: effectiveDuration),
            incomingTransition: nil,
            outgoingTransition: nil,
            motionEffect: metadata.motionEffect
        )

        let singleTimeline = Timeline(
            segments: [segment],
            renderSize: timeline.renderSize,
            totalDuration: effectiveDuration,
            transitionSequence: []
        )

        let playerItem: AVPlayerItem
        if clip.isTrimmed {
            let composition = AVMutableComposition()
            let sourceStart = CMTime(seconds: clip.trimStart, preferredTimescale: 600)
            let sourceRange = CMTimeRange(start: sourceStart, duration: effectiveDuration)

            if let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try compVideoTrack.insertTimeRange(sourceRange, of: context.videoTrack, at: .zero)
                compVideoTrack.preferredTransform = context.preferredTransform
            }
            if let assetAudioTrack = context.audioTrack,
               let compAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try compAudioTrack.insertTimeRange(sourceRange, of: assetAudioTrack, at: .zero)
            }
            playerItem = AVPlayerItem(asset: composition)
        } else {
            playerItem = AVPlayerItem(asset: context.asset)
        }

        if clip.shouldMuteLiveAudio(tapeDefault: livePhotosMuted) {
            let audioTracks = try await playerItem.asset.loadTracks(withMediaType: .audio)
            if !audioTracks.isEmpty {
                let audioMix = AVMutableAudioMix()
                audioMix.inputParameters = audioTracks.map { track in
                    let params = AVMutableAudioMixInputParameters(track: track)
                    params.setVolume(0, at: .zero)
                    return params
                }
                playerItem.audioMix = audioMix
            }
        }

        return PlayerComposition(playerItem: playerItem, timeline: singleTimeline)
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
    ) async throws -> PlayerComposition {
        let components = try await buildCompositionComponents(for: tape, timeline: timeline)

        let playerItem = AVPlayerItem(asset: components.composition)
        playerItem.videoComposition = components.videoComposition
        if let audioMix = components.audioMix {
            playerItem.audioMix = audioMix
        }

        return PlayerComposition(playerItem: playerItem, timeline: components.timeline)
    }

    @MainActor
    func buildCompositionComponents(
        for tape: Tape,
        timeline: Timeline,
        enableBlurBackground: Bool = false
    ) async throws -> ExportableComposition {
        let composition = AVMutableComposition()
        let videoTracks = try createCompositionTracks(for: composition, mediaType: .video)
        let audioTracks = try createCompositionTracks(for: composition, mediaType: .audio)

        var videoTrackMap: [Int: AVMutableCompositionTrack] = [:]
        var audioTrackMap: [Int: AVMutableCompositionTrack] = [:]
        var audioMixParameters: [CMPersistentTrackID: AVMutableAudioMixInputParameters] = [:]

        var segmentsWithContexts: [Segment] = []
        let isSingleClipTimeline = timeline.segments.count == 1

        for segment in timeline.segments {
            let assetContext: ClipAssetContext
            if let existing = segment.assetContext {
                assetContext = existing
            } else {
                assetContext = try await resolveClipContext(for: segment.metadata.clip, index: segment.metadata.index)
            }

            let resolvedTimeRange: CMTimeRange
            if isSingleClipTimeline {
                resolvedTimeRange = CMTimeRange(start: .zero, duration: assetContext.duration)
            } else {
                resolvedTimeRange = segment.timeRange
            }

            let segmentWithContext = Segment(
                clipIndex: segment.clipIndex,
                metadata: segment.metadata,
                assetContext: assetContext,
                timeRange: resolvedTimeRange,
                incomingTransition: segment.incomingTransition,
                outgoingTransition: segment.outgoingTransition,
                motionEffect: segment.motionEffect
            )
            segmentsWithContexts.append(segmentWithContext)

            let clip = segment.metadata.clip
            let sourceStart = CMTime(seconds: clip.trimStart, preferredTimescale: 600)
            let sourceDuration = clip.isTrimmed ? resolvedTimeRange.duration : assetContext.duration
            let sourceRange = CMTimeRange(start: sourceStart, duration: sourceDuration)

            let trackIndex = videoTracks.isEmpty ? 0 : segment.clipIndex % videoTracks.count
            if trackIndex < videoTracks.count {
                let videoTrack = videoTracks[trackIndex]
                try videoTrack.insertTimeRange(sourceRange, of: assetContext.videoTrack, at: resolvedTimeRange.start)
                videoTrackMap[segment.clipIndex] = videoTrack
            }

            let isClipMuted = clip.shouldMuteLiveAudio(tapeDefault: livePhotosMuted)

            if assetContext.hasAudio,
               let sourceAudioTrack = assetContext.audioTrack,
               trackIndex < audioTracks.count {
                let audioTrack = audioTracks[trackIndex]
                try audioTrack.insertTimeRange(sourceRange, of: sourceAudioTrack, at: resolvedTimeRange.start)
                audioTrackMap[segment.clipIndex] = audioTrack

                let key = audioTrack.trackID
                let params = audioMixParameters[key] ?? AVMutableAudioMixInputParameters(track: audioTrack)

                let clipVol = isClipMuted ? Float(0) : Float(clip.volume ?? 1.0)

                if clipVol <= 0 {
                    params.setVolume(0, at: resolvedTimeRange.start)
                } else {
                    params.setVolume(clipVol, at: resolvedTimeRange.start)

                    if let incoming = segment.incomingTransition, incoming.style == .crossfade {
                        let rampRange = CMTimeRange(start: resolvedTimeRange.start, duration: incoming.duration)
                        params.setVolumeRamp(fromStartVolume: 0, toEndVolume: clipVol, timeRange: rampRange)
                    }
                    if let outgoing = segment.outgoingTransition, outgoing.style == .crossfade {
                        let rampStart = CMTimeSubtract(CMTimeAdd(resolvedTimeRange.start, resolvedTimeRange.duration), outgoing.duration)
                        let rampRange = CMTimeRange(start: rampStart, duration: outgoing.duration)
                        params.setVolumeRamp(fromStartVolume: clipVol, toEndVolume: 0, timeRange: rampRange)
                    }
                }

                audioMixParameters[key] = params
            }
        }

        let resolvedTotalDuration: CMTime
        if isSingleClipTimeline, let onlySegment = segmentsWithContexts.first {
            resolvedTotalDuration = onlySegment.timeRange.duration
        } else {
            resolvedTotalDuration = timeline.totalDuration
        }

        let timelineWithContexts = Timeline(
            segments: segmentsWithContexts,
            renderSize: timeline.renderSize,
            totalDuration: resolvedTotalDuration,
            transitionSequence: timeline.transitionSequence
        )

        let videoComposition = AVMutableVideoComposition()

        if enableBlurBackground {
            let blurInstructions = buildBlurVideoInstructions(
                for: timelineWithContexts,
                videoTrackMap: videoTrackMap,
                renderSize: timeline.renderSize,
                tapeScaleMode: tape.scaleMode
            )
            videoComposition.instructions = blurInstructions
            videoComposition.customVideoCompositorClass = BlurredBackgroundCompositor.self
        } else {
            let instructions = buildVideoInstructions(
                for: timelineWithContexts,
                videoTrackMap: videoTrackMap,
                renderSize: timeline.renderSize,
                tapeScaleMode: tape.scaleMode
            )
            videoComposition.instructions = instructions
        }

        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.renderSize = timeline.renderSize

        let audioMix: AVMutableAudioMix?
        if !audioMixParameters.isEmpty {
            let mix = AVMutableAudioMix()
            mix.inputParameters = Array(audioMixParameters.values)
            audioMix = mix
        } else {
            audioMix = nil
        }

        return ExportableComposition(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: audioMix,
            timeline: timelineWithContexts
        )
    }

    // MARK: - Asset Loading

    private func loadAssets(for clips: [Clip]) async throws -> [ClipAssetContext] {
        try await loadAssets(for: clips, startIndex: 0)
    }

    private func loadAssets(for clips: [Clip], startIndex: Int) async throws -> [ClipAssetContext] {
        let chunkSize = 10
        var allContexts: [ClipAssetContext] = []

        for chunkStart in stride(from: 0, to: clips.count, by: chunkSize) {
            let chunkEnd = min(chunkStart + chunkSize, clips.count)
            let chunk = clips[chunkStart..<chunkEnd]

            let chunkContexts = try await withThrowingTaskGroup(of: ClipAssetContext.self) { group in
                for (offset, clip) in chunk.enumerated() {
                    let index = startIndex + chunkStart + offset
                    group.addTask {
                        let resolved = try await self.resolveAsset(for: clip)
                        let asset = resolved.asset
                        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                            throw BuilderError.missingVideoTrack
                        }
                        let duration = try await asset.load(.duration)
                        let naturalSize = try await videoTrack.load(.naturalSize)
                        let preferredTransform = try await videoTrack.load(.preferredTransform)
                        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
                        let shouldMute = clip.shouldMuteLiveAudio(tapeDefault: self.livePhotosMuted)
                        let audioTrack = shouldMute ? nil : audioTracks.first
                        let hasAudio = audioTrack != nil
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

                var results: [ClipAssetContext] = []
                for try await context in group {
                    results.append(context)
                }
                return results
            }

            allContexts.append(contentsOf: chunkContexts)
        }

        return allContexts.sorted { $0.index < $1.index }
    }

    // Asset resolution methods moved to TapeCompositionBuilder+AssetResolution.swift

    @MainActor
    private func makeStillImagePlayerItem(
        cgImage: CGImage,
        clip: Clip,
        duration: CMTime,
        renderSize: CGSize,
        motionEffect: MotionEffect?,
        scaleMode: ScaleMode
    ) async throws -> AVPlayerItem {
        let timingAsset = try await Self.timingAsset()
        guard let timingTrack = try await timingAsset.loadTracks(withMediaType: .video).first else {
            throw BuilderError.missingVideoTrack
        }
        let composition = AVMutableComposition()
        let track = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        let timingDuration = try await timingAsset.load(.duration)
        let timingRange = CMTimeRange(start: .zero, duration: timingDuration)
        try track?.insertTimeRange(timingRange, of: timingTrack, at: .zero)
        if CMTimeCompare(timingDuration, duration) != 0 {
            track?.scaleTimeRange(timingRange, toDuration: duration)
        }

        let rotationTurns = ((clip.rotateQuarterTurns % 4) + 4) % 4
        let instruction = StillImageCompositionInstruction(
            timeRange: CMTimeRange(start: .zero, duration: duration),
            trackID: track?.trackID ?? kCMPersistentTrackID_Invalid,
            renderSize: renderSize,
            image: cgImage,
            imageSize: CGSize(width: cgImage.width, height: cgImage.height),
            rotationTurns: rotationTurns,
            motionEffect: motionEffect,
            scaleMode: scaleMode
        )

        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = StillImageVideoCompositor.self
        videoComposition.instructions = [instruction]
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.renderSize = renderSize

        let playerItem = AVPlayerItem(asset: composition)
        playerItem.videoComposition = videoComposition
        return playerItem
    }

    private static var timingAssetTask: Task<AVAsset, Error>?

    private static func timingAsset() async throws -> AVAsset {
        if let task = timingAssetTask {
            return try await task.value
        }
        let task: Task<AVAsset, Error> = Task {
            let fileManager = FileManager.default
            let url = fileManager.temporaryDirectory.appendingPathComponent("TimingAsset.mov")
            if fileManager.fileExists(atPath: url.path) {
                return AVURLAsset(url: url)
            }
            return try await buildTimingAsset(at: url)
        }
        timingAssetTask = task
        do {
            let asset = try await task.value
            return asset
        } catch {
            timingAssetTask = nil
            throw error
        }
    }

    private static func buildTimingAsset(at url: URL) async throws -> AVAsset {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 2,
            AVVideoHeightKey: 2,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 50_000
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 2,
                kCVPixelBufferHeightKey as String: 2,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        guard let pool = adaptor.pixelBufferPool else {
            throw BuilderError.imageEncodingFailed
        }
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw BuilderError.imageEncodingFailed
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, 0, CVPixelBufferGetDataSize(buffer))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        while !input.isReadyForMoreMediaData {
            await Task.yield()
        }
        adaptor.append(buffer, withPresentationTime: .zero)
        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        if writer.status == .failed {
            throw writer.error ?? BuilderError.imageEncodingFailed
        }
        return AVURLAsset(url: url)
    }

    // MARK: - Metadata Loading (Fast - for timeline building)
    
    private func loadMetadata(for clips: [Clip], startIndex: Int) -> [ClipMetadata] {
        // TIMELINE OPTIMIZATION: No async work needed - just read clip properties synchronously
        // This is instant - no task groups, no PHAsset fetches, just in-memory property access
        return clips.enumerated().map { offset, clip in
            let index = startIndex + offset
            let duration: CMTime
            let motionEffect: MotionEffect?
            
            switch clip.clipType {
            case .video:
                if clip.duration > 0 {
                    let effectiveDuration = clip.trimmedDuration > 0 ? clip.trimmedDuration : clip.duration
                    duration = CMTime(seconds: effectiveDuration, preferredTimescale: 600)
                } else {
                    duration = CMTime(seconds: 1.0, preferredTimescale: 600)
                    TapesLog.player.warning("TapeCompositionBuilder: Clip \(index) missing duration, using default 1.0s")
                }
                motionEffect = nil
                
            case .image:
                let durationSeconds = clip.duration > 0 ? clip.duration : imageConfiguration.defaultDuration
                duration = CMTime(seconds: durationSeconds, preferredTimescale: 600)
                motionEffect = MotionEffect.from(style: clip.motionStyle)
            }
            
            // TIMELINE OPTIMIZATION: naturalSize is nil for timeline building
            // It will be resolved later during playback building when needed
            return ClipMetadata(
                index: index,
                clip: clip,
                duration: duration,
                naturalSize: nil, // Not needed for timeline - resolved on-demand during playback
                motionEffect: motionEffect
            )
        }
    }
    
    // fetchPHAsset moved to TapeCompositionBuilder+AssetResolution.swift

    // MARK: - Transition Handling

    private func buildTransitionDescriptors(for tape: Tape, metadata: [ClipMetadata]) -> [TransitionDescriptor?] {
        guard metadata.count > 1 else { return [] }

        let baseStyle = tape.transition
        let defaultStyles: [TransitionType]
        switch baseStyle {
        case .none, .crossfade, .slideLR, .slideRL:
            defaultStyles = Array(repeating: baseStyle, count: metadata.count - 1)
        case .randomise:
            defaultStyles = generateRandomSequence(boundaries: metadata.count - 1, tapeID: tape.id)
        }

        var descriptors: [TransitionDescriptor?] = []
        descriptors.reserveCapacity(defaultStyles.count)

        for index in 0..<defaultStyles.count {
            let leftClipID = metadata[index].clip.id
            let rightClipID = metadata[index + 1].clip.id
            let seamOverride = tape.seamTransition(leftClipID: leftClipID, rightClipID: rightClipID)

            let style = seamOverride?.style ?? defaultStyles[index]
            let durationSeconds = seamOverride?.duration ?? tape.transitionDuration

            if style == .none {
                descriptors.append(nil)
                continue
            }

            let currentDuration = metadata[index].duration
            let nextDuration = metadata[index + 1].duration
            let maxDurationCurrent = CMTimeMultiplyByFloat64(currentDuration, multiplier: 0.5)
            let maxDurationNext = CMTimeMultiplyByFloat64(nextDuration, multiplier: 0.5)
            let rawDuration = CMTime(seconds: durationSeconds, preferredTimescale: 600)
            let capped = minTime(rawDuration, maxDurationCurrent, maxDurationNext)
            if CMTimeCompare(capped, .zero) <= 0 {
                descriptors.append(nil)
            } else {
                descriptors.append(TransitionDescriptor(style: style, duration: capped))
            }
        }

        return descriptors
    }
    
    private func buildTransitionDescriptors(for tape: Tape, assets: [ClipAssetContext]) -> [TransitionDescriptor?] {
        guard assets.count > 1 else { return [] }

        let baseStyle = tape.transition
        let defaultStyles: [TransitionType]
        switch baseStyle {
        case .none, .crossfade, .slideLR, .slideRL:
            defaultStyles = Array(repeating: baseStyle, count: assets.count - 1)
        case .randomise:
            defaultStyles = generateRandomSequence(boundaries: assets.count - 1, tapeID: tape.id)
        }

        var descriptors: [TransitionDescriptor?] = []
        descriptors.reserveCapacity(defaultStyles.count)

        for index in 0..<defaultStyles.count {
            let leftClipID = assets[index].clip.id
            let rightClipID = assets[index + 1].clip.id
            let seamOverride = tape.seamTransition(leftClipID: leftClipID, rightClipID: rightClipID)

            let style = seamOverride?.style ?? defaultStyles[index]
            let durationSeconds = seamOverride?.duration ?? tape.transitionDuration

            if style == .none {
                descriptors.append(nil)
                continue
            }

            let currentAsset = assets[index]
            let nextAsset = assets[index + 1]

            let maxDurationCurrent = CMTimeMultiplyByFloat64(currentAsset.duration, multiplier: 0.5)
            let maxDurationNext = CMTimeMultiplyByFloat64(nextAsset.duration, multiplier: 0.5)
            let rawDuration = CMTime(seconds: durationSeconds, preferredTimescale: 600)
            let capped = minTime(rawDuration, maxDurationCurrent, maxDurationNext)
            if CMTimeCompare(capped, .zero) <= 0 {
                descriptors.append(nil)
            } else {
                descriptors.append(TransitionDescriptor(style: style, duration: capped))
            }
        }

        return descriptors
    }

    private func buildSegments(for metadata: [ClipMetadata], transitions: [TransitionDescriptor?]) -> [Segment] {
        var segments: [Segment] = []
        segments.reserveCapacity(metadata.count)

        var currentStart = CMTime.zero

        for index in 0..<metadata.count {
            let meta = metadata[index]
            let incomingTransition = index > 0 ? transitions[index - 1] : nil
            let outgoingTransition = index < transitions.count ? transitions[index] : nil

            let duration = meta.duration
            let timeRange = CMTimeRange(start: currentStart, duration: duration)

            let segment = Segment(
                clipIndex: index,
                metadata: meta,
                assetContext: nil, // Will be resolved on-demand during playback building
                timeRange: timeRange,
                incomingTransition: incomingTransition,
                outgoingTransition: outgoingTransition,
                motionEffect: meta.motionEffect
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
    
    private func buildSegments(for metadata: [ClipMetadata], contexts: [ClipAssetContext], transitions: [TransitionDescriptor?]) -> [Segment] {
        var segments = buildSegments(for: metadata, transitions: transitions)
        for (index, context) in contexts.enumerated() {
            segments[index] = Segment(
                clipIndex: segments[index].clipIndex,
                metadata: segments[index].metadata,
                assetContext: context,
                timeRange: segments[index].timeRange,
                incomingTransition: segments[index].incomingTransition,
                outgoingTransition: segments[index].outgoingTransition,
                motionEffect: segments[index].motionEffect
            )
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
        // TIMELINE FIX: Use assetContext if available, otherwise use metadata
        guard let assetContext = segment.assetContext else {
            // Fallback to metadata - this shouldn't happen in playback building, but handle gracefully
            return CGAffineTransform.identity
        }
        let base = baseTransform(
            for: assetContext,
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

    private func effectiveScaleMode(for segment: Segment, tapeScaleMode: ScaleMode, renderSize: CGSize) -> ScaleMode {
        let clip = segment.assetContext?.clip ?? segment.metadata.clip
        if let override = clip.overrideScaleMode {
            return override
        }
        if clip.clipType == .image,
           let naturalSize = segment.metadata.naturalSize,
           naturalSize.width > 0, naturalSize.height > 0,
           renderSize.width > 0, renderSize.height > 0 {
            let imageIsLandscape = naturalSize.width > naturalSize.height
            let renderIsLandscape = renderSize.width > renderSize.height
            return (imageIsLandscape == renderIsLandscape) ? .fill : .fit
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
            let segmentScaleMode = effectiveScaleMode(for: segment, tapeScaleMode: tapeScaleMode, renderSize: renderSize)

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

                let nextScaleMode = effectiveScaleMode(for: nextSegment, tapeScaleMode: tapeScaleMode, renderSize: renderSize)
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

    // MARK: - Blur Video Instructions

    private func buildBlurVideoInstructions(
        for timeline: Timeline,
        videoTrackMap: [Int: AVMutableCompositionTrack],
        renderSize: CGSize,
        tapeScaleMode: ScaleMode
    ) -> [AVVideoCompositionInstructionProtocol] {
        var instructions: [BlurredBackgroundInstruction] = []

        for (index, segment) in timeline.segments.enumerated() {
            guard let track = videoTrackMap[segment.clipIndex] else { continue }
            let segmentScaleMode = effectiveScaleMode(for: segment, tapeScaleMode: tapeScaleMode, renderSize: renderSize)

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
                let timeRange = CMTimeRange(start: passThroughStart, duration: passThroughDuration)
                let passThroughEnd = CMTimeAdd(passThroughStart, passThroughDuration)

                let fitStart = transform(for: segment, renderSize: renderSize, scaleMode: segmentScaleMode, at: passThroughStart)
                let fitEnd = transform(for: segment, renderSize: renderSize, scaleMode: segmentScaleMode, at: passThroughEnd)
                let fillStart = transform(for: segment, renderSize: renderSize, scaleMode: .fill, at: passThroughStart)
                let fillEnd = transform(for: segment, renderSize: renderSize, scaleMode: .fill, at: passThroughEnd)

                let needsBlur = segmentScaleMode == .fit
                    && clipNeedsBlurBackground(segment: segment, renderSize: renderSize)
                let clipRect = (segmentScaleMode == .fit)
                    ? fittedClipRect(for: segment, renderSize: renderSize) : nil

                let layer = BlurredBackgroundInstruction.LayerInfo(
                    trackID: track.trackID,
                    fitStartTransform: fitStart,
                    fitEndTransform: fitEnd,
                    fillStartTransform: fillStart,
                    fillEndTransform: fillEnd,
                    startOpacity: 1.0,
                    endOpacity: 1.0,
                    needsBlurBackground: needsBlur,
                    fitClipRect: clipRect
                )

                instructions.append(BlurredBackgroundInstruction(timeRange: timeRange, layers: [layer]))
            }

            guard let transition = segment.outgoingTransition,
                  let nextSegment = timeline.segments[safe: index + 1],
                  let nextTrack = videoTrackMap[nextSegment.clipIndex] else { continue }

            let transitionStart = CMTimeSubtract(
                CMTimeAdd(segment.timeRange.start, segment.timeRange.duration),
                transition.duration
            )
            let transitionRange = CMTimeRange(start: transitionStart, duration: transition.duration)

            let nextScaleMode = effectiveScaleMode(for: nextSegment, tapeScaleMode: tapeScaleMode, renderSize: renderSize)

            let fromFitStart = transform(for: segment, renderSize: renderSize, scaleMode: segmentScaleMode, at: transitionStart)
            let fromFitEnd = transform(for: segment, renderSize: renderSize, scaleMode: segmentScaleMode, at: CMTimeAdd(transitionStart, transition.duration))
            let toFitStart = transform(for: nextSegment, renderSize: renderSize, scaleMode: nextScaleMode, at: transitionStart)
            let toFitEnd = transform(for: nextSegment, renderSize: renderSize, scaleMode: nextScaleMode, at: CMTimeAdd(transitionStart, transition.duration))

            let fromFillStart = transform(for: segment, renderSize: renderSize, scaleMode: .fill, at: transitionStart)
            let fromFillEnd = transform(for: segment, renderSize: renderSize, scaleMode: .fill, at: CMTimeAdd(transitionStart, transition.duration))
            let toFillStart = transform(for: nextSegment, renderSize: renderSize, scaleMode: .fill, at: transitionStart)
            let toFillEnd = transform(for: nextSegment, renderSize: renderSize, scaleMode: .fill, at: CMTimeAdd(transitionStart, transition.duration))

            let fromNeedsBlur = segmentScaleMode == .fit
                && clipNeedsBlurBackground(segment: segment, renderSize: renderSize)
            let toNeedsBlur = nextScaleMode == .fit
                && clipNeedsBlurBackground(segment: nextSegment, renderSize: renderSize)
            let fromClipRect = (segmentScaleMode == .fit)
                ? fittedClipRect(for: segment, renderSize: renderSize) : nil
            let toClipRect = (nextScaleMode == .fit)
                ? fittedClipRect(for: nextSegment, renderSize: renderSize) : nil

            let fromLayer: BlurredBackgroundInstruction.LayerInfo
            let toLayer: BlurredBackgroundInstruction.LayerInfo

            switch transition.style {
            case .crossfade:
                fromLayer = BlurredBackgroundInstruction.LayerInfo(
                    trackID: track.trackID,
                    fitStartTransform: fromFitStart,
                    fitEndTransform: fromFitEnd,
                    fillStartTransform: fromFillStart,
                    fillEndTransform: fromFillEnd,
                    startOpacity: 1.0,
                    endOpacity: 0.0,
                    needsBlurBackground: fromNeedsBlur,
                    fitClipRect: fromClipRect
                )
                toLayer = BlurredBackgroundInstruction.LayerInfo(
                    trackID: nextTrack.trackID,
                    fitStartTransform: toFitStart,
                    fitEndTransform: toFitEnd,
                    fillStartTransform: toFillStart,
                    fillEndTransform: toFillEnd,
                    startOpacity: 0.0,
                    endOpacity: 1.0,
                    needsBlurBackground: toNeedsBlur,
                    fitClipRect: toClipRect
                )

            case .slideLR, .slideRL:
                let offset = transition.style == .slideLR ? renderSize.width : -renderSize.width

                let fromFitSlideEnd = prependTranslation(to: fromFitStart, dx: -offset, dy: 0)
                let toFitSlideStart = prependTranslation(to: toFitStart, dx: offset, dy: 0)
                let fromFillSlideEnd = prependTranslation(to: fromFillStart, dx: -offset, dy: 0)
                let toFillSlideStart = prependTranslation(to: toFillStart, dx: offset, dy: 0)

                fromLayer = BlurredBackgroundInstruction.LayerInfo(
                    trackID: track.trackID,
                    fitStartTransform: fromFitStart,
                    fitEndTransform: fromFitSlideEnd,
                    fillStartTransform: fromFillStart,
                    fillEndTransform: fromFillSlideEnd,
                    startOpacity: 1.0,
                    endOpacity: 1.0,
                    needsBlurBackground: fromNeedsBlur,
                    fitClipRect: fromClipRect
                )
                toLayer = BlurredBackgroundInstruction.LayerInfo(
                    trackID: nextTrack.trackID,
                    fitStartTransform: toFitSlideStart,
                    fitEndTransform: toFitStart,
                    fillStartTransform: toFillSlideStart,
                    fillEndTransform: toFillStart,
                    startOpacity: 1.0,
                    endOpacity: 1.0,
                    needsBlurBackground: toNeedsBlur,
                    fitClipRect: toClipRect
                )

            case .none, .randomise:
                continue
            }

            instructions.append(BlurredBackgroundInstruction(
                timeRange: transitionRange,
                layers: [toLayer, fromLayer]
            ))
        }

        instructions.sort { CMTimeCompare($0.theTimeRange.start, $1.theTimeRange.start) < 0 }
        return instructions
    }

    private func fittedClipRect(for segment: Segment, renderSize: CGSize) -> CGRect? {
        guard let context = segment.assetContext else { return nil }
        guard segment.motionEffect != nil else { return nil }
        let naturalSize = context.naturalSize.applying(context.preferredTransform)
        let absWidth = abs(naturalSize.width)
        let absHeight = abs(naturalSize.height)
        guard absWidth > 0, absHeight > 0 else { return nil }

        let scaleX = renderSize.width / absWidth
        let scaleY = renderSize.height / absHeight
        let scale = min(scaleX, scaleY)

        let fittedWidth = absWidth * scale
        let fittedHeight = absHeight * scale
        let originX = (renderSize.width - fittedWidth) / 2
        let originY = (renderSize.height - fittedHeight) / 2

        return CGRect(x: originX, y: originY, width: fittedWidth, height: fittedHeight)
    }

    private func clipNeedsBlurBackground(segment: Segment, renderSize: CGSize) -> Bool {
        guard let context = segment.assetContext else { return false }
        let naturalSize = context.naturalSize.applying(context.preferredTransform)
        let absWidth = abs(naturalSize.width)
        let absHeight = abs(naturalSize.height)
        guard absWidth > 0, absHeight > 0 else { return false }

        let scaleX = renderSize.width / absWidth
        let scaleY = renderSize.height / absHeight
        return abs(scaleX - scaleY) > 0.01
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

        let transform = preferred.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        let translatedX = (renderWidth - absWidth * scale) / 2
        let translatedY = (renderHeight - absHeight * scale) / 2
        return transform.concatenating(CGAffineTransform(translationX: translatedX, y: translatedY))
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

// Image handling and asset resolution methods moved to:
// - TapeCompositionBuilder+AssetResolution.swift
// - TapeCompositionBuilder+ImageEncoding.swift
