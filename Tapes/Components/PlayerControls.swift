import SwiftUI

struct PlayerControls: View {
    let isPlaying: Bool
    let isFinished: Bool
    let canGoBack: Bool
    let canGoForward: Bool
    let onPlayPause: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void

    private var playButtonIcon: String {
        if isFinished { return "gobackward" }
        return isPlaying ? "pause.fill" : "play.fill"
    }

    private var playButtonLabel: String {
        if isFinished { return "Replay" }
        return isPlaying ? "Pause" : "Play"
    }

    var body: some View {
        HStack(spacing: 32) {
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

            Button(action: onPlayPause) {
                Image(systemName: playButtonIcon)
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(.ultraThinMaterial, in: Circle())
                    .contentShape(Circle())
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            }
            .accessibilityLabel(playButtonLabel)

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
        .padding(.horizontal, 20)
    }
}

#Preview {
    PlayerControls(
        isPlaying: false,
        isFinished: false,
        canGoBack: true,
        canGoForward: true,
        onPlayPause: {},
        onPrevious: {},
        onNext: {}
    )
    .padding()
    .background(Color.black)
}
