import SwiftUI

struct VerticalVolumeSlider: View {
    @Binding var value: Double
    let icon: String
    var range: ClosedRange<Double> = 0...1

    @State private var isDragging = false
    @GestureState private var dragStartValue: Double?

    private let sliderWidth: CGFloat = 48

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return (value - range.lowerBound) / span
    }

    private var volumeIcon: String {
        if value <= 0.01 {
            if icon == "music.note" { return "music.note.slash" }
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
        GeometryReader { screen in
            let sliderHeight = screen.size.height / 3

            VStack(spacing: 0) {
                Spacer()

                GeometryReader { geo in
                    let height = geo.size.height
                    let fillHeight = fraction * height
                    let cornerRadius = sliderWidth / 2

                    ZStack(alignment: .bottom) {
                        Capsule()
                            .fill(.clear)

                        Capsule()
                            .fill(.white.opacity(0.4))
                            .frame(height: fillHeight)

                        VStack {
                            Spacer()
                            Image(systemName: volumeIcon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.3), radius: 2)
                                .padding(.bottom, 12)
                        }
                    }
                    .clipShape(Capsule())
                    .modifier(GlassEffectModifier())
                    .contentShape(Capsule())
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
            }
        }
        .frame(width: sliderWidth)
    }
}

private struct GlassEffectModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(.ultraThinMaterial, in: Capsule())
        }
    }
}
