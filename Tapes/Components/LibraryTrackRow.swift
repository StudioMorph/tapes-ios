import SwiftUI

/// A single track cell for the 12K Library browser.
///
/// Visual states:
/// - Collapsed: artwork + title + meta line. No icon.
/// - Expanded (previewing): + animated waveform icon + "Use this track" CTA.
/// - Expanded (paused): + static waveform glyph + "Use this track" CTA.
/// - In-use: always expanded, 2pt blue stroke, "Using this track" disabled.
struct LibraryTrackRow: View {
    let track: TapesAPIClient.LibraryTrack
    let isExpanded: Bool
    let isPlaying: Bool
    let isInUse: Bool
    let isCommitting: Bool
    let onTap: () -> Void
    let onTogglePreview: () -> Void
    let onUse: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            if isExpanded {
                actionArea
            }
        }
        .background(Tokens.Colors.secondaryBackground, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .strokeBorder(isInUse ? Tokens.Colors.systemBlue : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isExpanded else { return }
            onTap()
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .animation(.easeInOut(duration: 0.2), value: isPlaying)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: Tokens.Spacing.m) {
            artwork

            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Tokens.Colors.primaryText)
                    .lineLimit(1)

                Text(metaText)
                    .font(.caption)
                    .foregroundStyle(Tokens.Colors.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            previewIconButton
        }
        .padding(Tokens.Spacing.m)
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(artworkGradient)
                .frame(width: 36, height: 36)

            Image(systemName: "music.note")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
        }
    }

    private var artworkGradient: LinearGradient {
        let hue = Double(abs(track.id.hashValue % 1000)) / 1000.0
        return LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.6, brightness: 0.7),
                Color(hue: (hue + 0.1).truncatingRemainder(dividingBy: 1.0), saturation: 0.5, brightness: 0.9)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var previewIconButton: some View {
        Button(action: isExpanded ? onTogglePreview : onTap) {
            Group {
                if isPlaying {
                    SoundWaveAnimationView()
                } else {
                    Image(systemName: "waveform")
                        .font(.title3)
                        .foregroundStyle(Tokens.Colors.systemBlue)
                }
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Stop preview" : "Preview track")
    }

    // MARK: - Action area

    private var actionArea: some View {
        VStack(spacing: 0) {
            useButton
                .padding(.horizontal, Tokens.Spacing.m)
                .padding(.bottom, Tokens.Spacing.m)
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private var useButton: some View {
        if isInUse {
            Button(action: {}) {
                Text("Using this track")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.regular)
            .disabled(true)
        } else {
            Button(action: onUse) {
                Text(isCommitting ? "Saving…" : "Use this track")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.regular)
            .disabled(isCommitting)
        }
    }

    // MARK: - Text helpers

    private var titleText: String {
        track.displayTitle
    }

    private var metaText: String {
        var parts: [String] = []
        if let bpm = track.bpm { parts.append("\(bpm) bpm") }
        if let duration = track.duration { parts.append(formatDuration(duration)) }
        if let intensity = track.intensity, !intensity.isEmpty { parts.append(intensity.capitalized) }
        if parts.isEmpty { return "—" }
        return "• " + parts.joined(separator: " • ")
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
