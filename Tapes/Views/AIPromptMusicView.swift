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
            VStack(alignment: .leading, spacing: Tokens.Spacing.l) {
                promptSection
                durationSection
                generateButton
                if trackGen.isReady {
                    previewControls
                    useButton
                }
                creditLabel
            }
            .padding(.horizontal, Tokens.Spacing.m)
            .padding(.vertical, Tokens.Spacing.l)
        }
        .background(Tokens.Colors.primaryBackground)
        .onDisappear {
            trackGen.cancel()
        }
    }

    // MARK: - Prompt

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
            Text("Describe the vibe")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Tokens.Colors.primaryText)

            TextEditor(text: $promptText)
                .scrollContentBackground(.hidden)
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

    // MARK: - Generate

    private var generateButton: some View {
        VStack(spacing: Tokens.Spacing.s) {
            Button {
                generate()
            } label: {
                HStack {
                    if trackGen.isGenerating {
                        ProgressView()
                            .tint(.white)
                        Text("Generating…")
                    } else {
                        Text(trackGen.isReady ? "Generate again" : "Generate track")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(trackGen.isGenerating || trimmedPrompt.isEmpty)

            if trackGen.isGenerating {
                ProgressView(value: trackGen.progress)
                    .tint(Tokens.Colors.systemBlue)
            }

            if case .failed(let message) = trackGen.state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Color.red)
            }
        }
    }

    // MARK: - Preview controls (after generation)

    private var previewControls: some View {
        VStack(spacing: Tokens.Spacing.m) {
            HStack(spacing: Tokens.Spacing.xl) {
                Button {
                    trackGen.togglePreview(volume: tape.musicVolume)
                } label: {
                    HStack(spacing: Tokens.Spacing.s) {
                        if trackGen.isPreviewing {
                            SoundWaveAnimationView()
                            Text("Stop")
                        } else {
                            Image(systemName: "play.fill")
                            Text("Preview")
                        }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Tokens.Spacing.s)
                }
                .buttonStyle(.plain)
            }
            .padding(Tokens.Spacing.s)
            .background(Tokens.Colors.secondaryBackground, in: RoundedRectangle(cornerRadius: 12))

            volumeSlider
        }
    }

    private var volumeSlider: some View {
        let volumeBinding = Binding<Double>(
            get: { Double(tape.musicVolume) },
            set: { tape.backgroundMusicVolume = $0 }
        )

        return HStack(spacing: Tokens.Spacing.s) {
            Image(systemName: "speaker.fill")
                .font(.caption)
                .foregroundStyle(Tokens.Colors.secondaryText)

            Slider(value: volumeBinding, in: 0.05...1.0, step: 0.05)
                .tint(.blue)
                .onChange(of: volumeBinding.wrappedValue) {
                    trackGen.updatePreviewVolume(tape.musicVolume)
                }

            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
                .foregroundStyle(Tokens.Colors.secondaryText)

            Text("\(Int(volumeBinding.wrappedValue * 100))%")
                .font(.caption)
                .foregroundStyle(Tokens.Colors.secondaryText)
                .frame(width: 36, alignment: .trailing)
        }
    }

    private var useButton: some View {
        Button {
            Task { await useTrack() }
        } label: {
            Text("Use this track")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.green)
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

    private var trimmedPrompt: String {
        String(promptText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
    }

    private func generate() {
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

    private func useTrack() async {
        let committed = await trackGen.commitScratch(to: tape.id)
        guard committed != nil else { return }

        tape.backgroundMusicMood = "prompt"
        if tape.waveColorHue == nil {
            tape.waveColorHue = Double.random(in: 0...1)
        }
        onTrackGenerated()
    }
}
