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
    
    // Placeholder cache: key = "widthxheight-duration" (e.g., "1080x1920-6.0")
    private static var placeholderCache: [String: AVAsset] = [:]

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
        case compositionTrackCreationFailed

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
            case .compositionTrackCreationFailed:
                return "Failed to create composition tracks for video playback."
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
            defaultDuration: 6.0,
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
        
        // Diagnostic metadata (only populated if diagnostics enabled)
        var cleanAperture: CGRect? = nil
        var pixelAspectRatio: CGSize? = nil
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
    
    /// Build composition with placeholders for missing clips (for hybrid loading with seamless rebuilds).
    /// This method builds a complete timeline with placeholder assets for missing clips,
    /// enabling immediate playback and seamless swaps when assets load.
    @MainActor
    func buildPlayerItem(
        for tape: Tape,
        readyAssets: [(Int, HybridAssetLoader.ResolvedAsset)],
        skippedIndices: Set<Int>
    ) async throws -> PlayerComposition {
        let renderSize = renderSize(for: tape.orientation)
        let readyAssetMap = Dictionary(uniqueKeysWithValues: readyAssets)
        
        // Build contexts for ALL clips (ready + placeholders)
        // First, process ready assets in parallel
        var readyContexts: [(Int, ClipAssetContext)] = []
        await withTaskGroup(of: (Int, ClipAssetContext?).self) { group in
            for (index, clip) in tape.clips.enumerated() {
                if let resolved = readyAssetMap[index] {
                    group.addTask {
                        do {
                            let videoTracks = try await resolved.asset.loadTracks(withMediaType: .video)
                            guard let videoTrack = videoTracks.first else {
                                return (index, nil)
                            }
                            
                            let audioTracks = try await resolved.asset.loadTracks(withMediaType: .audio)
                            
                            let context = ClipAssetContext(
                                index: index,
                                clip: resolved.clip,
                                asset: resolved.asset,
                                duration: resolved.duration,
                                naturalSize: resolved.naturalSize,
                                preferredTransform: resolved.preferredTransform,
                                hasAudio: resolved.hasAudio,
                                videoTrack: videoTrack,
                                audioTrack: audioTracks.first,
                                motionEffect: resolved.motionEffect,
                                isTemporaryAsset: resolved.isTemporary
                            )
                            return (index, context)
                        } catch {
                            return (index, nil)
                        }
                    }
                }
            }
            
            for await (index, context) in group {
                if let context = context {
                    readyContexts.append((index, context))
                }
            }
        }
        
        // Collect placeholder requirements (group by duration for better caching)
        var placeholderTasks: [(Int, Double)] = []
        for (index, clip) in tape.clips.enumerated() {
            if readyAssetMap[index] == nil {
                let placeholderDuration = clip.duration > 0 ? clip.duration : (clip.clipType == .image ? imageConfiguration.defaultDuration : 5.0)
                placeholderTasks.append((index, placeholderDuration))
            }
        }
        
        // Create placeholders in parallel (batch of 10 to avoid overwhelming system)
        var placeholderContexts: [(Int, ClipAssetContext)] = []
        let batchSize = 10
        for batchStart in stride(from: 0, to: placeholderTasks.count, by: batchSize) {
            let batch = Array(placeholderTasks[batchStart..<min(batchStart + batchSize, placeholderTasks.count)])
            
            await withTaskGroup(of: (Int, ClipAssetContext?).self) { group in
                for (index, duration) in batch {
                    group.addTask {
                        do {
                            let placeholderAsset = try await self.createPlaceholderAsset(duration: duration, renderSize: renderSize)
                            
                            let videoTracks = try await placeholderAsset.loadTracks(withMediaType: .video)
                            guard let videoTrack = videoTracks.first else {
                                return (index, nil)
                            }
                            
                            let placeholderDurationCM = CMTime(seconds: duration, preferredTimescale: 600)
                            
                            let context = ClipAssetContext(
                                index: index,
                                clip: tape.clips[index],
                                asset: placeholderAsset,
                                duration: placeholderDurationCM,
                                naturalSize: renderSize,
                                preferredTransform: .identity,
                                hasAudio: false,
                                videoTrack: videoTrack,
                                audioTrack: nil,
                                motionEffect: nil,
                                isTemporaryAsset: true
                            )
                            return (index, context)
                        } catch {
                            return (index, nil)
                        }
                    }
                }
                
                for await (index, context) in group {
                    if let context = context {
                        placeholderContexts.append((index, context))
                    }
                }
            }
        }
        
        // Combine and sort by index
        var contexts: [ClipAssetContext] = []
        let allContexts = readyContexts + placeholderContexts
        contexts = allContexts.sorted { $0.0 < $1.0 }.map { $0.1 }
        
        // Build complete timeline (all clips, no gaps)
        let timeline = makeTimeline(for: tape, contexts: contexts)
        return try buildPlayerComposition(for: tape, timeline: timeline)
    }
    
    /// Build timeline accounting for skipped clips - transitions only between consecutive ready clips
    private func makeTimelineWithSkips(
        for tape: Tape,
        contexts: [ClipAssetContext],
        skippedIndices: Set<Int>
    ) -> Timeline {
        guard !contexts.isEmpty else {
            return Timeline(
                segments: [],
                renderSize: renderSize(for: tape.orientation),
                totalDuration: .zero,
                transitionSequence: []
            )
        }
        
        // Build transition descriptors only for consecutive ready clips
        let transitionDescriptors = buildTransitionDescriptorsWithSkips(
            for: tape,
            contexts: contexts,
            skippedIndices: skippedIndices
        )
        
        let segments = buildSegments(for: contexts, transitions: transitionDescriptors)
        let totalDuration = segments.last.map { CMTimeAdd($0.timeRange.start, $0.timeRange.duration) } ?? .zero
        
        return Timeline(
            segments: segments,
            renderSize: renderSize(for: tape.orientation),
            totalDuration: totalDuration,
            transitionSequence: transitionDescriptors
        )
    }
    
    /// Build transition descriptors accounting for skipped clips
    private func buildTransitionDescriptorsWithSkips(
        for tape: Tape,
        contexts: [ClipAssetContext],
        skippedIndices: Set<Int>
    ) -> [TransitionDescriptor?] {
        guard contexts.count > 1 else { return [] }
        
        let baseStyle = tape.transition
        var descriptors: [TransitionDescriptor?] = []
        
        // Only add transitions between consecutive ready clips (no gaps)
        for i in 0..<(contexts.count - 1) {
            let currentIndex = contexts[i].index
            let nextIndex = contexts[i + 1].index
            
            // Check if there are any skipped clips between current and next
            // Only check for gaps if nextIndex > currentIndex + 1 (consecutive clips have no gap)
            let hasGap = (nextIndex > currentIndex + 1) && ((currentIndex + 1)..<nextIndex).contains { skippedIndices.contains($0) }
            
            if hasGap {
                // No transition across skipped clips
                descriptors.append(nil)
            } else {
                // Normal transition logic
                let style: TransitionType
                switch baseStyle {
                case .none, .crossfade, .slideLR, .slideRL:
                    style = baseStyle
                case .randomise:
                    // Use deterministic sequence based on tape ID
                    let allIndices = Array(skippedIndices).sorted()
                    // Generate sequence for all boundaries, then filter
                    let fullSequence = generateRandomSequence(boundaries: tape.clips.count - 1, tapeID: tape.id)
                    style = fullSequence[currentIndex]
                }
                
                let currentAsset = contexts[i]
                let nextAsset = contexts[i + 1]
                
                let maxDurationCurrent = CMTimeMultiplyByFloat64(currentAsset.duration, multiplier: 0.5)
                let maxDurationNext = CMTimeMultiplyByFloat64(nextAsset.duration, multiplier: 0.5)
                let rawDuration = CMTime(seconds: tape.transitionDuration, preferredTimescale: 600)
                let capped = minTime(rawDuration, maxDurationCurrent, maxDurationNext)
                
                if CMTimeCompare(capped, .zero) <= 0 || style == .none {
                    descriptors.append(nil)
                } else {
                    descriptors.append(TransitionDescriptor(style: style, duration: capped))
                }
            }
        }
        
        return descriptors
    }

    func resolveClipContext(for clip: Clip, index: Int) async throws -> ClipAssetContext {
        let contexts = try await loadAssets(for: [clip], startIndex: index)
        guard let context = contexts.first else {
            TapesLog.player.error("TapeCompositionBuilder: No context returned for clip \(index)")
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

        // CRITICAL FIX: Use only 2 tracks like the exporter to prevent overlapping insertions
        // Multiple tracks with overlapping time ranges cause AVFoundation to fail during playback
        guard let videoTrackA = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let videoTrackB = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrackA = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrackB = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw BuilderError.compositionTrackCreationFailed
        }

        var videoTrackMap: [Int: AVMutableCompositionTrack] = [:]
        var audioTrackMap: [Int: AVMutableCompositionTrack] = [:]
        var audioMixParameters: [CMPersistentTrackID: AVMutableAudioMixInputParameters] = [:]

        // Alternate between A and B tracks to prevent overlapping insertions
        var useVideoTrackA = true
        var useAudioTrackA = true

        for segment in timeline.segments {
            let videoTrack = useVideoTrackA ? videoTrackA : videoTrackB
            let sourceRange = CMTimeRange(start: .zero, duration: segment.assetContext.duration)
            try videoTrack.insertTimeRange(sourceRange, of: segment.assetContext.videoTrack, at: segment.timeRange.start)
            videoTrackMap[segment.clipIndex] = videoTrack
            useVideoTrackA.toggle()

            if segment.assetContext.hasAudio, let sourceAudioTrack = segment.assetContext.audioTrack {
                let audioTrack = useAudioTrackA ? audioTrackA : audioTrackB
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
                useAudioTrackA.toggle()
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
                    
                    // Diagnostic: Load clean aperture and pixel aspect ratio if available
                    var cleanAperture: CGRect? = nil
                    var pixelAspectRatio: CGSize? = nil
                    if PlaybackDiagnostics.isEnabled {
                        do {
                            let formatDescriptions = try await videoTrack.load(.formatDescriptions)
                            if let formatDesc = formatDescriptions.first {
                                // Clean aperture extraction
                                if let cleanApertureDict = CMFormatDescriptionGetExtension(formatDesc, extensionKey: kCMFormatDescriptionExtension_CleanAperture) as? [String: Any] {
                                    if let width = cleanApertureDict["Width"] as? CGFloat,
                                       let height = cleanApertureDict["Height"] as? CGFloat,
                                       let horizontalOffset = cleanApertureDict["HorizontalOffset"] as? CGFloat,
                                       let verticalOffset = cleanApertureDict["VerticalOffset"] as? CGFloat {
                                        cleanAperture = CGRect(
                                            x: horizontalOffset,
                                            y: verticalOffset,
                                            width: width,
                                            height: height
                                        )
                                    }
                                }
                                
                                // Pixel aspect ratio extraction
                                if let parDict = CMFormatDescriptionGetExtension(formatDesc, extensionKey: kCMFormatDescriptionExtension_PixelAspectRatio) as? [String: Any] {
                                    let parWidth = (parDict["HorizontalSpacing"] as? Int) ?? 1
                                    let parHeight = (parDict["VerticalSpacing"] as? Int) ?? 1
                                    pixelAspectRatio = CGSize(width: CGFloat(parWidth), height: CGFloat(parHeight))
                                }
                                // Default to 1:1 if not found
                                if pixelAspectRatio == nil {
                                    pixelAspectRatio = CGSize(width: 1, height: 1)
                                }
                            }
                        } catch {
                            // Silently fail - these are diagnostic only
                        }
                    }
                    
                    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
                    let audioTrack = audioTracks.first
                    let hasAudio = !audioTracks.isEmpty
                    var context = ClipAssetContext(
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
                    // Set diagnostic metadata
                    context.cleanAperture = cleanAperture
                    context.pixelAspectRatio = pixelAspectRatio
                    return context
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
            let asset = try await createVideoAsset(from: image, clip: clip, duration: durationSeconds)
            return ResolvedAsset(
                asset: asset,
                isTemporary: true,
                motionEffect: imageConfiguration.defaultMotionEffect
            )
        }
    }

    private static func fetchAVAssetFromPhotos(localIdentifier: String) async throws -> AVAsset {
        let fetchStartTime = Date()
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw BuilderError.photosAccessDenied
        }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let phAsset = fetchResult.firstObject else {
            throw BuilderError.photosAssetMissing
        }
        
        // Log asset properties to understand what we're fetching
        let mediaType = phAsset.mediaType == .video ? "video" : "unknown"
        let duration = phAsset.duration
        let creationDate = phAsset.creationDate?.description ?? "unknown"
        let modificationDate = phAsset.modificationDate?.description ?? "unknown"
        let pixelWidth = phAsset.pixelWidth
        let pixelHeight = phAsset.pixelHeight
        let isInCloud = phAsset.location == nil ? "likely_iCloud" : "local"

        TapesLog.player.info("TapeCompositionBuilder: [\(localIdentifier)] Starting fetch - type: \(mediaType), duration: \(String(format: "%.2f", duration))s, size: \(pixelWidth)x\(pixelHeight), created: \(creationDate), modified: \(modificationDate), location: \(isInCloud)")

        // Use high quality delivery mode for better resolution
        let options = PHVideoRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat  // Full quality, not fast format
        options.isNetworkAccessAllowed = true

        TapesLog.player.info("TapeCompositionBuilder: [\(localIdentifier)] Initiating PHImageManager request...")

        // Match old working approach exactly - simple continuation without DispatchQueue wrapper
        // The old code used semaphore synchronously - we use async continuation instead
        // But keep it simple - no nested async contexts
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AVAsset, Error>) in
            var hasResumed = false
            var firstCallbackTime: Date?
            var callbackCount = 0

            // Set up a timer to detect slow requests
            let slowRequestTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { timer in
                let elapsed = Date().timeIntervalSince(fetchStartTime)
                if !hasResumed && callbackCount == 0 {
                    TapesLog.player.warning("TapeCompositionBuilder: [\(localIdentifier)] Still no callbacks after \(String(format: "%.1f", elapsed))s - possible slow asset or sandbox issue")
                } else if !hasResumed {
                    TapesLog.player.info("TapeCompositionBuilder: [\(localIdentifier)] Received \(callbackCount) callbacks, still waiting after \(String(format: "%.1f", elapsed))s")
                } else {
                    timer.invalidate()
                }
            }

            PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { asset, audioMix, info in
                callbackCount += 1
                guard !hasResumed else { return }
                
                let callbackTime = Date()
                if firstCallbackTime == nil {
                    firstCallbackTime = callbackTime
                    let timeToFirstCallback = callbackTime.timeIntervalSince(fetchStartTime)
                    TapesLog.player.info("TapeCompositionBuilder: [\(localIdentifier)] First callback after \(String(format: "%.2f", timeToFirstCallback))s")
                }
                
                // Log detailed info about the request state
                if let info = info {
                    let isInCloud = (info[PHImageResultIsInCloudKey] as? Bool) ?? false
                    let isDegraded = (info[PHImageResultIsDegradedKey] as? Bool) ?? false
                    let cancelled = (info[PHImageCancelledKey] as? Bool) ?? false
                    let requestID = info[PHImageResultRequestIDKey] as? Int32
                    
                    if isInCloud {
                        TapesLog.player.info("TapeCompositionBuilder: [\(localIdentifier)] Asset is in iCloud, downloading...")
                    }
                    if isDegraded {
                        TapesLog.player.warning("TapeCompositionBuilder: [\(localIdentifier)] Received degraded asset, waiting for full quality...")
                    }
                    if cancelled {
                        TapesLog.player.warning("TapeCompositionBuilder: [\(localIdentifier)] Request was cancelled")
                    }
                    
                    // Log any errors
                    if let error = info[PHImageErrorKey] as? Error {
                        let errorCode = (error as NSError).code
                        let errorDomain = (error as NSError).domain
                        TapesLog.player.error("TapeCompositionBuilder: [\(localIdentifier)] Photos error - domain: \(errorDomain), code: \(errorCode), description: \(error.localizedDescription)")
                    }
                }
                
                if let asset = asset {
                    hasResumed = true
                    slowRequestTimer.invalidate()
                    let totalTime = callbackTime.timeIntervalSince(fetchStartTime)

                    // Log asset properties
                    if let urlAsset = asset as? AVURLAsset {
                        let fileName = urlAsset.url.lastPathComponent
                        let fileSize = (try? FileManager.default.attributesOfItem(atPath: urlAsset.url.path)[.size] as? Int64) ?? 0
                        let fileSizeMB = Double(fileSize) / (1024 * 1024)
                        TapesLog.player.info("TapeCompositionBuilder: [\(localIdentifier)] ✓ Success in \(String(format: "%.2f", totalTime))s - file: \(fileName), size: \(String(format: "%.2f", fileSizeMB))MB")
                    } else {
                        TapesLog.player.info("TapeCompositionBuilder: [\(localIdentifier)] ✓ Success in \(String(format: "%.2f", totalTime))s")
                    }

                    continuation.resume(returning: asset)
                } else if let info = info,
                          let error = info[PHImageErrorKey] as? Error {
                    hasResumed = true
                    slowRequestTimer.invalidate()
                    let totalTime = callbackTime.timeIntervalSince(fetchStartTime)
                    let errorCode = (error as NSError).code
                    TapesLog.player.error("TapeCompositionBuilder: [\(localIdentifier)] ✗ Failed after \(String(format: "%.2f", totalTime))s - error code: \(errorCode), description: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                } else {
                    // Check if this is a degraded callback - wait for full quality
                    if let info = info,
                       let isDegraded = info[PHImageResultIsDegradedKey] as? Bool,
                       isDegraded {
                        // Don't resume yet - wait for full quality callback
                        TapesLog.player.info("TapeCompositionBuilder: [\(localIdentifier)] Degraded callback, waiting for full quality...")
                        return
                    }
                    
                    hasResumed = true
                    slowRequestTimer.invalidate()
                    let totalTime = callbackTime.timeIntervalSince(fetchStartTime)
                    TapesLog.player.error("TapeCompositionBuilder: [\(localIdentifier)] ✗ Failed after \(String(format: "%.2f", totalTime))s - Photos returned nil asset with no error")
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
                TapesLog.player.info("TapeCompositionBuilder: Using local file for video")
                let accessibleURL = try Self.accessibleURL(for: clip, url: localURL)
                return AVURLAsset(url: accessibleURL)
            } else {
                TapesLog.player.info("TapeCompositionBuilder: Local file not found, checking cache")
                let cachedURL = Self.cachedURL(for: clip, originalURL: localURL)
                if fileManager.fileExists(atPath: cachedURL.path) {
                    TapesLog.player.info("TapeCompositionBuilder: Using cached file for video")
                    return AVURLAsset(url: cachedURL)
                }
            }
        }

        if let assetLocalId = clip.assetLocalId {
            TapesLog.player.info("TapeCompositionBuilder: Fetching video from Photos: \(assetLocalId)")
            return try await Self.fetchAVAssetFromPhotos(localIdentifier: assetLocalId)
        }

        TapesLog.player.error("TapeCompositionBuilder: No video asset available for clip")
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
    
    /// Clean up stale cache files that might cause AVFoundation errors
    static func cleanupStaleCache() {
        let fileManager = FileManager.default
        let cacheDirectory = fileManager.temporaryDirectory.appendingPathComponent("PlaybackCache", isDirectory: true)
        
        guard fileManager.fileExists(atPath: cacheDirectory.path) else { return }
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey], options: [])
            
            let now = Date()
            let maxAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days
            
            var cleanedCount = 0
            for url in contents {
                // Check if file is older than maxAge or doesn't exist anymore
                if let modDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                    if now.timeIntervalSince(modDate) > maxAge {
                        try? fileManager.removeItem(at: url)
                        cleanedCount += 1
                    }
                } else {
                    // File metadata unavailable - might be corrupted, remove it
                    try? fileManager.removeItem(at: url)
                    cleanedCount += 1
                }
            }
            
            if cleanedCount > 0 {
                TapesLog.player.info("TapeCompositionBuilder: Cleaned up \(cleanedCount) stale cache files")
            }
        } catch {
            // If cleanup fails, try removing the entire cache directory and recreating it
            TapesLog.player.warning("TapeCompositionBuilder: Cache cleanup failed, removing cache directory: \(error.localizedDescription)")
            try? fileManager.removeItem(at: cacheDirectory)
        }
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
                clipIndex: assetContext.index, // Use the actual clip index from context, not array index
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

            // Clamp transition duration to prevent issues
            let maxTransitionDuration: Double = 0.2 // Based on user testing: 0.2s works, 0.3s fails
            
            // Get outgoing transition duration (clamped)
            let rawOutgoingDuration = segment.outgoingTransition?.duration ?? .zero
            let outgoingDuration = CMTimeCompare(rawOutgoingDuration, .zero) > 0 ?
                CMTime(seconds: min(CMTimeGetSeconds(rawOutgoingDuration), maxTransitionDuration), preferredTimescale: 600) :
                .zero

            // Check if there's a transition from the previous segment
            let hasIncomingTransition = index > 0 && timeline.segments[safe: index - 1]?.outgoingTransition != nil
            let incomingDuration = hasIncomingTransition ?
                (timeline.segments[safe: index - 1]?.outgoingTransition?.duration ?? .zero) :
                .zero
            let clampedIncomingDuration = CMTimeCompare(incomingDuration, .zero) > 0 ?
                CMTime(seconds: min(CMTimeGetSeconds(incomingDuration), maxTransitionDuration), preferredTimescale: 600) :
                .zero

            // Calculate segment instruction start and duration
            // If there's an incoming transition, the segment instruction starts after it
            // If there's an outgoing transition, the segment instruction ends before it
            var segmentStart = segment.timeRange.start
            var segmentDuration = segment.timeRange.duration

            if CMTimeCompare(clampedIncomingDuration, .zero) > 0 {
                segmentStart = CMTimeAdd(segmentStart, clampedIncomingDuration)
                segmentDuration = CMTimeSubtract(segmentDuration, clampedIncomingDuration)
            }
            if CMTimeCompare(outgoingDuration, .zero) > 0 {
                segmentDuration = CMTimeSubtract(segmentDuration, outgoingDuration)
            }

            // Create transition instruction at the boundary (if there's an incoming transition)
            // This matches the exporter's approach: one transition instruction per boundary
            if CMTimeCompare(clampedIncomingDuration, .zero) > 0,
               let prevSegment = timeline.segments[safe: index - 1],
               let prevTrack = videoTrackMap[prevSegment.clipIndex],
               let transition = prevSegment.outgoingTransition {
                let transitionStart = segment.timeRange.start
                let transitionRange = CMTimeRange(start: transitionStart, duration: clampedIncomingDuration)

                let prevScaleMode = effectiveScaleMode(for: prevSegment, tapeScaleMode: tapeScaleMode)

                let fromLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: prevTrack)
                let toLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)

                // Set base transforms
                let prevTransform = transform(for: prevSegment, renderSize: renderSize, scaleMode: prevScaleMode, at: transitionStart)
                let currentTransform = transform(for: segment, renderSize: renderSize, scaleMode: segmentScaleMode, at: transitionStart)
                fromLayer.setTransform(prevTransform, at: transitionStart)
                toLayer.setTransform(currentTransform, at: transitionStart)

                // Apply transition ramps
                configureTransition(
                    transition,
                    fromSegment: prevSegment,
                    toSegment: segment,
                    fromLayer: fromLayer,
                    toLayer: toLayer,
                    transitionRange: transitionRange,
                    renderSize: renderSize,
                    fromScaleMode: prevScaleMode,
                    toScaleMode: segmentScaleMode
                )

                let transitionInstruction = AVMutableVideoCompositionInstruction()
                transitionInstruction.timeRange = transitionRange
                transitionInstruction.layerInstructions = [toLayer, fromLayer] // Incoming on top, outgoing on bottom
                instructions.append(transitionInstruction)
            }

            // Create segment instruction (non-overlapping part)
            if CMTimeCompare(segmentDuration, CMTime(seconds: 0.001, preferredTimescale: 600)) > 0 {
                let instruction = AVMutableVideoCompositionInstruction()
                instruction.timeRange = CMTimeRange(start: segmentStart, duration: segmentDuration)

                let layerInstruction = baseLayerInstruction(
                    for: segment,
                    track: track,
                    renderSize: renderSize,
                    scaleMode: segmentScaleMode,
                    at: segmentStart
                )
                layerInstruction.setOpacity(1.0, at: segmentStart)
                layerInstruction.setOpacity(1.0, at: CMTimeAdd(segmentStart, segmentDuration))

                applyTransformRampIfNeeded(
                    on: layerInstruction,
                    for: segment,
                    renderSize: renderSize,
                    scaleMode: segmentScaleMode,
                    startTime: segmentStart,
                    endTime: CMTimeAdd(segmentStart, segmentDuration)
                )
                instruction.layerInstructions = [layerInstruction]
                instructions.append(instruction)
            }
        }

        instructions.sort { CMTimeCompare($0.timeRange.start, $1.timeRange.start) < 0 }

        // Log instruction count for diagnostics
        let singleLayerCount = instructions.filter { $0.layerInstructions.count == 1 }.count
        let transitionCount = instructions.filter { $0.layerInstructions.count > 1 }.count
        TapesLog.player.info("TapeCompositionBuilder: Created \(instructions.count) video instructions (\(singleLayerCount) segment, \(transitionCount) transitions) for \(timeline.segments.count) segments")

        // Validate instruction coverage
        if !instructions.isEmpty {
            var lastEnd = CMTime.zero
            var gaps: [CMTimeRange] = []
            var overlaps: [CMTimeRange] = []

            for instruction in instructions {
                let start = instruction.timeRange.start
                let end = CMTimeAdd(start, instruction.timeRange.duration)

                if CMTimeCompare(start, lastEnd) > 0 {
                    let gapDuration = CMTimeSubtract(start, lastEnd)
                    gaps.append(CMTimeRange(start: lastEnd, duration: gapDuration))
                } else if CMTimeCompare(start, lastEnd) < 0 {
                    let overlapDuration = CMTimeSubtract(lastEnd, start)
                    overlaps.append(CMTimeRange(start: start, duration: overlapDuration))
                }

                lastEnd = CMTimeMaximum(lastEnd, end)
            }

            if !gaps.isEmpty {
                TapesLog.player.warning("TapeCompositionBuilder: Found \(gaps.count) gaps in video instructions")
                for (index, gap) in gaps.prefix(3).enumerated() {
                    let gapStart = CMTimeGetSeconds(gap.start)
                    let gapDuration = CMTimeGetSeconds(gap.duration)
                    TapesLog.player.warning("TapeCompositionBuilder: Gap \(index + 1): start=\(String(format: "%.2f", gapStart))s, duration=\(String(format: "%.2f", gapDuration))s")
                }
            }

            if !overlaps.isEmpty {
                TapesLog.player.warning("TapeCompositionBuilder: Found \(overlaps.count) overlaps in video instructions")
                for (index, overlap) in overlaps.prefix(3).enumerated() {
                    let overlapStart = CMTimeGetSeconds(overlap.start)
                    let overlapDuration = CMTimeGetSeconds(overlap.duration)
                    TapesLog.player.warning("TapeCompositionBuilder: Overlap \(index + 1): start=\(String(format: "%.2f", overlapStart))s, duration=\(String(format: "%.2f", overlapDuration))s")
                }
            }
        }

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
        // CRITICAL FIX: Set opacity to 1.0 at the time point
        // For transitions, configureTransition will override this with ramps
        // For pass-through, opacity is set at both start and end in buildVideoInstructions
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
            // CRITICAL FIX: Match exporter approach - only handle opacity, transforms stay static
            // If transforms change during transition (motion effects), we need to animate them
            // Set opacity ramps (toLayer starts at 0.0, fromLayer starts at 1.0)
            fromLayer.setOpacityRamp(fromStartOpacity: 1.0, toEndOpacity: 0.0, timeRange: transitionRange)
            toLayer.setOpacityRamp(fromStartOpacity: 0.0, toEndOpacity: 1.0, timeRange: transitionRange)
            
            // CRITICAL: Set transforms at BOTH start and end explicitly
            // This ensures AVFoundation knows the full transform range, even if no motion effects
            let transitionEnd = CMTimeAdd(transitionRange.start, transitionRange.duration)
            
            // Set transforms at start
            fromLayer.setTransform(fromStartTransform, at: transitionRange.start)
            toLayer.setTransform(toStartTransform, at: transitionRange.start)
            
            // If transforms change during transition (motion effects), animate them
            // Otherwise, just set at end to ensure AVFoundation has explicit boundary values
            if fromStartTransform != fromEndTransform {
                fromLayer.setTransformRamp(fromStart: fromStartTransform, toEnd: fromEndTransform, timeRange: transitionRange)
            } else {
                fromLayer.setTransform(fromStartTransform, at: transitionEnd)
            }
            
            if toStartTransform != toEndTransform {
                toLayer.setTransformRamp(fromStart: toStartTransform, toEnd: toEndTransform, timeRange: transitionRange)
            } else {
                toLayer.setTransform(toStartTransform, at: transitionEnd)
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
        // CRITICAL FIX: Match exporter approach exactly
        // Exporter only animates incoming layer, outgoing stays in place
        // Use proper concatenating() instead of prependTranslation (which just adds to tx/ty)
        let width = renderSize.width
        let startX: CGFloat = direction == .leftToRight ? -width : width
        let transitionEnd = CMTimeAdd(transitionRange.start, transitionRange.duration)
        
        // Calculate incoming start transform (off-screen position)
        let incomingStartTransform = toTransform.concatenating(CGAffineTransform(translationX: startX, y: 0))
        
        // Outgoing layer: stays in place, just fades out (like exporter)
        fromLayer.setOpacityRamp(fromStartOpacity: 1.0, toEndOpacity: 0.85, timeRange: transitionRange)
        fromLayer.setTransform(fromTransform, at: transitionRange.start)
        fromLayer.setTransform(fromTransform, at: transitionEnd) // Explicitly set at end too
        
        // Incoming layer: slides in from off-screen to final position (like exporter)
        // CRITICAL: Set transform at start explicitly, then ramp to final position
        toLayer.setOpacityRamp(fromStartOpacity: 0.85, toEndOpacity: 1.0, timeRange: transitionRange)
        toLayer.setTransform(incomingStartTransform, at: transitionRange.start) // Explicit start position
        toLayer.setTransformRamp(fromStart: incomingStartTransform, toEnd: toTransform, timeRange: transitionRange)
        toLayer.setTransform(toTransform, at: transitionEnd) // Explicit end position
    }

    private func baseTransform(
        for context: ClipAssetContext,
        renderSize: CGSize,
        scaleMode: ScaleMode
    ) -> CGAffineTransform {
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

        // OPTION A: Match TapeExporter approach - use concatenating() instead of scaledBy()
        // This matches the working export code exactly
        var transform = preferred
        transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        let translatedX = (renderWidth - absWidth * scale) / 2
        let translatedY = (renderHeight - absHeight * scale) / 2
        transform = transform.concatenating(CGAffineTransform(translationX: translatedX, y: translatedY))
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
        // CRITICAL: For Photos assets, always fetch from Photos to get full resolution
        // Don't use cached imageData which may be compressed JPEG (0.8 quality)
        if let assetLocalId = clip.assetLocalId {
            return try await fetchImageFromPhotos(localIdentifier: assetLocalId)
        }
        
        // For non-Photos images, use cached data or local file
        if let data = clip.imageData, let image = UIImage(data: data) {
            return image
        }
        if let url = clip.localURL, let image = UIImage(contentsOfFile: url.path) {
            return image
        }
        
        throw BuilderError.assetUnavailable(clipID: clip.id)
    }

    func fetchImageFromPhotos(localIdentifier: String) async throws -> UIImage {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw BuilderError.photosAccessDenied
        }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else {
            throw BuilderError.photosAssetMissing
        }
        
        // CRITICAL MEMORY FIX: Request reasonable size instead of maximum
        // Render size is 1080x1920 (portrait) or 1920x1080 (landscape)
        // Request 2x render size for excellent quality without excessive memory
        // This caps images at ~2160x3840 instead of 4284x5712, saving ~60% memory
        let maxTargetSize = CGSize(width: 2160, height: 3840) // 2x portrait render size
        
        // Use high quality delivery mode but with reasonable target size
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat  // High quality, not opportunistic
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.resizeMode = .fast  // Allow resizing for memory efficiency
        
        // Request image at reasonable size (Photos will scale down if larger)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UIImage, Error>) in
            var hasResumed = false
            var finalImage: UIImage?
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: maxTargetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                guard !hasResumed else { return }
                
                // Check if this is a degraded (low quality) version
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if isDegraded {
                    // Store degraded version as fallback, but wait for full quality
                    finalImage = image
                    TapesLog.player.info("TapeCompositionBuilder: Received degraded image, waiting for full quality...")
                    return
                }
                
                // Got full quality version
                hasResumed = true
                if let image = image {
                    let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
                    TapesLog.player.info("TapeCompositionBuilder: Received image (\(Int(pixelSize.width))x\(Int(pixelSize.height)))")
                    continuation.resume(returning: image)
                } else if let error = info?[PHImageErrorKey] as? Error {
                    TapesLog.player.error("TapeCompositionBuilder: Image error: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                } else if let cancelled = info?[PHImageCancelledKey] as? NSNumber, cancelled.boolValue {
                    continuation.resume(throwing: BuilderError.photosAssetMissing)
                } else {
                    // Fallback to degraded if available, otherwise error
                    if let degraded = finalImage {
                        TapesLog.player.warning("TapeCompositionBuilder: Using degraded image as fallback")
                        continuation.resume(returning: degraded)
                    } else {
                        TapesLog.player.error("TapeCompositionBuilder: Image returned nil with no error")
                        continuation.resume(throwing: BuilderError.photosAssetMissing)
                    }
                }
            }
        }
    }

    func createVideoAsset(from image: UIImage, clip: Clip, duration: Double) async throws -> AVAsset {
        // CRITICAL MEMORY FIX: Extract CGImage early and allow UIImage to be deallocated
        // The UIImage can be large (especially Photos assets), so we extract the CGImage
        // and let the UIImage be freed before encoding starts
        let cgImage = try normalizedCGImage(from: image, clip: clip)
        // UIImage can now be deallocated - we only need the CGImage for encoding
        let rotationTurns = ((clip.rotateQuarterTurns % 4) + 4) % 4
        
        // Use high resolution but cap at reasonable maximum (4K) for performance
        // 2x render size gives excellent quality without overkill
        // Render size is 1080x1920 (portrait) or 1920x1080 (landscape)
        let maxRenderSize = CGSize(width: 1920, height: 1920) // Use square max for both orientations
        let maxEncodeSize = CGSize(width: maxRenderSize.width * 2, height: maxRenderSize.height * 2) // 2x = 3840x3840
        
        let swapAxes = rotationTurns % 2 != 0
        let baseWidth = CGFloat(cgImage.width)
        let baseHeight = CGFloat(cgImage.height)
        let rotatedWidth = swapAxes ? baseHeight : baseWidth
        let rotatedHeight = swapAxes ? baseWidth : baseHeight
        
        // Cap at max encode size but preserve aspect ratio
        let scale = min(1.0, min(maxEncodeSize.width / rotatedWidth, maxEncodeSize.height / rotatedHeight))
        let targetWidth = makeEvenDimension(rotatedWidth * scale)
        let targetHeight = makeEvenDimension(rotatedHeight * scale)
        let targetSize = CGSize(width: CGFloat(targetWidth), height: CGFloat(targetHeight))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        // Calculate bitrate based on resolution (higher for larger images)
        // Formula: width * height * 0.1 gives good quality for static images
        let pixelCount = targetWidth * targetHeight
        let bitrate = max(10_000_000, pixelCount / 100) // At least 10 Mbps, scale with resolution

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: targetWidth,
            AVVideoHeightKey: targetHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoMaxKeyFrameIntervalKey: 30,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
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

        // CRITICAL OPTIMIZATION: Encode static frames to match duration (not animated frames)
        // Ken Burns animation is already applied via AVVideoCompositionLayerInstruction transforms
        // (see applyTransformRampIfNeeded - it handles all pan/zoom animation at playback time)
        // 
        // Key insight: We need enough frames to cover the clip duration, but we can:
        // 1. Use VERY low frame rate (1-2fps) - video playback rate is overridden by composition
        // 2. Encode the same static frame repeated (no motion baked in)
        // 3. This is still ~45x faster than 30fps (4s clip: 4 frames vs 120 frames)
        //
        // The composition's frameDuration (30fps) will determine actual playback smoothness,
        // not the encoded frame rate. So we can encode at 1fps and playback is still smooth.
        let encodedFrameRate: Int32 = 1 // Very low rate - just enough to cover duration
        let frameDuration = CMTime(value: 1, timescale: encodedFrameRate)
        let totalFrames = max(1, Int(ceil(duration * Double(encodedFrameRate))))
        
        // Encoding image to video (Ken Burns via composition transforms)
        
        guard let pixelBufferPool = adaptor.pixelBufferPool else {
            throw BuilderError.imageEncodingFailed
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        // OPTIMIZATION: Only 2 frames needed (minimal video track for AVComposition)
        // Ken Burns animation handled by AVVideoCompositionLayerInstruction transforms
        // Rendering same image twice is fast (~0.01s total) - negligible overhead
        for frameIndex in 0..<totalFrames {
            let time = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
            
            // OPTIMIZATION: Use async yield instead of blocking sleep
            // Allows other tasks to run while waiting for encoder
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 100_000) // 0.1ms yield
            }

            var pixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &pixelBuffer)
            guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
                continue
            }

            // Render same image (static frame) - transforms will animate during playback
            // Use high quality rendering
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
        // OPTIMIZATION: Use async/await instead of blocking semaphore
        // This allows other tasks to run while encoding finishes
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                continuation.resume()
            }
        }
        return AVURLAsset(url: url)
    }

    func normalizedCGImage(from image: UIImage, clip: Clip) throws -> CGImage {
        if image.imageOrientation == .up, let cgImage = image.cgImage {
            return cgImage
        }

        // Preserve full resolution - use actual pixel dimensions with scale
        let pixelSize = CGSize(
            width: max(image.size.width * image.scale, 1),
            height: max(image.size.height * image.scale, 1)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale  // Preserve original scale for quality
        format.opaque = false
        format.preferredRange = .extended  // Use extended color range for better quality

        let renderer = UIGraphicsImageRenderer(size: pixelSize, format: format)
        let rendered = renderer.image { context in
            // Use high quality rendering
            context.cgContext.interpolationQuality = .high
            image.draw(in: CGRect(origin: .zero, size: pixelSize))
        }

        guard let cgImage = rendered.cgImage else {
            throw BuilderError.assetUnavailable(clipID: clip.id)
        }
        return cgImage
    }
    
    // MARK: - Placeholder Asset Creation
    
    /// Creates a black video placeholder asset for missing clips.
    /// Cached by (renderSize, duration) to avoid recreating identical placeholders.
    func createPlaceholderAsset(duration: Double, renderSize: CGSize) async throws -> AVAsset {
        let key = "\(Int(renderSize.width))x\(Int(renderSize.height))-\(duration)"
        
        // Check cache
        if let cached = Self.placeholderCache[key] {
            return cached
        }
        
        // Create black video asset
        let targetWidth = Int(renderSize.width)
        let targetHeight = Int(renderSize.height)
        
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("placeholder-\(key)-\(UUID().uuidString)")
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
        
        // Minimal encoding: 2 frames at 1fps (same as image encoding)
        let encodedFrameRate: Int32 = 1
        let frameDuration = CMTime(value: 1, timescale: encodedFrameRate)
        let totalFrames = max(2, Int(ceil(duration * Double(encodedFrameRate))))
        
        guard let pixelBufferPool = adaptor.pixelBufferPool else {
            throw BuilderError.imageEncodingFailed
        }
        
        // Render black frames
        for frameIndex in 0..<totalFrames {
            let time = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
            
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 100_000) // 0.1ms yield
            }
            
            var pixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &pixelBuffer)
            guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
                continue
            }
            
            // Fill with black (RGB: 0,0,0)
            CVPixelBufferLockBaseAddress(buffer, [])
            defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
            
            let baseAddress = CVPixelBufferGetBaseAddress(buffer)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            let height = CVPixelBufferGetHeight(buffer)
            
            // Clear buffer (black = zeros)
            if let baseAddress = baseAddress {
                memset(baseAddress, 0, bytesPerRow * height)
            }
            
            adaptor.append(buffer, withPresentationTime: time)
        }
        
        input.markAsFinished()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                continuation.resume()
            }
        }
        
        let asset = AVURLAsset(url: url)
        
        // Cache for reuse
        Self.placeholderCache[key] = asset
        
        return asset
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
        context.interpolationQuality = .high  // High quality interpolation

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
