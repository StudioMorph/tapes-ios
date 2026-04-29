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
                        MoodRowView(
                            mood: mood,
                            isSelected: tape.musicMood == mood,
                            isGenerating: tape.musicMood == mood && trackGen.isGenerating,
                            isReady: tape.musicMood == mood && trackGen.isReady,
                            isPreviewing: tape.musicMood == mood && trackGen.isPreviewing,
                            progress: tape.musicMood == mood ? trackGen.progress : 0,
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
        .navigationTitle("Background Music")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            if tape.musicMood != .none {
                trackGen.loadCachedState(for: tape.id)
            }
        }
        .onDisappear { trackGen.stopPreview() }
    }

    private func selectMood(_ mood: MubertAPIClient.Mood) {
        guard mood != tape.musicMood else { return }

        trackGen.cancel()
        if tape.musicMood != .none {
            Task { await MubertAPIClient.shared.clearCache(for: tape.id) }
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            tape.backgroundMusicMood = mood == .none ? nil : mood.rawValue
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
