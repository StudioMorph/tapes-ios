import SwiftUI
import AVFoundation
import AVKit
import Combine

extension Notification.Name {
    static let autoHideControls = Notification.Name("autoHideControls")
}


// MARK: - Unified Tape Player View

struct TapePlayerView: View {
    @StateObject private var engine = SimplePlaybackEngine()
    @State private var showingControls: Bool = true
    @State private var controlsTimer: Timer?
    @State private var hasAppeared = false
    @State private var appearanceTime: Date?

    let tape: Tape
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Video player (if exists)
            if let player = engine.player {
                    VideoPlayer(player: player)
                        .disabled(true)
                        .overlay(tapCatcher)
                        .onDisappear { player.pause() }
            } else {
                // No player yet - show tap catcher for controls
                tapCatcher
            }
            
            // Loading overlay - show whenever actually loading/preparing (no fake delays)
            // Always render overlay (but conditionally visible) to ensure SwiftUI tracks state
            PlayerLoadingOverlay(
                isLoading: engine.isPreparing || engine.isBuffering,
                loadError: engine.error
            )
            .zIndex(100)
            .opacity((engine.isPreparing || engine.isBuffering) ? 1 : 0)
            .allowsHitTesting(engine.isPreparing || engine.isBuffering)

            // Controls (show/hide based on state)
            if showingControls || engine.error != nil || engine.isFinished {
                VStack {
                    PlayerHeader(
                        currentClipIndex: engine.currentClipIndex,
                        totalClips: tape.clips.count,
                        onDismiss: onDismiss
                    )
                    Spacer()
                    if engine.error == nil {
                        controlsView
                    }
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: showingControls)
            }
        }
        .onAppear {
            hasAppeared = true
            appearanceTime = Date()
            Task { await preparePlayer() }
            setupControlsTimer()
        }
        .onReceive(NotificationCenter.default.publisher(for: .autoHideControls)) { _ in
            // Hide controls when timer fires (if conditions are met)
            if engine.isPlaying && engine.error == nil && !engine.isPreparing && !engine.isBuffering {
                withAnimation {
                    showingControls = false
                }
            }
        }
        .onDisappear {
            TapesLog.player.info("TapePlayerView: onDisappear called (appearanceTime: \(appearanceTime != nil ? "set" : "nil"), buffering: \(engine.isBuffering))")
            
            // Prevent premature teardown during SwiftUI lifecycle transitions
            // Don't tear down if we just appeared or are actively buffering or preparing
            if engine.isBuffering || engine.isPreparing {
                TapesLog.player.warning("TapePlayerView: Ignoring onDisappear - engine is still buffering (\(engine.isBuffering)) or preparing (\(engine.isPreparing))")
                return
            }
            
            // Check if engine is still preparing (hasn't started playing yet)
            // Use a longer timeout - preparation can take 15+ seconds
            if engine.player == nil && engine.error == nil {
                if let appearanceTime = appearanceTime {
                    let timeSinceAppearance = Date().timeIntervalSince(appearanceTime)
                    // Allow up to 30 seconds for preparation before allowing teardown (Photos can be slow)
                    if timeSinceAppearance < 30.0 {
                        TapesLog.player.warning("TapePlayerView: Ignoring onDisappear - engine is still preparing (only \(String(format: "%.1f", timeSinceAppearance))s since appearance)")
                        return
                    }
                } else {
                    // No appearance time but no player - still preparing
                    TapesLog.player.warning("TapePlayerView: Ignoring onDisappear - engine is still preparing (no player yet, no appearanceTime)")
                    return
                }
            }
            
            if let appearanceTime = appearanceTime {
                let timeSinceAppearance = Date().timeIntervalSince(appearanceTime)
                if timeSinceAppearance < 3.0 {
                    TapesLog.player.warning("TapePlayerView: Ignoring premature onDisappear (only \(String(format: "%.2f", timeSinceAppearance))s since appearance)")
                    return
                }
            } else if hasAppeared {
                // Has appeared but no time recorded - still ignore for safety
                TapesLog.player.warning("TapePlayerView: Ignoring onDisappear - hasAppeared=true but no appearanceTime")
                return
            }
            
            TapesLog.player.info("TapePlayerView: Proceeding with teardown")
            tearDown()
            hasAppeared = false
            appearanceTime = nil
        }
    }

    private var tapCatcher: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                toggleControls()
            }
    }

    // MARK: - Controls View

    private var controlsView: some View {
        VStack(spacing: 32) {
            // Progress bar (thumbnail scrubber TODO: integrate when thumbnails are generated)
            PlayerProgressBar(
                currentTime: engine.currentTime,
                totalDuration: engine.duration,
                onSeek: { time in
                    engine.seek(to: time)
                }
            )
            
            // Advanced controls
            AdvancedPlayerControls(
                    isPlaying: engine.isPlaying,
                    playbackSpeed: engine.playbackSpeed,
                    canGoBack: engine.currentClipIndex > 0,
                    canGoForward: engine.currentClipIndex < tape.clips.count - 1,
                    onPlayPause: {
                        if engine.isPlaying {
                            engine.pause()
                        } else {
                            engine.play()
                        }
                    },
                    onPrevious: {
                        let prevIndex = engine.currentClipIndex - 1
                        guard prevIndex >= 0 else { return }
                        engine.seekToClip(at: prevIndex)
                    },
                    onNext: {
                        let nextIndex = engine.currentClipIndex + 1
                        guard nextIndex < tape.clips.count else { return }
                        engine.seekToClip(at: nextIndex)
                    },
                    onSpeedChange: { speed in
                        engine.setPlaybackSpeed(speed)
                    },
                    onFrameStep: { _ in
                        // Frame step not implemented in SimplePlaybackEngine
                    }
                )
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
    }

    // MARK: - Player Preparation
    
    @MainActor
    private func preparePlayer() async {
        // Set loading state immediately before async preparation starts
        // This ensures UI shows loading overlay right away
        engine.setError(nil) // Clear any previous errors
        // isPreparing and isBuffering are set inside prepare(), but we want immediate UI feedback
        // The prepare() function will set these, but let's ensure they're observed
        await engine.prepare(tape: tape)
    }
    
    private func toggleControls() {
        if showingControls {
            // Hide controls
            withAnimation { showingControls = false }
            controlsTimer?.invalidate()
            controlsTimer = nil
        } else {
            // Show controls
            withAnimation { showingControls = true }
            // Auto-hide after 3 seconds if playing
            setupControlsTimer()
        }
    }
    
    private func setupControlsTimer() {
        controlsTimer?.invalidate()
        // Timer will auto-hide controls after 3 seconds
        // Capture engine reference (it's a @StateObject, so it's a reference type)
        let engineRef = engine
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            Task { @MainActor in
                // Check conditions on main thread
                if engineRef.isPlaying && engineRef.error == nil && !engineRef.isPreparing && !engineRef.isBuffering {
                    // Post notification to trigger state update
                    NotificationCenter.default.post(name: .autoHideControls, object: nil)
                }
            }
        }
    }
    
    private func tearDown() {
        engine.teardown()
        controlsTimer?.invalidate()
        controlsTimer = nil
    }
}
