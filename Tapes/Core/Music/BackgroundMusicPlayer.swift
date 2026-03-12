//
//  BackgroundMusicPlayer.swift
//  Tapes
//
//  Created by AI Assistant on 26/01/2026.
//

import AVFoundation
import OSLog
import SwiftUI

private let log = Logger(subsystem: "com.tapes.app", category: "BackgroundMusic")

@MainActor
final class BackgroundMusicPlayer: ObservableObject {

    @Published private(set) var isLoading = false
    @Published private(set) var isPlaying = false
    @Published private(set) var error: String?

    private var audioPlayer: AVAudioPlayer?
    private var pendingPlay = false

    // MARK: - Prepare

    /// Generates (or loads from cache) a background track and prepares it for playback.
    /// If the video already called syncPlay() before this finishes, playback starts automatically.
    func prepare(mood: MubertAPIClient.Mood, durationSeconds: Int, volume: Float) async {
        guard mood != .none else {
            stop()
            return
        }

        isLoading = true
        error = nil
        pendingPlay = false

        log.info("Preparing background music: mood=\(mood.rawValue), duration=\(durationSeconds)s, volume=\(volume)")

        do {
            let localURL = try await MubertAPIClient.shared.generateTrack(
                mood: mood,
                durationSeconds: durationSeconds
            )

            guard !Task.isCancelled else { return }

            log.info("Track ready at \(localURL.lastPathComponent), creating AVAudioPlayer")

            let player = try AVAudioPlayer(contentsOf: localURL)
            player.numberOfLoops = -1
            player.volume = volume
            player.prepareToPlay()

            self.audioPlayer = player
            self.isLoading = false
            log.info("Background music player ready, pendingPlay=\(self.pendingPlay)")

            if pendingPlay {
                play()
            }
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription
            self.isLoading = false
            log.error("Background music failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Playback Control

    func play() {
        audioPlayer?.play()
        isPlaying = true
    }

    func pause() {
        audioPlayer?.pause()
        isPlaying = false
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        isLoading = false
        pendingPlay = false
    }

    func setVolume(_ volume: Float) {
        audioPlayer?.volume = volume
    }

    // MARK: - Sync with Video Player

    /// Call when the main video player starts playing.
    /// If the track isn't ready yet, defers playback until prepare() finishes.
    func syncPlay() {
        if let player = audioPlayer, !isLoading {
            player.play()
            isPlaying = true
        } else {
            log.info("Audio not ready yet, deferring play")
            pendingPlay = true
        }
    }

    /// Call when the main video player pauses.
    func syncPause() {
        pendingPlay = false
        pause()
    }

    /// Call when playback ends entirely.
    func syncStop() {
        stop()
    }
}
