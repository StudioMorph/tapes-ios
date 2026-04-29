import SwiftUI

struct BackgroundMusicPickerView: View {
    @Binding var tape: Tape
    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var trackGen = TrackGenerationManager()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.l) {
                VStack(spacing: Tokens.Spacing.s) {
                    ForEach(MubertAPIClient.Mood.allCases) { mood in
                        let selected = isSelected(mood)
                        MoodRowView(
                            mood: mood,
                            isSelected: selected,
                            isGenerating: selected && trackGen.isGenerating,
                            isReady: selected && trackGen.isReady,
                            isPreviewing: selected && trackGen.isPreviewing,
                            progress: selected ? trackGen.progress : 0,
                            volume: Binding(
                                get: { Double(tape.musicVolume) },
                                set: { tape.backgroundMusicVolume = $0 }
                            ),
                            onSelect: { selectMood(mood) },
                            onPreview: { trackGen.togglePreview(volume: tape.musicVolume) },
                            onRegenerate: {
                                guard let api = authManager.apiClient else { return }
                                trackGen.regenerate(mood: mood, tapeID: tape.id, api: api)
                            },
                            onVolumeChanged: {
                                trackGen.updatePreviewVolume(tape.musicVolume)
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, Tokens.Spacing.l)
            .padding(.vertical, Tokens.Spacing.l)
        }
        .background(Tokens.Colors.primaryBackground.ignoresSafeArea())
        .onAppear {
            if currentMood != nil {
                trackGen.loadCachedState(for: tape.id)
            }
        }
        .onDisappear { trackGen.stopPreview() }
    }

    /// The currently selected mood, *only* when `backgroundMusicMood`
    /// holds a real mood rawValue. Returns `nil` for library / prompt
    /// tracks (and for "no music"), so those don't accidentally light
    /// up the "None" row.
    private var currentMood: MubertAPIClient.Mood? {
        guard let raw = tape.backgroundMusicMood,
              let mood = MubertAPIClient.Mood(rawValue: raw),
              mood != .none else { return nil }
        return mood
    }

    /// Selection rule for a mood row.
    /// - `.none` is selected only when there is genuinely no background
    ///   music (`backgroundMusicMood == nil`). It does **not** show as
    ///   selected when a library or prompt track is in use.
    /// - Any other mood is selected only when its rawValue matches
    ///   `backgroundMusicMood` exactly.
    private func isSelected(_ mood: MubertAPIClient.Mood) -> Bool {
        if mood == .none {
            return tape.backgroundMusicMood == nil
        }
        return tape.backgroundMusicMood == mood.rawValue
    }

    private func selectMood(_ mood: MubertAPIClient.Mood) {
        guard !isSelected(mood) else { return }

        trackGen.cancel()
        if tape.backgroundMusicMood != nil {
            Task { await MubertAPIClient.shared.clearCache(for: tape.id) }
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            tape.backgroundMusicMood = mood == .none ? nil : mood.rawValue
            tape.backgroundMusicPrompt = nil
            if mood != .none && tape.waveColorHue == nil {
                tape.waveColorHue = Double.random(in: 0...1)
            }
        }
        provideHapticFeedback()

        if mood != .none, let api = authManager.apiClient {
            trackGen.generate(mood: mood, tapeID: tape.id, api: api)
        }
    }

    private func provideHapticFeedback() {
        #if os(iOS)
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        #endif
    }
}

#Preview {
    NavigationView {
        BackgroundMusicPickerView(tape: .constant(Tape.sampleTapes[0]))
            .environmentObject(AuthManager())
    }
}
