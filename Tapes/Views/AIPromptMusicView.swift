import SwiftUI

struct AIPromptMusicView: View {
    @Binding var tape: Tape
    let onTrackGenerated: () -> Void

    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var trackGen = TrackGenerationManager()

    @State private var promptText = ""
    @State private var duration: Double = 30

    var body: some View {
        ScrollView {
            VStack(spacing: Tokens.Spacing.m) {
                if showsTopCard {
                    topCard
                }
                inputCard
                creditLabel
            }
            .padding(Tokens.Spacing.m)
        }
        .background(Tokens.Colors.primaryBackground)
        .onAppear {
            if let prompt = inUsePrompt {
                trackGen.loadCachedState(for: tape.id)
                if promptText.isEmpty { promptText = prompt }
            }
        }
        .onDisappear {
            trackGen.cancel()
        }
    }

    private var inUsePrompt: String? {
        guard tape.backgroundMusicMood == "prompt",
              let prompt = tape.backgroundMusicPrompt,
              !prompt.isEmpty else { return nil }
        return prompt
    }

    private var showsTopCard: Bool {
        trackGen.isGenerating || trackGen.isReady || inUsePrompt != nil
    }

    // MARK: - Top card
    //
    // Priority (highest first):
    //   1. Generating  → "Generating" + progress
    //   2. Scratch ready → LibraryTrackRow with "Use this track" CTA
    //   3. In-use prompt → LibraryTrackRow with "Using this track" disabled
    //   4. Nothing      → top card hidden

    @ViewBuilder
    private var topCard: some View {
        if trackGen.isGenerating {
            generatingCard
        } else if trackGen.isReady, let trackID = trackGen.scratchTrackID {
            LibraryTrackRow(
                track: scratchTrack(id: trackID),
                isExpanded: true,
                isPlaying: trackGen.isPreviewing,
                isInUse: false,
                isCommitting: false,
                metaTextOverride: scratchMetaText,
                onRegenerate: regenerateScratchPrompt,
                onTap: { /* always expanded */ },
                onTogglePreview: { trackGen.togglePreview(volume: tape.musicVolume) },
                onUse: { Task { await useTrack() } }
            )
        } else if let prompt = inUsePrompt {
            LibraryTrackRow(
                track: inUseTrack(prompt: prompt),
                isExpanded: true,
                isPlaying: trackGen.isPreviewing,
                isInUse: true,
                isCommitting: false,
                metaTextOverride: prompt.metaSnippet,
                onRegenerate: { regenerateInUsePrompt(prompt) },
                onTap: { /* always expanded */ },
                onTogglePreview: { trackGen.togglePreview(volume: tape.musicVolume) },
                onUse: { /* already in use */ }
            )
        }
    }

    private var generatingCard: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
            Text("Generating")
                .font(.headline)
                .foregroundStyle(Tokens.Colors.primaryText)

            ProgressView(value: trackGen.progress)
                .tint(Tokens.Colors.systemBlue)
        }
        .padding(Tokens.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Colors.secondaryBackground, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
    }

    // MARK: - Input card

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
            promptSection
            durationSection
            actionButton
        }
        .padding(Tokens.Spacing.m)
        .background(Tokens.Colors.secondaryBackground, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
    }

    // MARK: - Prompt

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
            Text("Describe your vibe")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Tokens.Colors.primaryText)

            TextEditor(text: $promptText)
                .scrollContentBackground(.hidden)
                .font(.body)
                .foregroundStyle(Tokens.Colors.primaryText)
                .frame(minHeight: 80, maxHeight: 120)
                .padding(Tokens.Spacing.s)
                .background(Tokens.Colors.tertiaryBackground, in: RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topLeading) {
                    if promptText.isEmpty {
                        Text("e.g. Warm lo-fi beats for a sunset montage…")
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

    // MARK: - Duration

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
            HStack {
                Text("Duration")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Tokens.Colors.primaryText)
                Spacer()
                Text("\(Int(duration))s")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Tokens.Colors.secondaryText)
            }

            Slider(value: $duration, in: 15...90, step: 5)
                .tint(Tokens.Colors.systemBlue)
        }
    }

    // MARK: - Action button (idle / generating / ready)

    @ViewBuilder
    private var actionButton: some View {
        if trackGen.isGenerating {
            Button(role: .destructive, action: stopGeneration) {
                Text("Stop Generation")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        } else if trackGen.isReady {
            Button(action: generateAgain) {
                Text("Generate Again")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(trimmedPrompt.isEmpty)
        } else {
            Button(action: generateAgain) {
                Text("Generate Track")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(trimmedPrompt.isEmpty)
        }
    }

    private var creditLabel: some View {
        Text("Powered by Mubert AI")
            .font(.caption2)
            .foregroundStyle(Tokens.Colors.tertiaryText)
    }

    // MARK: - Actions

    private var trimmedPrompt: String {
        String(promptText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
    }

    private func generateAgain() {
        guard let api = authManager.apiClient else { return }
        let prompt = trimmedPrompt
        guard !prompt.isEmpty else { return }
        trackGen.generateFromPrompt(
            prompt: prompt,
            duration: Int(duration),
            intensity: "medium",
            api: api
        )
    }

    /// Refresh icon on the scratch card → regenerate using the prompt that
    /// produced the current scratch track (ignores edits to the text box).
    private func regenerateScratchPrompt() {
        guard let api = authManager.apiClient,
              let prompt = trackGen.lastPrompt else { return }
        trackGen.generateFromPrompt(
            prompt: prompt,
            duration: trackGen.lastDuration,
            intensity: trackGen.lastIntensity,
            api: api
        )
    }

    /// Refresh icon on the in-use card → regenerate using the persisted prompt.
    /// The user can adjust duration via the slider; intensity stays "medium".
    private func regenerateInUsePrompt(_ prompt: String) {
        guard let api = authManager.apiClient else { return }
        trackGen.generateFromPrompt(
            prompt: prompt,
            duration: Int(duration),
            intensity: "medium",
            api: api
        )
    }

    private func stopGeneration() {
        trackGen.cancel()
    }

    private func useTrack() async {
        let committed = await trackGen.commitScratch(to: tape.id)
        guard committed != nil else { return }

        tape.backgroundMusicMood = "prompt"
        tape.backgroundMusicPrompt = trackGen.lastPrompt
        if tape.waveColorHue == nil {
            tape.waveColorHue = Double.random(in: 0...1)
        }
        onTrackGenerated()
    }

    // MARK: - Synthesised LibraryTrack for the top card

    /// Synthesises a `LibraryTrack` for a scratch (preview) track.
    /// The Mubert track ID is used so the seeded namer gives a stable name
    /// for the duration of the scratch session.
    private func scratchTrack(id: String) -> TapesAPIClient.LibraryTrack {
        TapesAPIClient.LibraryTrack(
            id: id,
            bpm: nil,
            key: nil,
            duration: trackGen.lastDuration,
            intensity: nil,
            mode: nil,
            playlistIndex: nil,
            generations: nil
        )
    }

    /// Synthesises a `LibraryTrack` for the persisted in-use prompt.
    /// We seed the row's ID with the prompt text itself, so the same prompt
    /// always renders the same name across launches.
    private func inUseTrack(prompt: String) -> TapesAPIClient.LibraryTrack {
        TapesAPIClient.LibraryTrack(
            id: "prompt:\(prompt)",
            bpm: nil,
            key: nil,
            duration: nil,
            intensity: nil,
            mode: nil,
            playlistIndex: nil,
            generations: nil
        )
    }

    /// Meaningful meta line for an AI-generated track: the prompt that produced it.
    private var scratchMetaText: String? {
        trackGen.lastPrompt?.metaSnippet
    }
}

private extension String {
    /// Quoted, ellipsised snippet of a prompt for use in a meta line.
    var metaSnippet: String {
        guard !isEmpty else { return "" }
        let snippet = String(prefix(80))
        return "\u{201C}\(snippet)\(count > 80 ? "\u{2026}" : "")\u{201D}"
    }
}
