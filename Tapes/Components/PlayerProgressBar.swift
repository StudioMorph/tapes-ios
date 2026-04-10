import SwiftUI

// MARK: - Scrub Bar (Group 2)

struct PlayerScrubBar: View {
    let currentTime: Double
    let totalDuration: Double
    let onSeek: (Double) -> Void

    private var progressFraction: CGFloat {
        guard totalDuration > 0 else { return 0 }
        return CGFloat(min(max(currentTime / totalDuration, 0), 1))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.white.opacity(0.3))
                    .background(.ultraThinMaterial)

                Rectangle()
                    .fill(Color(red: 0, green: 0.478, blue: 1))
                    .frame(width: max(0, geometry.size.width * progressFraction))
                    .clipShape(
                        .rect(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 100,
                            topTrailingRadius: 100
                        )
                    )
            }
            .contentShape(Rectangle().inset(by: -8))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let progress = max(0, min(1, value.location.x / geometry.size.width))
                        onSeek(totalDuration * progress)
                    }
            )
        }
        .frame(height: 8)
    }
}

// MARK: - Time Labels (inside Group 3)

struct PlayerTimeLabels: View {
    let currentTime: Double
    let totalDuration: Double

    var body: some View {
        HStack {
            Text(formatTime(currentTime))
                .font(.system(size: 12))
                .foregroundStyle(.white)

            Spacer()

            Text(formatTime(totalDuration))
                .font(.system(size: 12))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
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
    VStack(spacing: 0) {
        PlayerScrubBar(currentTime: 155, totalDuration: 326, onSeek: { _ in })
        PlayerTimeLabels(currentTime: 155, totalDuration: 326)
            .padding(.top, 6)
    }
    .background(Color.black)
}
