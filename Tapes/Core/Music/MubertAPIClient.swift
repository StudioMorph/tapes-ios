//
//  MubertAPIClient.swift
//  Tapes
//
//  Created by AI Assistant on 26/01/2026.
//

import Foundation
import OSLog

private let log = TapesLog.music

actor MubertAPIClient {

    static let shared = MubertAPIClient()

    // Mubert credentials live on the backend only. All requests go through
    // the /music/* proxy routes on the Tapes API.

    // MARK: - Moods

    enum Mood: String, CaseIterable, Codable, Identifiable {
        case none       = "none"
        case chill      = "chill"
        case cinematic  = "cinematic"
        case dramatic   = "dramatic"
        case dreamy     = "dreamy"
        case energetic  = "energizing"
        case epic       = "epic"
        case happy      = "happy"
        case inspiring  = "inspirational"
        case melancholic = "melancholic"
        case peaceful   = "peaceful"
        case romantic   = "romantic"
        case sad        = "sad"
        case scary      = "scary"
        case upbeat     = "upbeat"
        case uplifting  = "uplifting"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .none:        return "None"
            case .chill:       return "Chill"
            case .cinematic:   return "Cinematic"
            case .dramatic:    return "Dramatic"
            case .dreamy:      return "Dreamy"
            case .energetic:   return "Energetic"
            case .epic:        return "Epic"
            case .happy:       return "Happy"
            case .inspiring:   return "Inspiring"
            case .melancholic: return "Melancholic"
            case .peaceful:    return "Peaceful"
            case .romantic:    return "Romantic"
            case .sad:         return "Sad"
            case .scary:       return "Scary"
            case .upbeat:      return "Upbeat"
            case .uplifting:   return "Uplifting"
            }
        }

        var icon: String {
            switch self {
            case .none:        return "speaker.slash"
            case .chill:       return "leaf"
            case .cinematic:   return "film"
            case .dramatic:    return "theatermasks"
            case .dreamy:      return "cloud"
            case .energetic:   return "bolt"
            case .epic:        return "mountain.2"
            case .happy:       return "sun.max"
            case .inspiring:   return "sparkles"
            case .melancholic: return "drop"
            case .peaceful:    return "water.waves"
            case .romantic:    return "heart"
            case .sad:         return "cloud.rain"
            case .scary:       return "eye"
            case .upbeat:      return "music.note"
            case .uplifting:   return "arrow.up.heart"
            }
        }

        var playlistIndex: String {
            switch self {
            case .none:        return ""
            case .chill:       return "4.0.0"   // Chill / Chillout
            case .cinematic:   return "0.8.1"   // Moods / Heroic / Cinematic
            case .dramatic:    return "0.4.1"   // Moods / Tense / Dramatic
            case .dreamy:      return "0.7.0"   // Moods / Dreamy
            case .energetic:   return "0.1.4"   // Moods / Energizing
            case .epic:        return "0.8.1"   // Moods / Heroic / Cinematic
            case .happy:       return "0.2.2"   // Moods / Joyful
            case .inspiring:   return "0.5.0"   // Moods / Beautiful
            case .melancholic: return "0.3.0"   // Moods / Sad
            case .peaceful:    return "3.0.0"   // Calm / Ambient / Meditation
            case .romantic:    return "0.6.1"   // Moods / Erotic
            case .sad:         return "0.3.0"   // Moods / Sad
            case .scary:       return "0.10.0"  // Moods / Scary / Spooky
            case .upbeat:      return "5.0.2"   // Sport / Fitness / Energy
            case .uplifting:   return "0.5.0"   // Moods / Beautiful
            }
        }
    }

    // MARK: - Errors

    enum APIError: LocalizedError {
        case noMoodSelected
        case invalidResponse
        case serverError(String)
        case networkError(Error)
        case notConfigured

        var errorDescription: String? {
            switch self {
            case .noMoodSelected:    return "No mood selected."
            case .invalidResponse:   return "Invalid response from music service."
            case .serverError(let m): return "Music service error: \(m)"
            case .networkError(let e): return "Network error: \(e.localizedDescription)"
            case .notConfigured:     return "Music service is not yet configured."
            }
        }
    }

    // MARK: - Generate Track

    private static let maxPollAttempts = 30
    private static let pollInterval: UInt64 = 2_000_000_000 // 2 seconds

    static let loopTrackDuration = 30

    /// Generates a background music track for the given mood and tape via the
    /// Tapes API proxy. Mubert credentials never touch the device. Reports
    /// progress via the callback (0.0–1.0). Tracks are cached per-tape.
    func generateTrack(
        mood: Mood,
        tapeID: UUID,
        api: TapesAPIClient,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws -> URL {
        guard mood != .none else { throw APIError.noMoodSelected }

        if let cached = cachedTrackURL(for: tapeID) {
            log.info("Using cached track for tape=\(tapeID.uuidString.prefix(8))")
            onProgress(1.0)
            return cached
        }

        onProgress(0.05)
        log.info("Requesting track: mood=\(mood.rawValue) playlist=\(mood.playlistIndex) tape=\(tapeID.uuidString.prefix(8))")

        let response: TapesAPIClient.MusicGenerateResponse
        do {
            response = try await api.generateMusicTrack(
                moodPlaylist: mood.playlistIndex,
                duration: Self.loopTrackDuration
            )
        } catch {
            log.error("Music proxy generate failed: \(error.localizedDescription, privacy: .public)")
            throw APIError.serverError(error.localizedDescription)
        }

        onProgress(0.1)

        if response.status == "done", let urlStr = response.url, let url = URL(string: urlStr) {
            log.info("Track immediately ready")
            onProgress(0.9)
            let local = try await downloadTrack(from: url, tapeID: tapeID)
            onProgress(1.0)
            return local
        }

        log.info("Track processing, polling id=\(response.trackId)")
        return try await pollForTrack(id: response.trackId, tapeID: tapeID, api: api, onProgress: onProgress)
    }

    // MARK: - Polling

    private func pollForTrack(
        id: String,
        tapeID: UUID,
        api: TapesAPIClient,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws -> URL {
        for attempt in 0..<Self.maxPollAttempts {
            try await Task.sleep(nanoseconds: Self.pollInterval)

            let fraction = 0.1 + 0.8 * (Double(attempt + 1) / Double(Self.maxPollAttempts))
            onProgress(fraction)

            let response: TapesAPIClient.MusicGenerateResponse
            do {
                response = try await api.pollMusicTrack(trackId: id)
            } catch {
                log.error("Music proxy poll failed: \(error.localizedDescription, privacy: .public)")
                throw APIError.serverError(error.localizedDescription)
            }

            log.info("Poll \(attempt + 1)/\(Self.maxPollAttempts): status=\(response.status, privacy: .public)")
            if response.status == "done", let urlStr = response.url, let url = URL(string: urlStr) {
                log.info("Track ready")
                onProgress(0.95)
                let local = try await downloadTrack(from: url, tapeID: tapeID)
                onProgress(1.0)
                return local
            }
        }

        log.error("Track generation timed out after \(Self.maxPollAttempts) attempts")
        throw APIError.serverError("Track generation timed out.")
    }

    // MARK: - Generate from Prompt (Text-to-Music)

    /// Generates a prompt-based track to a scratch (tmp) location.
    /// The tape's per-tape cache is left untouched until the caller commits.
    func generateFromPromptScratch(
        prompt: String,
        duration: Int = 30,
        intensity: String = "medium",
        api: TapesAPIClient,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws -> URL {
        onProgress(0.05)
        log.info("Requesting scratch prompt track: \"\(prompt.prefix(40))\"")

        let response: TapesAPIClient.MusicGenerateResponse
        do {
            response = try await api.generateMusicFromPrompt(
                prompt: prompt,
                duration: duration,
                intensity: intensity
            )
        } catch {
            log.error("Music proxy prompt generate failed: \(error.localizedDescription, privacy: .public)")
            throw APIError.serverError(error.localizedDescription)
        }

        onProgress(0.1)

        if response.status == "done", let urlStr = response.url, let url = URL(string: urlStr) {
            log.info("Prompt track immediately ready (scratch)")
            onProgress(0.9)
            let local = try await downloadToScratch(from: url)
            onProgress(1.0)
            return local
        }

        log.info("Prompt track processing, polling id=\(response.trackId)")
        return try await pollForScratchTrack(id: response.trackId, api: api, onProgress: onProgress)
    }

    private func pollForScratchTrack(
        id: String,
        api: TapesAPIClient,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws -> URL {
        for attempt in 0..<Self.maxPollAttempts {
            try await Task.sleep(nanoseconds: Self.pollInterval)

            let fraction = 0.1 + 0.8 * (Double(attempt + 1) / Double(Self.maxPollAttempts))
            onProgress(fraction)

            let response: TapesAPIClient.MusicGenerateResponse
            do {
                response = try await api.pollMusicTrack(trackId: id)
            } catch {
                log.error("Music proxy poll failed: \(error.localizedDescription, privacy: .public)")
                throw APIError.serverError(error.localizedDescription)
            }

            log.info("Scratch poll \(attempt + 1)/\(Self.maxPollAttempts): status=\(response.status, privacy: .public)")
            if response.status == "done", let urlStr = response.url, let url = URL(string: urlStr) {
                log.info("Scratch track ready")
                onProgress(0.95)
                let local = try await downloadToScratch(from: url)
                onProgress(1.0)
                return local
            }
        }

        log.error("Scratch track generation timed out after \(Self.maxPollAttempts) attempts")
        throw APIError.serverError("Track generation timed out.")
    }

    // MARK: - Scratch cache helpers

    private func scratchDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mubert_scratch", isDirectory: true)
    }

    private func downloadToScratch(from remoteURL: URL) async throws -> URL {
        let (tempURL, _) = try await URLSession.shared.download(from: remoteURL)
        let dir = scratchDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let localURL = dir.appendingPathComponent("\(UUID().uuidString).mp3")
        try FileManager.default.moveItem(at: tempURL, to: localURL)
        log.info("Downloaded scratch track: \(localURL.lastPathComponent)")
        return localURL
    }

    /// Promotes a scratch file into the tape's per-tape cache slot,
    /// replacing any existing cached track for that tape.
    func commitScratch(at scratchURL: URL, to tapeID: UUID) throws -> URL {
        let cacheDir = trackCacheDir()
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let dest = cacheDir.appendingPathComponent("\(tapeID.uuidString).mp3")

        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: scratchURL, to: dest)
        log.info("Committed scratch → cache for tape=\(tapeID.uuidString.prefix(8))")
        return dest
    }

    func discardScratch(at scratchURL: URL) {
        try? FileManager.default.removeItem(at: scratchURL)
        log.info("Discarded scratch: \(scratchURL.lastPathComponent)")
    }

    // MARK: - Download Library Track

    func downloadLibraryTrack(
        from remoteURL: URL,
        tapeID: UUID
    ) async throws -> URL {
        clearCache(for: tapeID)
        return try await downloadTrack(from: remoteURL, tapeID: tapeID)
    }

    // MARK: - Cache (per-tape)

    private func trackCacheDir() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("mubert_tracks", isDirectory: true)
    }

    func cachedTrackURL(for tapeID: UUID) -> URL? {
        let file = trackCacheDir().appendingPathComponent("\(tapeID.uuidString).mp3")
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    func clearCache(for tapeID: UUID) {
        let file = trackCacheDir().appendingPathComponent("\(tapeID.uuidString).mp3")
        try? FileManager.default.removeItem(at: file)
        log.info("Cleared cache for tape=\(tapeID.uuidString.prefix(8))")
    }

    // MARK: - Download

    private func downloadTrack(from remoteURL: URL, tapeID: UUID) async throws -> URL {
        let (tempURL, _) = try await URLSession.shared.download(from: remoteURL)
        let cacheDir = trackCacheDir()
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let localURL = cacheDir.appendingPathComponent("\(tapeID.uuidString).mp3")

        if FileManager.default.fileExists(atPath: localURL.path) {
            try FileManager.default.removeItem(at: localURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: localURL)
        log.info("Downloaded and cached track: \(localURL.lastPathComponent)")
        return localURL
    }

}
