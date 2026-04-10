import SwiftUI

struct VerticalVolumeSlider: View {
    @Binding var value: Double
    let icon: String
    var range: ClosedRange<Double> = 0...1

    @State private var isExpanded = false
    @State private var collapseTask: Task<Void, Never>?
    @GestureState private var dragStartValue: Double?

    private let pillSize: CGFloat = 44
    private let expandedWidth: CGFloat = 44
    private let collapseDuration: TimeInterval = 3

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

                if isExpanded {
                    expandedSlider(height: sliderHeight)
                        .transition(.scale(scale: 0.5, anchor: .bottom).combined(with: .opacity))
                } else {
                    collapsedPill
                        .transition(.scale(scale: 0.8, anchor: .bottom).combined(with: .opacity))
                }
            }
        }
        .frame(width: expandedWidth)
    }

    // MARK: - Collapsed Pill

    private var collapsedPill: some View {
        Button {
            expand()
        } label: {
            Image(systemName: volumeIcon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: pillSize, height: pillSize)
                .background(.black.opacity(0.2))
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
    }

    // MARK: - Expanded Slider

    private func expandedSlider(height: CGFloat) -> some View {
        GeometryReader { geo in
            let h = geo.size.height
            let fillHeight = fraction * h

            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(.black.opacity(0.2))
                    .background(.ultraThinMaterial, in: Capsule())

                Capsule()
                    .fill(.white.opacity(0.8))
                    .frame(height: fillHeight)

                VStack {
                    Spacer()
                    Image(systemName: volumeIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(red: 0, green: 0.478, blue: 1))
                        .padding(.bottom, 10)
                }
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($dragStartValue) { _, state, _ in
                        if state == nil { state = value }
                    }
                    .onChanged { gesture in
                        resetCollapseTimer()
                        let y = gesture.location.y
                        let newFraction = 1.0 - (y / h)
                        let span = range.upperBound - range.lowerBound
                        value = range.lowerBound + min(max(newFraction, 0), 1) * span
                    }
                    .onEnded { _ in
                        resetCollapseTimer()
                    }
            )
        }
        .frame(width: expandedWidth, height: height)
    }

    // MARK: - Expand / Collapse

    private func expand() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isExpanded = true
        }
        resetCollapseTimer()
    }

    private func collapse() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isExpanded = false
        }
    }

    private func resetCollapseTimer() {
        collapseTask?.cancel()
        collapseTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(collapseDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { collapse() }
        }
    }
}
