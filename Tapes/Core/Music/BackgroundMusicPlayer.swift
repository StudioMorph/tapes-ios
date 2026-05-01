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

    /// Loads the background track for a tape. The `mood` enum is only needed
    /// for the (currently dormant) mood-based generation path. Prompt tracks
    /// and library tracks are already cached locally by the time the player
    /// opens, so they always hit the cache-first branch. Library tracks also
    /// carry a `librarySourceURL` for self-healing re-download.
    func prepare(tapeID: UUID, volume: Float, librarySourceURL: URL? = nil, api: TapesAPIClient?) async {
        isLoading = true
        error = nil
        pendingPlay = false

        log.info("Preparing background music: tape=\(tapeID.uuidString.prefix(8)), volume=\(volume)")

        do {
            let localURL: URL

            if let cached = await MubertAPIClient.shared.cachedTrackURL(for: tapeID) {
                log.info("Track already cached")
                localURL = cached
            } else if let libraryURL = librarySourceURL {
                log.info("Cache miss, retrying library download from source URL")
                localURL = try await MubertAPIClient.shared.downloadLibraryTrack(from: libraryURL, tapeID: tapeID)
            } else {
                log.info("No cached track — nothing to prepare")
                isLoading = false
                return
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
