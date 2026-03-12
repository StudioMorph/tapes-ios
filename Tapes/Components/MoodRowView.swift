import SwiftUI

struct MoodRowView: View {
    let mood: MubertAPIClient.Mood
    let isSelected: Bool
    let isGenerating: Bool
    let isReady: Bool
    let isPreviewing: Bool
    let progress: Double
    let onSelect: () -> Void
    let onPreview: () -> Void
    let onRegenerate: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 0) {
                HStack(spacing: Tokens.Spacing.m) {
                    Image(systemName: mood.icon)
                        .font(.body)
                        .foregroundColor(isSelected ? .blue : Tokens.Colors.secondaryText)
                        .frame(width: 24)

                    Text(mood.displayName)
                        .font(Tokens.Typography.headline)
                        .foregroundColor(Tokens.Colors.primaryText)

                    Spacer()

                    if isSelected && mood != .none {
                        actionButtons
                    }

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                            .font(.body)
                    }
                }
                .padding(.vertical, Tokens.Spacing.m)
                .padding(.horizontal, Tokens.Spacing.m)

                if isSelected && mood != .none {
                    progressBar
                }
            }
            .background(Tokens.Colors.secondaryBackground)
            .cornerRadius(Tokens.Radius.card)
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
                    .font(.body)
                    .foregroundColor(isReady ? .blue : Tokens.Colors.tertiaryText)
                    .frame(width: 24, height: 24)
            }
            .disabled(!isReady)
            .buttonStyle(.plain)
            .accessibilityLabel(isPreviewing ? "Stop preview" : "Preview track")

            Button(action: onRegenerate) {
                Image(systemName: "arrow.trianglehead.2.clockwise")
                    .font(.body)
                    .foregroundColor(isReady ? Tokens.Colors.primaryText : Tokens.Colors.tertiaryText)
                    .frame(width: 24, height: 24)
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

    // MARK: - Progress Bar

    @ViewBuilder
    private var progressBar: some View {
        if isGenerating || isReady {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Tokens.Colors.tertiaryBackground)

                    Rectangle()
                        .fill(Color.green)
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
            onSelect: {}, onPreview: {}, onRegenerate: {}
        )
        MoodRowView(
            mood: .chill, isSelected: true, isGenerating: true,
            isReady: false, isPreviewing: false, progress: 0.6,
            onSelect: {}, onPreview: {}, onRegenerate: {}
        )
        MoodRowView(
            mood: .epic, isSelected: true, isGenerating: false,
            isReady: true, isPreviewing: false, progress: 1,
            onSelect: {}, onPreview: {}, onRegenerate: {}
        )
        MoodRowView(
            mood: .cinematic, isSelected: false, isGenerating: false,
            isReady: false, isPreviewing: false, progress: 0,
            onSelect: {}, onPreview: {}, onRegenerate: {}
        )
    }
    .padding()
    .background(Tokens.Colors.primaryBackground)
}
