import SwiftUI

struct PlayerHeader: View {
    let tapeName: String
    let currentClipIndex: Int
    let totalClips: Int
    let totalDuration: Double
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.2))
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .contentShape(Circle())
                }
                .accessibilityLabel("Close player")

                Spacer()

                Text(clipCounterText)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(.black.opacity(0.2))
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }

            Text(tapeName)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
    }

    private var clipCounterText: AttributedString {
        var counter = AttributedString("\(currentClipIndex + 1)/\(totalClips)")
        counter.font = .system(size: 14, weight: .semibold)

        var duration = AttributedString(" - \(formatTime(totalDuration))")
        duration.font = .system(size: 14)

        return counter + duration
    }

    private func formatTime(_ time: Double) -> String {
        guard time.isFinite else { return "0:00" }
        let clamped = max(0, time)
        let totalSeconds = Int(clamped)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    PlayerHeader(
        tapeName: "Summer Holidays",
        currentClipIndex: 0,
        totalClips: 55,
        totalDuration: 1925,
        onDismiss: {}
    )
    .background(Color.black)
}
