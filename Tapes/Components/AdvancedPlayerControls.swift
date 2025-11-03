import SwiftUI
import AVFoundation

/// Phase 3: Advanced controls with playback speed and thumbnail scrubbing
struct AdvancedPlayerControls: View {
    let isPlaying: Bool
    let playbackSpeed: Float
    let canGoBack: Bool
    let canGoForward: Bool
    let onPlayPause: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onSpeedChange: (Float) -> Void
    let onFrameStep: (Int) -> Void // +1 for forward, -1 for backward
    
    @State private var showingSpeedMenu = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Speed control
            HStack(spacing: 16) {
                Text("Speed")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(.white.opacity(0.8))
                
                Button(action: { showingSpeedMenu.toggle() }) {
                    Text(formatSpeed(playbackSpeed))
                        .font(Tokens.Typography.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .actionSheet(isPresented: $showingSpeedMenu) {
                    speedMenu
                }
                
                // Frame-by-frame controls
                Button(action: { onFrameStep(-1) }) {
                    Image(systemName: "arrow.left.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .disabled(!canGoBack)
                .accessibilityLabel("Step backward one frame")
                
                Button(action: { onFrameStep(1) }) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .disabled(!canGoForward)
                .accessibilityLabel("Step forward one frame")
            }
            
            // Standard controls
            HStack(spacing: 32) {
                // Previous button
                Button(action: onPrevious) {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(canGoBack ? .white : .white.opacity(0.4))
                        .frame(width: 56, height: 56)
                        .background(.ultraThinMaterial, in: Circle())
                        .contentShape(Circle())
                }
                .disabled(!canGoBack)
                .accessibilityLabel("Previous clip")
                
                // Play/Pause button
                Button(action: onPlayPause) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(.ultraThinMaterial, in: Circle())
                        .contentShape(Circle())
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                }
                .accessibilityLabel(isPlaying ? "Pause" : "Play")
                
                // Next button
                Button(action: onNext) {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(canGoForward ? .white : .white.opacity(0.4))
                        .frame(width: 56, height: 56)
                        .background(.ultraThinMaterial, in: Circle())
                        .contentShape(Circle())
                }
                .disabled(!canGoForward)
                .accessibilityLabel("Next clip")
            }
        }
        .padding(.horizontal, 20)
    }
    
    private var speedMenu: ActionSheet {
        ActionSheet(
            title: Text("Playback Speed"),
            buttons: [
                .default(Text("0.5x")) { onSpeedChange(0.5) },
                .default(Text("1x")) { onSpeedChange(1.0) },
                .default(Text("1.5x")) { onSpeedChange(1.5) },
                .default(Text("2x")) { onSpeedChange(2.0) },
                .cancel()
            ]
        )
    }
    
    private func formatSpeed(_ speed: Float) -> String {
        return String(format: "%.1fx", speed)
    }
}

