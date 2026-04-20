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

    private let baseURL = "https://music-api.mubert.com/api/v3/public/tracks"
    private let customerID = "a148eef0-a5b0-476a-841f-8cec671079bf"
    private let accessToken = "rSM2ABBePwoeu4AC7Z4OePkj2rXggDpDI2YuRmT2Y7HPdwtuLqxWHwzM9sPN0NF1"

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

    // MARK: - Response

    struct TrackResponse: Decodable {
        let data: TrackData?
    }

    struct TrackData: Decodable {
        let id: String
        let generations: [Generation]?
    }

    struct Generation: Decodable {
        let status: String
        let url: String?
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

    /// Generates a background music track for the given mood and tape.
    /// Reports progress via the callback (0.0–1.0). Tracks are cached per-tape.
    func generateTrack(
        mood: Mood,
        tapeID: UUID,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws -> URL {
        guard mood != .none else { throw APIError.noMoodSelected }

        if let cached = cachedTrackURL(for: tapeID) {
            log.info("Using cached track for tape=\(tapeID.uuidString.prefix(8))")
            onProgress(1.0)
            return cached
        }

        let trackDuration = Self.loopTrackDuration

        let body: [String: Any] = [
            "playlist_index": mood.playlistIndex,
            "duration": trackDuration,
            "bitrate": 128,
            "format": "mp3",
            "intensity": "medium",
            "mode": "track"
        ]

        onProgress(0.05)
        log.info("Requesting track: mood=\(mood.rawValue) playlist=\(mood.playlistIndex) tape=\(tapeID.uuidString.prefix(8))")

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(customerID, forHTTPHeaderField: "customer-id")
        request.setValue(accessToken, forHTTPHeaderField: "access-token")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        log.info("API response status: \(httpResponse.statusCode)")
        onProgress(0.1)

        if httpResponse.statusCode == 401 {
            let responseBody = String(data: data, encoding: .utf8) ?? "(empty)"
            log.error("Mubert 401 — credentials rejected. Body: \(responseBody, privacy: .public)")
            throw APIError.notConfigured
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            log.error("API error \(httpResponse.statusCode): \(message)")
            throw APIError.serverError(message)
        }

        let trackResponse = try JSONDecoder().decode(TrackResponse.self, from: data)
        guard let trackID = trackResponse.data?.id else {
            throw APIError.invalidResponse
        }

        if let gen = trackResponse.data?.generations?.first,
           gen.status == "done", let urlStr = gen.url, let url = URL(string: urlStr) {
            log.info("Track immediately ready: \(urlStr)")
            onProgress(0.9)
            let local = try await downloadTrack(from: url, tapeID: tapeID)
            onProgress(1.0)
            return local
        }

        log.info("Track processing, polling id=\(trackID)")
        return try await pollForTrack(id: trackID, tapeID: tapeID, onProgress: onProgress)
    }

    // MARK: - Polling

    private func pollForTrack(
        id: String,
        tapeID: UUID,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws -> URL {
        let pollURL = URL(string: "\(baseURL)/\(id)")!

        for attempt in 0..<Self.maxPollAttempts {
            try await Task.sleep(nanoseconds: Self.pollInterval)

            let fraction = 0.1 + 0.8 * (Double(attempt + 1) / Double(Self.maxPollAttempts))
            onProgress(fraction)

            var request = URLRequest(url: pollURL)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(customerID, forHTTPHeaderField: "customer-id")
            request.setValue(accessToken, forHTTPHeaderField: "access-token")

            let (data, _) = try await URLSession.shared.data(for: request)
            let trackResponse = try JSONDecoder().decode(TrackResponse.self, from: data)

            if let gen = trackResponse.data?.generations?.first {
                log.info("Poll \(attempt + 1)/\(Self.maxPollAttempts): status=\(gen.status)")
                if gen.status == "done", let urlStr = gen.url, let url = URL(string: urlStr) {
                    log.info("Track ready: \(urlStr)")
                    onProgress(0.95)
                    let local = try await downloadTrack(from: url, tapeID: tapeID)
                    onProgress(1.0)
                    return local
                }
            }
        }

        log.error("Track generation timed out after \(Self.maxPollAttempts) attempts")
        throw APIError.serverError("Track generation timed out.")
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
