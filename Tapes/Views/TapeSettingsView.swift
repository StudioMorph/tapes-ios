import SwiftUI

struct TapeSettingsView: View {
    @Binding var tape: Tape
    let onDismiss: () -> Void
    let onTapeDeleted: (() -> Void)?
    @EnvironmentObject var tapesStore: TapesStore
    
    // UI-only state
    @State private var selectedTransition: TransitionType
    @State private var transitionDuration: Double
    @State private var selectedMood: MubertAPIClient.Mood
    @State private var musicVolume: Double
    @State private var hasChanges = false
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var showingDeleteError = false
    
    init(tape: Binding<Tape>, onDismiss: @escaping () -> Void = {}, onTapeDeleted: (() -> Void)? = nil) {
        self._tape = tape
        self.onDismiss = onDismiss
        self.onTapeDeleted = onTapeDeleted
        self._selectedTransition = State(initialValue: tape.wrappedValue.transition)
        self._transitionDuration = State(initialValue: tape.wrappedValue.transitionDuration)
        self._selectedMood = State(initialValue: tape.wrappedValue.musicMood)
        self._musicVolume = State(initialValue: Double(tape.wrappedValue.musicVolume))
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Tokens.Spacing.xl) {
                    transitionSection
                        .accessibilitySortPriority(1)
                    
                    if selectedTransition != .none {
                        transitionDurationSection
                            .accessibilitySortPriority(2)
                    }

                    backgroundMusicSection
                        .accessibilitySortPriority(3)

                    if selectedMood != .none {
                        musicVolumeSection
                            .accessibilitySortPriority(4)
                    }

                    destructiveActionSection
                        .accessibilitySortPriority(5)
                }
                .padding(.horizontal, Tokens.Spacing.l)
                .padding(.vertical, Tokens.Spacing.l)
            }
            .background(Tokens.Colors.primaryBackground.ignoresSafeArea())
            .navigationTitle("Tape Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        resetToBindingValues()
                        onDismiss()
                    }
                    .foregroundColor(Tokens.Colors.primaryText)
                    .accessibilityLabel("Cancel changes and close settings")
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                        onDismiss()
                    }
                    .foregroundColor(hasChanges ? .blue : Tokens.Colors.secondaryText)
                    .disabled(!hasChanges)
                    .accessibilityLabel(hasChanges ? "Save changes" : "No changes to save")
                    .accessibilityHint(hasChanges ? "Saves the current transition settings" : "No changes have been made")
                }
            }
        }
        .onChange(of: transitionDuration) { _ in hasChanges = true }
        .onChange(of: tape) { _ in resetToBindingValues() }
        .alert("Delete this Tape?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteTape()
            }
        } message: {
            Text("This will delete the Tape and its album. Your photos and videos remain in your device's Library.")
        }
        .alert("Delete Failed", isPresented: $showingDeleteError) {
            Button("OK") {
                showingDeleteError = false
                deleteError = nil
            }
        } message: {
            if let error = deleteError {
                Text(error)
            }
        }
    }
    
    // MARK: - Sections
    
    private var transitionSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.l) {
            SectionHeader(title: "Choose default transition")
            
            VStack(spacing: Tokens.Spacing.s) {
                ForEach(TransitionType.allCases, id: \.self) { transition in
                    TransitionOption(
                        transition: transition,
                        isSelected: selectedTransition == transition,
                        onSelect: {
                            selectedTransition = transition
                            hasChanges = true
                            provideHapticFeedback()
                        }
                    )
                }
            }
        }
    }
    
    private var transitionDurationSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.l) {
            SectionHeader(title: "Transition Duration")
            
            TransitionDurationSlider(
                duration: $transitionDuration,
                hasChanges: $hasChanges
            )
        }
    }
    
    private var backgroundMusicSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.l) {
            SectionHeader(title: "Background Music")

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: Tokens.Spacing.s),
                GridItem(.flexible(), spacing: Tokens.Spacing.s),
                GridItem(.flexible(), spacing: Tokens.Spacing.s)
            ], spacing: Tokens.Spacing.s) {
                ForEach(MubertAPIClient.Mood.allCases) { mood in
                    MoodOptionCell(
                        mood: mood,
                        isSelected: selectedMood == mood
                    ) {
                        selectedMood = mood
                        hasChanges = true
                        provideHapticFeedback()
                    }
                }
            }
        }
    }

    private var musicVolumeSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
            SectionHeader(title: "Music Volume")

            HStack(spacing: Tokens.Spacing.m) {
                Image(systemName: "speaker.fill")
                    .foregroundColor(Tokens.Colors.secondaryText)
                    .font(.caption)

                Slider(value: $musicVolume, in: 0.05...1.0, step: 0.05)
                    .tint(Tokens.Colors.systemRed)
                    .onChange(of: musicVolume) { _ in hasChanges = true }

                Image(systemName: "speaker.wave.3.fill")
                    .foregroundColor(Tokens.Colors.secondaryText)
                    .font(.caption)
            }

            Text("\(Int(musicVolume * 100))%")
                .font(.caption)
                .foregroundColor(Tokens.Colors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var destructiveActionSection: some View {
        DestructiveActionSection(
            isDeleting: isDeleting,
            onDelete: {
                provideHapticFeedback()
                showingDeleteConfirmation = true
            }
        )
    }
    
    // MARK: - Helper Methods
    
    private func resetToBindingValues() {
        selectedTransition = tape.transition
        transitionDuration = tape.transitionDuration
        selectedMood = tape.musicMood
        musicVolume = Double(tape.musicVolume)
        hasChanges = false
    }
    
    private func saveChanges() {
        var updated = tape
        updated.updateSettings(
            orientation: tape.orientation,
            scaleMode: tape.scaleMode,
            transition: selectedTransition,
            transitionDuration: transitionDuration
        )
        updated.backgroundMusicMood = selectedMood == .none ? nil : selectedMood.rawValue
        updated.backgroundMusicVolume = musicVolume
        tape = updated
        hasChanges = false
    }
    
    private func deleteTape() {
        isDeleting = true
        
        Task {
            // Call the existing delete functionality
            await MainActor.run {
                tapesStore.deleteTape(tape)
            }
            
            // Success - provide haptic feedback
            #if os(iOS)
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.notificationOccurred(.success)
            #endif
            
            // Dismiss modal and show success toast
            await MainActor.run {
                onDismiss()
                onTapeDeleted?()
            }
        }
    }
    
    private func provideHapticFeedback() {
        #if os(iOS)
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        #endif
    }
}

// MARK: - Previews

#Preview("Default State") {
    TapeSettingsView(
        tape: .constant(Tape.sampleTapes[0]),
        onDismiss: {},
        onTapeDeleted: nil
    )
    .environmentObject(TapesStore())
}

#Preview("Dark Mode") {
    TapeSettingsView(
        tape: .constant(Tape.sampleTapes[0]),
        onDismiss: {},
        onTapeDeleted: nil
    )
    .environmentObject(TapesStore())
    .preferredColorScheme(.dark)
}

#Preview("Dynamic Type XL") {
    TapeSettingsView(
        tape: .constant(Tape.sampleTapes[0]),
        onDismiss: {},
        onTapeDeleted: nil
    )
    .environmentObject(TapesStore())
    .environment(\.sizeCategory, .accessibilityExtraLarge)
}

#Preview("RTL") {
    TapeSettingsView(
        tape: .constant(Tape.sampleTapes[0]),
        onDismiss: {},
        onTapeDeleted: nil
    )
    .environmentObject(TapesStore())
    .environment(\.layoutDirection, .rightToLeft)
}

#Preview("Loading State") {
    TapeSettingsView(
        tape: .constant(Tape.sampleTapes[0]),
        onDismiss: {},
        onTapeDeleted: nil
    )
    .environmentObject(TapesStore())
    .onAppear {
        // Simulate loading state
    }
}
