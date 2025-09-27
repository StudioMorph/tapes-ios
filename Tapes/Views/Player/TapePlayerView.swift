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
                CustomVideoPlayerView(player: player)
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
            // Progress bar
            ProgressView(value: currentTime, total: totalDuration)
                .progressViewStyle(LinearProgressViewStyle(tint: .white))
                .scaleEffect(y: 2)
            
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
        
        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        
        // Add observer for when video ends
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            self.onVideoEnded()
        }
        
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
}

// MARK: - Custom Video Player View (No Built-in Controls)

struct CustomVideoPlayerView: UIViewRepresentable {
    let player: AVPlayer
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        playerLayer.frame = view.bounds
        view.layer.addSublayer(playerLayer)
        
        // Store the layer for later updates
        context.coordinator.playerLayer = playerLayer
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let playerLayer = context.coordinator.playerLayer {
            playerLayer.frame = uiView.bounds
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var playerLayer: AVPlayerLayer?
    }
}

#Preview {
    TapePlayerView(
        tape: Tape.sampleTapes[0],
        onDismiss: {}
    )
}