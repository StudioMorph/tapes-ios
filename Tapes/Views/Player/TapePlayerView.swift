import SwiftUI
import AVFoundation
import AVKit

// MARK: - Unified Tape Player View

struct TapePlayerView: View {
    @State private var player: AVPlayer?
    @State private var currentClipIndex: Int = 0
    @State private var isPlaying: Bool = false
    @State private var showingControls: Bool = true
    @State private var controlsTimer: Timer?
    @State private var totalDuration: Double = 0
    @State private var currentTime: Double = 0
    @State private var isFinished: Bool = false
    @State private var progressTimer: Timer?
    
    let tape: Tape
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Video Player
                videoPlayerView
                
                // Controls
                if showingControls {
                    controlsView
                }
            }
        }
        .onAppear {
            setupPlayer()
            setupControlsTimer()
        }
                .onDisappear {
                    // Stop all audio and clean up
                    player?.pause()
                    player?.replaceCurrentItem(with: nil)
                    player = nil
                    controlsTimer?.invalidate()
                    progressTimer?.invalidate()
                    // Clean up notification observers
                    NotificationCenter.default.removeObserver(self)
                }
        .onTapGesture {
            toggleControls()
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            Text("\(currentClipIndex + 1) of \(tape.clips.count)")
                .font(.headline)
                .foregroundColor(.white)
        }
        .padding()
    }
    
    // MARK: - Video Player View
    
    private var videoPlayerView: some View {
        GeometryReader { geometry in
            if let player = player {
                VideoPlayer(player: player)
                    .disabled(true) // Disable all built-in controls
                    .onAppear {
                        print("🎬 Playing clip \(currentClipIndex + 1) of \(tape.clips.count)")
                    }
                    .onDisappear {
                        player.pause()
                    }
            } else {
                // Loading state
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    
                    Text("Loading...")
                        .foregroundColor(.white)
                        .padding(.top)
                }
            }
        }
    }
    
    // MARK: - Controls View
    
    private var controlsView: some View {
        VStack(spacing: 20) {
            if isFinished {
                // Finished state - show play again button
                finishedView
            } else {
                // Global progress bar
                globalProgressView
                
                // Global control buttons
                globalControlButtons
            }
        }
        .padding()
    }
    
    // MARK: - Finished View
    
    private var finishedView: some View {
        VStack(spacing: 20) {
            Text("Playback Complete")
                .font(.title2)
                .foregroundColor(.white)
            
            Button(action: playAgain) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Play Again")
                }
                .font(.title2)
                .foregroundColor(.black)
                .padding()
                .background(Color.white)
                .cornerRadius(10)
            }
        }
    }
    
    // MARK: - Global Progress View
    
    private var globalProgressView: some View {
        VStack(spacing: 8) {
            // Interactive progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 6)
                    
                    // Progress track
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: geometry.size.width * (currentTime / totalDuration), height: 6)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let progress = max(0, min(1, value.location.x / geometry.size.width))
                            let targetTime = progress * totalDuration
                            currentTime = targetTime
                        }
                        .onEnded { value in
                            let progress = max(0, min(1, value.location.x / geometry.size.width))
                            let targetTime = progress * totalDuration
                            scrubToPosition(value.location.x, in: geometry.size.width)
                        }
                )
            }
            .frame(height: 6)
            
            // Time labels
            HStack {
                Text(formatTime(currentTime))
                    .foregroundColor(.white)
                    .font(.caption)
                
                Spacer()
                
                Text(formatTime(totalDuration))
                    .foregroundColor(.white)
                    .font(.caption)
            }
        }
    }
    
    // MARK: - Global Control Buttons
    
    private var globalControlButtons: some View {
        HStack(spacing: 40) {
            // Previous button
            Button(action: previousClip) {
                Image(systemName: "backward.fill")
                    .font(.title)
                    .foregroundColor(.white)
            }
            .disabled(currentClipIndex == 0)
            
            // Play/Pause button
            Button(action: togglePlayPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.largeTitle)
                    .foregroundColor(.white)
            }
            
            // Next button
            Button(action: nextClip) {
                Image(systemName: "forward.fill")
                    .font(.title)
                    .foregroundColor(.white)
            }
            .disabled(currentClipIndex >= tape.clips.count - 1)
        }
    }
    
    // MARK: - Progress View
    
    private var progressView: some View {
        HStack {
            Text("\(currentClipIndex + 1) of \(tape.clips.count)")
                .foregroundColor(.white)
            
            Spacer()
            
            if let clip = currentClip {
                Text(formatTime(clip.duration))
                    .foregroundColor(.white)
            }
        }
        .font(.caption)
    }
    
    // MARK: - Current Clip
    
    private var currentClip: Clip? {
        guard currentClipIndex < tape.clips.count else { return nil }
        return tape.clips[currentClipIndex]
    }
    
    // MARK: - Setup
    
    private func setupPlayer() {
        guard !tape.clips.isEmpty else { return }
        calculateTotalDuration()
        loadCurrentClip()
        startProgressTracking()
    }
    
    private func calculateTotalDuration() {
        totalDuration = tape.clips.reduce(0) { total, clip in
            total + clip.duration
        }
        print("🎬 Total duration: \(formatTime(totalDuration))")
    }
    
    private func loadCurrentClip() {
        guard let clip = currentClip,
              let url = clip.localURL else {
            print("❌ No clip or URL available")
            return
        }
        
        print("🎬 Loading clip \(currentClipIndex + 1): \(clip.id)")
        
        // Create new player item first
        let playerItem = AVPlayerItem(url: url)
        
        // Add observer for when video ends
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            self.onVideoEnded()
        }
        
        // Replace current item with new one (smooth transition)
        player?.replaceCurrentItem(with: playerItem)
        
        // Auto-play when loaded
        player?.play()
        isPlaying = true
    }
    
    private func onVideoEnded() {
        print("🎬 Video ended, advancing to next clip")
        
        // Auto-advance to next clip if available
        if currentClipIndex < tape.clips.count - 1 {
            nextClip()
        } else {
            // Reached the end - show finished state
            player?.pause()
            isPlaying = false
            isFinished = true
            print("🎬 Reached end of tape")
        }
    }
    
    private func playAgain() {
        currentClipIndex = 0
        currentTime = 0
        isFinished = false
        loadCurrentClip()
    }
    
    // MARK: - Controls
    
    private func togglePlayPause() {
        if isPlaying {
            player?.pause()
            isPlaying = false
        } else {
            player?.play()
            isPlaying = true
        }
    }
    
    private func nextClip() {
        guard currentClipIndex < tape.clips.count - 1 else { return }
        currentClipIndex += 1
        loadCurrentClip()
    }
    
    private func previousClip() {
        guard currentClipIndex > 0 else { return }
        currentClipIndex -= 1
        loadCurrentClip()
    }
    
    private func toggleControls() {
        withAnimation {
            showingControls.toggle()
        }
        
        if showingControls {
            setupControlsTimer()
        } else {
            controlsTimer?.invalidate()
        }
    }
    
    private func setupControlsTimer() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation {
                showingControls = false
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - Progress Tracking
    
    private func startProgressTracking() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            updateCurrentTime()
        }
    }
    
    private func updateCurrentTime() {
        guard let player = player,
              let currentItem = player.currentItem else { return }
        
        let currentTimeInSeconds = CMTimeGetSeconds(currentItem.currentTime())
        let totalElapsedTime = calculateElapsedTimeForCurrentClip() + currentTimeInSeconds
        
        currentTime = totalElapsedTime
        
        // Check if we've reached the end
        if totalElapsedTime >= totalDuration {
            currentTime = totalDuration
            if !isFinished {
                isFinished = true
                player.pause()
                isPlaying = false
            }
        }
    }
    
    private func calculateElapsedTimeForCurrentClip() -> Double {
        var elapsedTime: Double = 0
        for i in 0..<currentClipIndex {
            if i < tape.clips.count {
                elapsedTime += tape.clips[i].duration
            }
        }
        return elapsedTime
    }
    
    private func scrubToPosition(_ x: CGFloat, in width: CGFloat) {
        let progress = max(0, min(1, x / width))
        let targetTime = progress * totalDuration
        
        print("🎯 Scrubbing to: \(formatTime(targetTime)) (progress: \(progress))")
        
        // Find which clip this time corresponds to
        var accumulatedTime: Double = 0
        var targetClipIndex = 0
        
        for (index, clip) in tape.clips.enumerated() {
            if targetTime <= accumulatedTime + clip.duration {
                targetClipIndex = index
                break
            }
            accumulatedTime += clip.duration
        }
        
        print("🎯 Target clip index: \(targetClipIndex), current: \(currentClipIndex)")
        
        // If we need to change clips
        if targetClipIndex != currentClipIndex {
            print("🎯 Changing to clip \(targetClipIndex + 1)")
            currentClipIndex = targetClipIndex
            loadCurrentClip()
        }
        
        // Seek to the correct position within the current clip
        let timeInCurrentClip = targetTime - accumulatedTime
        let targetCMTime = CMTime(seconds: timeInCurrentClip, preferredTimescale: 600)
        
        print("🎯 Seeking to \(formatTime(timeInCurrentClip)) in clip \(targetClipIndex + 1)")
        player?.seek(to: targetCMTime)
        
        // Update current time
        currentTime = targetTime
    }
}


#Preview {
    TapePlayerView(
        tape: Tape.sampleTapes[0],
        onDismiss: {}
    )
}