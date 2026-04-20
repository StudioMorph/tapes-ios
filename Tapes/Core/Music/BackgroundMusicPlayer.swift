//
//  BackgroundMusicPlayer.swift
//  Tapes
//
//  Created by AI Assistant on 26/01/2026.
//

import AVFoundation
import OSLog
import SwiftUI

private let log = TapesLog.music

@MainActor
final class BackgroundMusicPlayer: ObservableObject {

    @Published private(set) var isLoading = false
    @Published private(set) var isPlaying = false
    @Published private(set) var error: String?

    private var audioPlayer: AVAudioPlayer?
    private var pendingPlay = false

    // MARK: - Prepare

    /// Loads (or waits for) a background track for the given mood and tape.
    /// If the track is already cached, loads instantly. If still generating, waits with polling.
    /// If the video already called syncPlay() before this finishes, playback starts automatically.
    func prepare(mood: MubertAPIClient.Mood, tapeID: UUID, volume: Float) async {
        guard mood != .none else {
            stop()
            return
        }

        isLoading = true
        error = nil
        pendingPlay = false

        log.info("Preparing background music: mood=\(mood.rawValue), tape=\(tapeID.uuidString.prefix(8)), volume=\(volume)")

        do {
            let localURL: URL

            if let cached = await MubertAPIClient.shared.cachedTrackURL(for: tapeID) {
                log.info("Track already cached")
                localURL = cached
            } else {
                log.info("Track not cached, generating...")
                localURL = try await MubertAPIClient.shared.generateTrack(
                    mood: mood,
                    tapeID: tapeID,
                    onProgress: { _ in }
                )
            }

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
