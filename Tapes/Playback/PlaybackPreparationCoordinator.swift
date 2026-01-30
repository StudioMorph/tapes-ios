import Foundation
import AVFoundation

final class PlaybackPreparationCoordinator {
    enum SkipReason: String {
        case timeout
        case error
    }

    struct PreparedClip {
        let index: Int
        let status: Status
        let duration: TimeInterval

        enum Status {
            case ready(TapeCompositionBuilder.ClipAssetContext)
            case skipped(SkipReason)
        }
    }

    struct PreparedResult {
        let composition: TapeCompositionBuilder.PlayerComposition
        let preparedClips: [PreparedClip]
    }

    enum CoordinatorError: Error, LocalizedError {
        case noPlayableClips

        var errorDescription: String? {
            switch self {
            case .noPlayableClips:
                return "No playable clips are available yet."
            }
        }
    }

    private let builder: TapeCompositionBuilder
    private let warmupWindowSize: Int
    private let warmupTimeout: TimeInterval
    private let sequentialTimeout: TimeInterval
    private var cache: [Int: CachedContext] = [:]
    private var currentTask: Task<Void, Never>?
    private var sourceTape: Tape?
    private var clips: [Clip] = []

    private struct CachedContext {
        let clipID: UUID
        let updatedAt: Date
        let context: TapeCompositionBuilder.ClipAssetContext
    }

    init(
        builder: TapeCompositionBuilder = TapeCompositionBuilder(),
        warmupWindowSize: Int = 5,
        warmupTimeout: TimeInterval = .infinity, // LOADING FIX: Remove timeout - let all assets load
        sequentialTimeout: TimeInterval = .infinity // LOADING FIX: Remove timeout - let all assets load
    ) {
        self.builder = builder
        self.warmupWindowSize = warmupWindowSize
        self.warmupTimeout = warmupTimeout
        self.sequentialTimeout = sequentialTimeout
    }

    func prepare(
        tape: Tape,
        onWarmupReady: @escaping (PreparedResult) -> Void,
        onProgress: @escaping (PreparedResult) -> Void,
        onCompletion: @escaping (PreparedResult) -> Void,
        onSkip: @escaping (SkipReason, Int) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        currentTask?.cancel()
        cache.removeAll()
        sourceTape = tape
        clips = tape.clips

        currentTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let warmupClips = try await self.performWarmup(onSkip: onSkip)
                if let warmupResult = try? await self.buildResult(using: warmupClips, tape: tape) {
                    onWarmupReady(warmupResult)
                }
                try Task.checkCancellation()
                try await self.performContinuation(
                    warmupClips: warmupClips,
                    onProgress: onProgress,
                    onCompletion: onCompletion,
                    onSkip: onSkip
                )
            } catch is CancellationError {
                return
            } catch {
                onError(error)
            }
        }
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        // MEMORY FIX: Clear cache to release AVAsset references
        cache.removeAll()
        sourceTape = nil
        clips = []
    }

    private func performWarmup(onSkip: @escaping (SkipReason, Int) -> Void) async throws -> [PreparedClip] {
        guard !clips.isEmpty, sourceTape != nil else {
            return []
        }

        let window = Array(clips.prefix(warmupWindowSize))
        TapesLog.player.info("PlaybackPrep: warmup resolving \(window.count) clips sequentially (no timeout)")

        var prepared: [PreparedClip] = []

        for (index, clip) in window.enumerated() {
            // LOADING FIX: No timeout - let all assets load completely
            let resolved = await resolveClip(clip: clip, index: index, timeout: .infinity)
            prepared.append(resolved)
            if case .skipped(let reason) = resolved.status {
                onSkip(reason, index)
            }
        }

        return prepared.sorted(by: { $0.index < $1.index })
    }

    private func performContinuation(
        warmupClips: [PreparedClip],
        onProgress: @escaping (PreparedResult) -> Void,
        onCompletion: @escaping (PreparedResult) -> Void,
        onSkip: @escaping (SkipReason, Int) -> Void
    ) async throws {
        guard let tape = sourceTape else { throw CoordinatorError.noPlayableClips }

        var preparedClips = warmupClips
        var readyContexts: [TapeCompositionBuilder.ClipAssetContext] = warmupClips.compactMap {
            if case .ready(let context) = $0.status { return context }
            return nil
        }

        let startIndex = min(warmupClips.count, clips.count)
        if startIndex < clips.count {
            TapesLog.player.info("PlaybackPrep: sequential continuation starting at clip index \(startIndex)")
        }

        for index in startIndex..<clips.count {
            try Task.checkCancellation()
            let clip = clips[index]
            let prepared = await resolveClip(clip: clip, index: index, timeout: sequentialTimeout)
            preparedClips.append(prepared)

            switch prepared.status {
            case .ready(let context):
                readyContexts.append(context)
                do {
                    let result = try await buildResult(using: preparedClips, tape: tape)
                    onProgress(result)
                } catch CoordinatorError.noPlayableClips {
                    // Not ready yet; wait for next clip
                } catch {
                    TapesLog.player.error("PlaybackPrep: failed to build partial composition after clip \(index): \(error.localizedDescription)")
                }
            case .skipped(let reason):
                onSkip(reason, index)
            }
        }

        let finalResult = try await buildResult(using: preparedClips, tape: tape)
        TapesLog.player.info("PlaybackPrep: preparation complete with \(preparedClips.filter { if case .ready = $0.status { return true } else { return false } }.count) ready clips and \(preparedClips.filter { if case .skipped = $0.status { return true } else { return false } }.count) skipped clips")
        onCompletion(finalResult)
    }

    private func resolveClip(clip: Clip, index: Int, timeout: TimeInterval) async -> PreparedClip {
        // LOADING FIX: If timeout is infinity, retry indefinitely until success or unrecoverable error
        let hasTimeout = timeout.isFinite
        let deadline = hasTimeout ? Date().addingTimeInterval(timeout) : Date.distantFuture
        var attempt = 0
        let baseDelay: UInt64 = 300_000_000
        let start = Date()

        while Date() < deadline {
            attempt += 1
            do {
                if let cached = cache[index], cached.clipID == clip.id, cached.updatedAt == clip.updatedAt {
                    let elapsed = Date().timeIntervalSince(start)
                    TapesLog.player.info("PlaybackPrep: using cached context for clip \(index) (id: \(clip.id)) after \(String(format: "%.2f", elapsed))s")
                    return PreparedClip(index: index, status: .ready(cached.context), duration: clip.duration)
                }

                let context = try await builder.resolveClipContext(for: clip, index: index)
                cache[index] = CachedContext(clipID: clip.id, updatedAt: clip.updatedAt, context: context)
                let elapsed = Date().timeIntervalSince(start)
                TapesLog.player.info("PlaybackPrep: resolved clip \(index) in \(String(format: "%.2f", elapsed))s")
                return PreparedClip(index: index, status: .ready(context), duration: clip.duration)
            } catch {
                if !isRecoverable(error) {
                    TapesLog.player.error("PlaybackPrep: unrecoverable error for clip \(index): \(error.localizedDescription)")
                    return PreparedClip(index: index, status: .skipped(.error), duration: clip.duration)
                }
                let remaining = deadline.timeIntervalSinceNow
                if hasTimeout && remaining <= 0 {
                    break
                }
                let jitter = UInt64.random(in: 0..<100_000_000)
                let sleepTime = hasTimeout ? min(UInt64(remaining * 1_000_000_000), baseDelay * UInt64(attempt) + jitter) : (baseDelay * UInt64(attempt) + jitter)
                TapesLog.player.info("PlaybackPrep: retry clip \(index) attempt \(attempt) -- \(error.localizedDescription)")
                try? await Task.sleep(nanoseconds: sleepTime)
            }
        }

        if hasTimeout {
            TapesLog.player.warning("PlaybackPrep: clip \(index) timed out after \(timeout)s")
            return PreparedClip(index: index, status: .skipped(.timeout), duration: clip.duration)
        } else {
            // Should never reach here with infinite timeout, but handle gracefully
            TapesLog.player.error("PlaybackPrep: unexpected timeout for clip \(index)")
            return PreparedClip(index: index, status: .skipped(.error), duration: clip.duration)
        }
    }

    private func buildResult(using prepared: [PreparedClip], tape: Tape) async throws -> PreparedResult {
        let ordered = prepared.sorted { $0.index < $1.index }
        let contexts = ordered.compactMap { clip -> TapeCompositionBuilder.ClipAssetContext? in
            if case .ready(let context) = clip.status { return context }
            return nil
        }

        guard !contexts.isEmpty else {
            throw CoordinatorError.noPlayableClips
        }

        var subsetTape = tape
        subsetTape.clips = contexts.map { $0.clip }
        // TIMELINE FIX: buildPlayerItem is now async and @MainActor, so call directly
        let composition = try await self.builder.buildPlayerItem(for: subsetTape, contexts: contexts)
        return PreparedResult(composition: composition, preparedClips: ordered)
    }

    private func isRecoverable(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == AVFoundationErrorDomain && nsError.code == -11800 {
            return true
        }
        if nsError.domain == NSOSStatusErrorDomain && nsError.code == -17913 {
            return true
        }
        if let builderError = error as? TapeCompositionBuilder.BuilderError {
            switch builderError {
            case .assetUnavailable, .photosAssetMissing:
                return true
            default:
                return false
            }
        }
        return false
    }
}
