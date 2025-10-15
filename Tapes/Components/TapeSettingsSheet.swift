import SwiftUI

struct TapeSettingsSheet: View {
    @Binding var tape: Tape
    let onDismiss: () -> Void
    
    @State private var orientation: TapeOrientation
    @State private var scaleMode: ScaleMode
    @State private var transition: TransitionType
    @State private var transitionDuration: Double
    @State private var hasChanges = false
    
    init(tape: Binding<Tape>, onDismiss: @escaping () -> Void = {}) {
        self._tape = tape
        self.onDismiss = onDismiss
        self._orientation = State(initialValue: tape.wrappedValue.orientation)
        self._scaleMode = State(initialValue: tape.wrappedValue.scaleMode)
        self._transition = State(initialValue: tape.wrappedValue.transition)
        self._transitionDuration = State(initialValue: tape.wrappedValue.transitionDuration)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Tokens.Spacing.l) {
                    transitionSection
                    if transition != .none {
                        transitionDurationSection
                    }
                    orientationSection
                    scaleModeSection
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
    }
    
    private var transitionSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.l) {
            Text("Transition")
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
    
    private var orientationSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.l) {
            Text("Orientation")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Tokens.Colors.onSurface)
            
            VStack(spacing: Tokens.Spacing.m) {
                orientationOption(title: "Portrait", description: "9:16 aspect ratio", value: .portrait)
                orientationOption(title: "Landscape", description: "16:9 aspect ratio", value: .landscape)
            }
        }
    }
    
    private var scaleModeSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.l) {
            Text("Scale Mode")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Tokens.Colors.onSurface)
            
            VStack(spacing: Tokens.Spacing.m) {
                scaleModeOption(title: "Fill", description: "Crop to fill frame", value: .fill)
                scaleModeOption(title: "Fit", description: "Scale to fit frame", value: .fit)
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
    
    private func orientationOption(title: String, description: String, value: TapeOrientation) -> some View {
        Button(action: {
            orientation = value
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
                
                if orientation == value {
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
    
    private func scaleModeOption(title: String, description: String, value: ScaleMode) -> some View {
        Button(action: {
            scaleMode = value
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
                
                if scaleMode == value {
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
            orientation: orientation,
            scaleMode: scaleMode,
            transition: transition,
            transitionDuration: transitionDuration
        )
        tape = updated
        hasChanges = false
    }

    private func resetToBindingValues() {
        orientation = tape.orientation
        scaleMode = tape.scaleMode
        transition = tape.transition
        transitionDuration = tape.transitionDuration
        hasChanges = false
    }
}

#Preview {
    TapeSettingsSheet(tape: .constant(Tape.sampleTapes[0]))
}
