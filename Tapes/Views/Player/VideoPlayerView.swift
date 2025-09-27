import SwiftUI
import AVFoundation
import AVKit

// MARK: - Video Player View

struct VideoPlayerView: View {
    let clip: Clip
    @State private var player: AVPlayer?
    @State private var playerItem: AVPlayerItem?
    @State private var isPlaying: Bool = false
    
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
        
        // Start playing
        player?.play()
        isPlaying = true
        
        print("✅ VideoPlayerView: Player created and started")
    }
}

#Preview {
    VideoPlayerView(clip: Clip(
        localURL: URL(string: "file:///path/to/video.mov"),
        clipType: .video,
        duration: 5.0
    ))
}
