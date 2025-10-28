import SwiftUI

struct TapeSettingsView: View {
    @Binding var tape: Tape
    let onDismiss: () -> Void
    let onTapeDeleted: (() -> Void)?
    @EnvironmentObject var tapesStore: TapesStore
    
    // UI-only state
    @State private var selectedTransition: TransitionType
    @State private var transitionDuration: Double
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
                    
                    destructiveActionSection
                        .accessibilitySortPriority(3)
                }
                .padding(.horizontal, Tokens.Spacing.l)
                .padding(.vertical, Tokens.Spacing.l)
            }
            .background(Tokens.Colors.bg.ignoresSafeArea())
            .navigationTitle("Tape Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        resetToBindingValues()
                        onDismiss()
                    }
                    .foregroundColor(Tokens.Colors.onSurface)
                    .accessibilityLabel("Cancel changes and close settings")
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                        onDismiss()
                    }
                    .foregroundColor(hasChanges ? Tokens.Colors.red : Tokens.Colors.muted)
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
            
            VStack(spacing: Tokens.Spacing.m) {
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
