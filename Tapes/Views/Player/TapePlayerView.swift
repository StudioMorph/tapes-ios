import SwiftUI
import AVFoundation
import AVKit

// MARK: - Clean Tape Player View

struct TapePlayerView: View {
    @State private var player: AVPlayer?
    @State private var currentClipIndex: Int = 0
    @State private var isPlaying: Bool = false
    @State private var showingControls: Bool = true
    @State private var controlsTimer: Timer?
    
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
            player?.pause()
            controlsTimer?.invalidate()
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
                    .onAppear {
                        print("🎬 Playing clip \(currentClipIndex + 1) of \(tape.clips.count)")
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
            // Progress indicator
            progressView
            
            // Control buttons
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
        .padding()
    }
    
    // MARK: - Progress View
    
    private var progressView: some View {
        HStack {
            Text("\(currentClipIndex + 1) of \(tape.clips.count)")
                .foregroundColor(.white)
            
            Spacer()
            
            if let clip = currentClip {
                Text(formatDuration(clip.duration))
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
        loadCurrentClip()
    }
    
    private func loadCurrentClip() {
        guard let clip = currentClip,
              let url = clip.localURL else {
            print("❌ No clip or URL available")
            return
        }
        
        print("🎬 Loading clip \(currentClipIndex + 1): \(clip.id)")
        
        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        
        // Auto-play when loaded
        player?.play()
        isPlaying = true
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
    
    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    TapePlayerView(
        tape: Tape.sampleTapes[0],
        onDismiss: {}
    )
}