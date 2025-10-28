import SwiftUI

struct TapeSettingsSheet: View {
    @Binding var tape: Tape
    let onDismiss: () -> Void
    let onTapeDeleted: (() -> Void)?
    @EnvironmentObject var tapesStore: TapesStore
    
    @State private var transition: TransitionType
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
        self._transition = State(initialValue: tape.wrappedValue.transition)
        self._transitionDuration = State(initialValue: tape.wrappedValue.transitionDuration)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 32) {
                    transitionSection
                    if transition != .none {
                        transitionDurationSection
                    }
                    deleteSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Tokens.Spacing.l)
                .padding(.top, Tokens.Spacing.l)
                .padding(.bottom, Tokens.Spacing.l * 2)
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
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                        onDismiss()
                    }
                    .foregroundColor(hasChanges ? Tokens.Colors.red : Tokens.Colors.muted)
                    .disabled(!hasChanges)
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
    
    private var transitionSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.l) {
            Text("Choose default transition")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Tokens.Colors.onSurface)
            
            VStack(spacing: Tokens.Spacing.m) {
                transitionOption(title: "None (Hard Cut)", description: "Default for speed and clarity", value: .none)
                transitionOption(title: "Crossfade", description: "The industry-standard, smooth and safe choice", value: .crossfade)
                transitionOption(title: "Slide (left→right)", description: "Horizontal slide between clips", value: .slideLR)
                transitionOption(title: "Slide (right→left)", description: "Horizontal slide between clips", value: .slideRL)
            }
        }
    }
    
    private var transitionDurationSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.l) {
            Text("Transition Duration")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Tokens.Colors.onSurface)
            
            VStack(spacing: Tokens.Spacing.s) {
                HStack {
                    Text("0.1s")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Tokens.Colors.muted)
                    
                    Slider(value: $transitionDuration, in: 0.1...2.0, step: 0.1)
                        .accentColor(Tokens.Colors.red)
                    
                    Text("2.0s")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Tokens.Colors.muted)
                }
                
                Text("\(String(format: "%.1f", transitionDuration))s")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Tokens.Colors.onSurface)
            }
            .padding(Tokens.Spacing.l)
            .background(Tokens.Colors.elevated)
            .cornerRadius(Tokens.Radius.card)
        }
    }
    
    private var deleteSection: some View {
        VStack(alignment: .center, spacing: Tokens.Spacing.m) {
            Button(action: {
                // Provide haptic feedback
                #if os(iOS)
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                #endif
                showingDeleteConfirmation = true
            }) {
                HStack(spacing: Tokens.Spacing.s) {
                    if isDeleting {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle(tint: Tokens.Colors.red))
                    } else {
                        Image(systemName: "trash")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(Tokens.Colors.red)
                    }
                    
                    Text("Delete Tape")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Tokens.Colors.red)
                }
                .frame(maxWidth: .infinity)
                .padding(Tokens.Spacing.l)
                .background(Tokens.Colors.elevated)
                .cornerRadius(Tokens.Radius.card)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isDeleting)
            .accessibilityLabel("Delete Tape, destructive")
            .accessibilityHint("Deletes the tape and its album. Photos and videos remain in your device's Library.")
            
            // Explanatory text below the button
            VStack(spacing: 2) {
                Text("Also deletes the album from your device.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Tokens.Colors.muted)
                    .multilineTextAlignment(.center)
                
                Text("All photos and videos will remain in your device's Library.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Tokens.Colors.muted)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    private func transitionOption(title: String, description: String, value: TransitionType) -> some View {
        Button(action: {
            transition = value
            hasChanges = true
        }) {
            HStack {
                VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Tokens.Colors.onSurface)
                    
                    Text(description)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Tokens.Colors.muted)
                }
                
                Spacer()
                
                if transition == value {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Tokens.Colors.red)
                        .font(.system(size: 20))
                }
            }
            .padding(Tokens.Spacing.l)
            .background(Tokens.Colors.elevated)
            .cornerRadius(Tokens.Radius.card)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func saveChanges() {
        var updated = tape
        updated.updateSettings(
            orientation: tape.orientation,
            scaleMode: tape.scaleMode,
            transition: transition,
            transitionDuration: transitionDuration
        )
        tape = updated
        hasChanges = false
    }

    private func resetToBindingValues() {
        transition = tape.transition
        transitionDuration = tape.transitionDuration
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
}

#Preview {
    TapeSettingsSheet(tape: .constant(Tape.sampleTapes[0]))
        .environmentObject(TapesStore())
}
