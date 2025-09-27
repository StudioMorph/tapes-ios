import SwiftUI
import AVFoundation
import AVKit
import UIKit

// MARK: - Video Player View

struct VideoPlayerView: View {
    let clip: Clip
    @State private var player: AVPlayer?
    @State private var playerItem: AVPlayerItem?
    @State private var isPlaying: Bool = false
    @Binding var shouldPlay: Bool
    
    var body: some View {
        ZStack {
            if let player = player {
                VideoPlayer(player: player)
                    .onAppear {
                        print("🎥 VideoPlayerView: Playing clip \(clip.id), URL: \(clip.localURL?.absoluteString ?? "nil")")
                    }
                    .onDisappear {
                        player.pause()
                    }
            } else {
                // Loading or error state
                VStack(spacing: Tokens.Spacing.l) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48, weight: .light))
                        .foregroundColor(Tokens.Colors.muted)
                    
                    Text("Video Not Available")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Tokens.Colors.muted)
                    
                    if let url = clip.localURL {
                        Text("URL: \(url.lastPathComponent)")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(Tokens.Colors.muted)
                    }
                }
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
        }
        .onChange(of: shouldPlay) { _, newValue in
            if newValue {
                player?.play()
                isPlaying = true
                print("🎥 VideoPlayerView: Started playing due to shouldPlay = true")
            } else {
                player?.pause()
                isPlaying = false
                print("🎥 VideoPlayerView: Paused due to shouldPlay = false")
            }
        }
    }
    
    private func setupPlayer() {
        guard let url = clip.localURL else {
            print("❌ VideoPlayerView: No local URL for clip \(clip.id)")
            return
        }
        
        print("🎥 VideoPlayerView: Setting up player for URL: \(url.absoluteString)")
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("❌ VideoPlayerView: File does not exist at path: \(url.path)")
            return
        }
        
        // Create player item
        playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        
        // Don't auto-play - wait for shouldPlay binding
        print("✅ VideoPlayerView: Player created (not auto-playing)")
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
        
        print("🖼️ CustomVideoPlayerView: makeUIView - Created playerLayer with frame: \(view.bounds)")
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let playerLayer = context.coordinator.playerLayer {
            // Ensure the layer is properly sized
            DispatchQueue.main.async {
                playerLayer.frame = uiView.bounds
                print("🖼️ CustomVideoPlayerView: updateUIView - Updated frame to: \(uiView.bounds)")
            }
        } else {
            print("⚠️ CustomVideoPlayerView: updateUIView - playerLayer is nil")
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
    VideoPlayerView(clip: Clip(
        localURL: URL(string: "file:///path/to/video.mov"),
        clipType: .video,
        duration: 5.0
    ), shouldPlay: .constant(true))
}
