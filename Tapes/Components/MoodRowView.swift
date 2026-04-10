import SwiftUI

struct MoodRowView: View {
    let mood: MubertAPIClient.Mood
    let isSelected: Bool
    let isGenerating: Bool
    let isReady: Bool
    let isPreviewing: Bool
    let progress: Double
    @Binding var volume: Double
    let onSelect: () -> Void
    let onPreview: () -> Void
    let onRegenerate: () -> Void
    let onVolumeChanged: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 0) {
                HStack(spacing: Tokens.Spacing.m) {
                    Image(systemName: mood.icon)
                        .font(.title3)
                        .foregroundColor(Tokens.Colors.primaryText)
                        .frame(width: 28)

                    Text(mood.displayName)
                        .font(Tokens.Typography.headline)
                        .foregroundColor(Tokens.Colors.primaryText)

                    Spacer()

                    if isSelected && mood != .none {
                        actionButtons
                    }

                    if isSelected && mood == .none {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                            .font(Tokens.Typography.title)
                    }
                }
                .padding(.vertical, Tokens.Spacing.m)
                .padding(.horizontal, Tokens.Spacing.m)

                if isSelected && mood != .none {
                    volumeSlider
                        .padding(.horizontal, Tokens.Spacing.m)
                        .padding(.bottom, Tokens.Spacing.m)

                    progressBar
                }
            }
            .background(Tokens.Colors.secondaryBackground)
            .cornerRadius(Tokens.Radius.card)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
        .frame(minHeight: Tokens.HitTarget.minimum)
        .accessibilityLabel("\(mood.displayName) mood")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: Tokens.Spacing.xl) {
            Button(action: onPreview) {
                previewIcon
                    .font(.title3)
                    .foregroundColor(isReady ? .blue : Tokens.Colors.tertiaryText)
                    .frame(width: 28, height: 28)
            }
            .disabled(!isReady)
            .buttonStyle(.plain)
            .accessibilityLabel(isPreviewing ? "Stop preview" : "Preview track")

            Button(action: onRegenerate) {
                Image(systemName: "arrow.trianglehead.2.clockwise")
                    .font(.title3)
                    .foregroundColor(isReady ? Tokens.Colors.primaryText : Tokens.Colors.tertiaryText)
                    .frame(width: 28, height: 28)
            }
            .disabled(isGenerating)
            .buttonStyle(.plain)
            .accessibilityLabel("Regenerate track")
        }
    }

    @ViewBuilder
    private var previewIcon: some View {
        if isPreviewing {
            SoundWaveAnimationView()
        } else {
            Image(systemName: "waveform")
        }
    }

    // MARK: - Volume Slider

    private var volumeSlider: some View {
        HStack(spacing: Tokens.Spacing.s) {
            Image(systemName: "speaker.fill")
                .font(.caption)
                .foregroundColor(isReady ? Tokens.Colors.secondaryText : Tokens.Colors.tertiaryText)

            Slider(value: $volume, in: 0.05...1.0, step: 0.05)
                .tint(isReady ? .blue : Tokens.Colors.tertiaryText)
                .disabled(!isReady)
                .onChange(of: volume) { _ in onVolumeChanged() }

            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
                .foregroundColor(isReady ? Tokens.Colors.secondaryText : Tokens.Colors.tertiaryText)

            Text("\(Int(volume * 100))%")
                .font(.caption)
                .foregroundColor(isReady ? Tokens.Colors.secondaryText : Tokens.Colors.tertiaryText)
                .frame(width: 36, alignment: .trailing)
        }
    }

    // MARK: - Progress Bar

    @ViewBuilder
    private var progressBar: some View {
        if isGenerating || isReady {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Tokens.Colors.tertiaryBackground)

                    Rectangle()
                        .fill(isReady ? Color.blue : Color.green)
                        .frame(width: geo.size.width * progress)
                        .animation(.linear(duration: 0.3), value: progress)
                }
            }
            .frame(height: 3)
            .clipShape(RoundedRectangle(cornerRadius: 1.5))
        }
    }
}

// MARK: - Animated Sound Wave

struct SoundWaveAnimationView: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.blue)
                    .frame(width: 3, height: animating ? barHeight(for: i) : 4)
                    .animation(
                        .easeInOut(duration: 0.4 + Double(i) * 0.1)
                        .repeatForever(autoreverses: true),
                        value: animating
                    )
            }
        }
        .frame(width: 24, height: 18)
        .onAppear { animating = true }
    }

    private func barHeight(for index: Int) -> CGFloat {
        switch index {
        case 0: return 10
        case 1: return 16
        case 2: return 12
        case 3: return 18
        default: return 8
        }
    }
}

#Preview {
    VStack(spacing: Tokens.Spacing.s) {
        MoodRowView(
            mood: .none, isSelected: true, isGenerating: false,
            isReady: false, isPreviewing: false, progress: 0,
            volume: .constant(0.8),
            onSelect: {}, onPreview: {}, onRegenerate: {}, onVolumeChanged: {}
        )
        MoodRowView(
            mood: .chill, isSelected: true, isGenerating: true,
            isReady: false, isPreviewing: false, progress: 0.6,
            volume: .constant(0.8),
            onSelect: {}, onPreview: {}, onRegenerate: {}, onVolumeChanged: {}
        )
        MoodRowView(
            mood: .epic, isSelected: true, isGenerating: false,
            isReady: true, isPreviewing: false, progress: 1,
            volume: .constant(0.8),
            onSelect: {}, onPreview: {}, onRegenerate: {}, onVolumeChanged: {}
        )
        MoodRowView(
            mood: .cinematic, isSelected: false, isGenerating: false,
            isReady: false, isPreviewing: false, progress: 0,
            volume: .constant(0.8),
            onSelect: {}, onPreview: {}, onRegenerate: {}, onVolumeChanged: {}
        )
    }
    .padding()
    .background(Tokens.Colors.primaryBackground)
}
