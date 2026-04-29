import SwiftUI

struct AIPromptMusicView: View {
    @Binding var tape: Tape
    let onTrackGenerated: () -> Void

    @EnvironmentObject private var authManager: AuthManager
    @State private var promptText = ""
    @State private var duration: Double = 30
    @State private var intensity: Intensity = .medium
    @State private var isGenerating = false
    @State private var progress: Double = 0
    @State private var errorMessage: String?

    enum Intensity: String, CaseIterable {
        case low, medium, high
    }

    private let quickTags = ["Lo-fi", "Cinematic", "Ambient", "Upbeat", "Chill", "Electronic", "Jazz", "Dreamy"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.l) {
                promptSection
                quickTagsSection
                durationSection
                intensitySection
                generateButton
                creditLabel
            }
            .padding(.horizontal, Tokens.Spacing.m)
            .padding(.vertical, Tokens.Spacing.l)
        }
        .background(Tokens.Colors.primaryBackground)
    }

    // MARK: - Prompt

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
            Text("Describe the vibe")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Tokens.Colors.primaryText)

            TextEditor(text: $promptText)
                .frame(minHeight: 80, maxHeight: 120)
                .padding(Tokens.Spacing.s)
                .background(Tokens.Colors.secondaryBackground, in: RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topLeading) {
                    if promptText.isEmpty {
                        Text("e.g. Warm lo-fi beats for a sunset montage...")
                            .font(.body)
                            .foregroundStyle(Tokens.Colors.tertiaryText)
                            .padding(.horizontal, Tokens.Spacing.s + 4)
                            .padding(.top, Tokens.Spacing.s + 8)
                            .allowsHitTesting(false)
                    }
                }

            HStack {
                Spacer()
                Text("\(promptText.count)/200")
                    .font(.caption2)
                    .foregroundStyle(promptText.count > 200 ? Color.red : Tokens.Colors.tertiaryText)
            }
        }
    }

    // MARK: - Quick Tags

    private var quickTagsSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
            Text("Quick tags")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Tokens.Colors.primaryText)

            WrappingHStack(spacing: Tokens.Spacing.s) {
                ForEach(quickTags, id: \.self) { tag in
                    let isActive = promptText.localizedCaseInsensitiveContains(tag)
                    Button {
                        toggleTag(tag)
                    } label: {
                        Text(tag)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(isActive ? Tokens.Colors.systemBlue.opacity(0.15) : Tokens.Colors.secondaryBackground)
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(isActive ? Tokens.Colors.systemBlue : Color.clear, lineWidth: 1)
                            )
                            .foregroundStyle(isActive ? Tokens.Colors.systemBlue : Tokens.Colors.primaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Duration

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
            HStack {
                Text("Duration")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Tokens.Colors.primaryText)
                Spacer()
                Text("\(Int(duration))s")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Tokens.Colors.systemBlue)
            }

            Slider(value: $duration, in: 15...90, step: 5)
                .tint(Tokens.Colors.systemBlue)

            HStack {
                Text("15s")
                    .font(.caption2)
                    .foregroundStyle(Tokens.Colors.tertiaryText)
                Spacer()
                Text("90s")
                    .font(.caption2)
                    .foregroundStyle(Tokens.Colors.tertiaryText)
            }
        }
    }

    // MARK: - Intensity

    private var intensitySection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
            Text("Energy")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Tokens.Colors.primaryText)

            Picker("", selection: $intensity) {
                ForEach(Intensity.allCases, id: \.self) { level in
                    Text(level.rawValue.capitalized).tag(level)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Generate

    private var generateButton: some View {
        VStack(spacing: Tokens.Spacing.s) {
            Button {
                Task { await generate() }
            } label: {
                ZStack {
                    Text("Generate track")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Tokens.Colors.systemBlue,
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .opacity(isGenerating ? 0 : 1)

                    if isGenerating {
                        VStack(spacing: Tokens.Spacing.s) {
                            ProgressView(value: progress)
                                .tint(.white)
                            Text("Generating…")
                                .font(.caption)
                                .foregroundStyle(Tokens.Colors.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Tokens.Colors.systemBlue.opacity(0.6),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isGenerating || promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Color.red)
            }
        }
    }

    private var creditLabel: some View {
        HStack {
            Spacer()
            Text("Powered by Mubert AI")
                .font(.caption2)
                .foregroundStyle(Tokens.Colors.tertiaryText)
            Spacer()
        }
    }

    // MARK: - Actions

    private func toggleTag(_ tag: String) {
        if promptText.localizedCaseInsensitiveContains(tag) {
            promptText = promptText
                .replacingOccurrences(of: tag, with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "  ", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            if !promptText.isEmpty && !promptText.hasSuffix(" ") {
                promptText += " "
            }
            promptText += tag
        }
    }

    private func generate() async {
        guard let api = authManager.apiClient else { return }
        let trimmed = String(promptText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !trimmed.isEmpty else { return }

        isGenerating = true
        progress = 0
        errorMessage = nil

        do {
            let localURL = try await MubertAPIClient.shared.generateFromPrompt(
                prompt: trimmed,
                duration: Int(duration),
                intensity: intensity.rawValue,
                tapeID: tape.id,
                api: api,
                onProgress: { p in
                    Task { @MainActor in progress = p }
                }
            )
            tape.backgroundMusicMood = "prompt"
            if tape.waveColorHue == nil {
                tape.waveColorHue = Double.random(in: 0...1)
            }
            _ = localURL
            isGenerating = false
            onTrackGenerated()
        } catch {
            isGenerating = false
            errorMessage = error.localizedDescription
        }
    }
}

private struct WrappingHStack: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (i, subview) in subviews.enumerated() where i < result.positions.count {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[i].x,
                                      y: bounds.minY + result.positions[i].y),
                          proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }
        return (positions, CGSize(width: maxX, height: y + rowHeight))
    }
}
