import SwiftUI

struct VerticalVolumeSlider: View {
    @Binding var value: Double
    let icon: String
    var range: ClosedRange<Double> = 0...1

    @State private var isDragging = false
    @GestureState private var dragStartValue: Double?

    private let sliderWidth: CGFloat = 36
    private let sliderHeight: CGFloat = 120

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return (value - range.lowerBound) / span
    }

    private var volumeIcon: String {
        if value <= 0.01 {
            return "speaker.slash.fill"
        }
        if icon == "speaker.wave.2.fill" || icon == "speaker.wave.2" {
            if value < 0.33 { return "speaker.fill" }
            if value < 0.66 { return "speaker.wave.1.fill" }
            return "speaker.wave.2.fill"
        }
        return icon
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let height = geo.size.height
                let fillHeight = fraction * height

                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: sliderWidth / 2)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: sliderWidth / 2)
                        .fill(.white.opacity(0.35))
                        .frame(height: fillHeight)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($dragStartValue) { _, state, _ in
                            if state == nil { state = value }
                        }
                        .onChanged { gesture in
                            isDragging = true
                            let y = gesture.location.y
                            let newFraction = 1.0 - (y / height)
                            let span = range.upperBound - range.lowerBound
                            value = range.lowerBound + min(max(newFraction, 0), 1) * span
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
            }
            .frame(width: sliderWidth, height: sliderHeight)

            Image(systemName: volumeIcon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
        }
    }
}
