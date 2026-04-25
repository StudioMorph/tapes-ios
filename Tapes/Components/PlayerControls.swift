import SwiftUI

struct PlayerControls: View {
    let isPlaying: Bool
    let isFinished: Bool
    let canGoBack: Bool
    let canGoForward: Bool
    var isDisabled: Bool = false
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

    private var disabledOpacity: Double { isDisabled ? 0.3 : 1.0 }

    var body: some View {
        HStack(spacing: 32) {
            Button(action: onPrevious) {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(canGoBack ? .white : .white.opacity(0.4))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!canGoBack || isDisabled)
            .accessibilityLabel("Previous clip")

            Button(action: onPlayPause) {
                Image(systemName: playButtonIcon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(isDisabled)
            .accessibilityLabel(playButtonLabel)

            Button(action: onNext) {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(canGoForward ? .white : .white.opacity(0.4))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!canGoForward || isDisabled)
            .accessibilityLabel("Next clip")
        }
        .opacity(disabledOpacity)
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
