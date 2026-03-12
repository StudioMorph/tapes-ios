//
//  MubertAPIClient.swift
//  Tapes
//
//  Created by AI Assistant on 26/01/2026.
//

import Foundation
import OSLog

private let log = Logger(subsystem: "com.tapes.app", category: "MubertAPI")

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

    private static let loopTrackDuration = 30

    /// Generates a background music track for the given mood.
    /// Returns a local file URL. Tracks are cached by mood for instant replay.
    func generateTrack(mood: Mood, durationSeconds: Int) async throws -> URL {
        guard mood != .none else { throw APIError.noMoodSelected }

        if let cached = cachedTrackURL(for: mood) {
            log.info("Using cached track for mood=\(mood.rawValue)")
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

        log.info("Requesting track: mood=\(mood.rawValue) playlist=\(mood.playlistIndex) duration=\(trackDuration)s (loops)")

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

        if httpResponse.statusCode == 401 {
            let responseBody = String(data: data, encoding: .utf8) ?? "(empty)"
            log.warning("API returned 401 — falling back to mock. Body: \(responseBody)")
            return try await downloadMockTrack(mood: mood, duration: durationSeconds)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            log.error("API error \(httpResponse.statusCode): \(message)")
            throw APIError.serverError(message)
        }

        if let responseStr = String(data: data, encoding: .utf8) {
            log.debug("API response body: \(responseStr)")
        }

        let trackResponse = try JSONDecoder().decode(TrackResponse.self, from: data)
        guard let trackID = trackResponse.data?.id else {
            throw APIError.invalidResponse
        }

        if let gen = trackResponse.data?.generations?.first,
           gen.status == "done", let urlStr = gen.url, let url = URL(string: urlStr) {
            log.info("Track immediately ready: \(urlStr)")
            return try await downloadTrack(from: url, mood: mood)
        }

        log.info("Track processing, polling id=\(trackID)")
        return try await pollForTrack(id: trackID, mood: mood)
    }

    // MARK: - Polling

    private func pollForTrack(id: String, mood: Mood) async throws -> URL {
        let pollURL = URL(string: "\(baseURL)/\(id)")!

        for attempt in 0..<Self.maxPollAttempts {
            try await Task.sleep(nanoseconds: Self.pollInterval)

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
                    return try await downloadTrack(from: url, mood: mood)
                }
            }
        }

        log.error("Track generation timed out after \(Self.maxPollAttempts) attempts")
        throw APIError.serverError("Track generation timed out.")
    }

    // MARK: - Cache

    private func trackCacheDir() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("mubert_tracks", isDirectory: true)
    }

    private func cachedTrackURL(for mood: Mood) -> URL? {
        let file = trackCacheDir().appendingPathComponent("\(mood.rawValue).mp3")
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    // MARK: - Download

    private func downloadTrack(from remoteURL: URL, mood: Mood) async throws -> URL {
        let (tempURL, _) = try await URLSession.shared.download(from: remoteURL)
        let cacheDir = trackCacheDir()
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let localURL = cacheDir.appendingPathComponent("\(mood.rawValue).mp3")

        if FileManager.default.fileExists(atPath: localURL.path) {
            try FileManager.default.removeItem(at: localURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: localURL)
        log.info("Downloaded and cached track: \(localURL.lastPathComponent)")
        return localURL
    }

    // MARK: - Mock Fallback

    /// Returns a simple tone audio file for development when the API isn't available.
    private func downloadMockTrack(mood: Mood, duration: Int) async throws -> URL {
        log.warning("Using mock audio track (API unavailable)")
        let cacheDir = trackCacheDir()
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let localURL = cacheDir.appendingPathComponent("mock_\(mood.rawValue).wav")

        if !FileManager.default.fileExists(atPath: localURL.path) {
            let toneWav = generateToneWav(durationSeconds: Self.loopTrackDuration, frequency: 220)
            try toneWav.write(to: localURL)
        }
        return localURL
    }

    /// Generates a quiet sine-wave tone WAV so the mock fallback is audible during development.
    private func generateToneWav(durationSeconds: Int, frequency: Double) -> Data {
        let sampleRate: UInt32 = 44100
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let numSamples = UInt32(durationSeconds) * sampleRate
        let dataSize = numSamples * UInt32(channels) * UInt32(bitsPerSample / 8)
        let fileSize = 36 + dataSize

        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: channels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        let blockAlign = channels * (bitsPerSample / 8)
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        let amplitude: Double = 3000
        for i in 0..<Int(numSamples) {
            let sample = Int16(amplitude * sin(2.0 * .pi * frequency * Double(i) / Double(sampleRate)))
            withUnsafeBytes(of: sample.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }
}
