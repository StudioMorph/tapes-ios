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
            VStack(spacing: Tokens.Space.s24) {
                // Transition options
                VStack(alignment: .leading, spacing: Tokens.Space.s16) {
                    Text("Transition")
                        .font(Tokens.Typography.title)
                        .foregroundColor(Tokens.Colors.textPrimary)
                    
                    VStack(spacing: Tokens.Space.s12) {
                        // None option
                        Button(action: {
                            transition = .none
                            hasChanges = true
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                                    Text("None (Hard Cut)")
                                        .font(Tokens.Typography.title)
                                        .foregroundColor(Tokens.Colors.textPrimary)
                                    
                                    Text("Default for speed and clarity")
                                        .font(Tokens.Typography.caption)
                                        .foregroundColor(Tokens.Colors.textMuted)
                                }
                                
                                Spacer()
                                
                                if transition == .none {
                                    Image(systemName: "checkmark")
                                        .font(.title2)
                                        .foregroundColor(Tokens.Colors.textPrimary)
                                }
                            }
                            .padding(Tokens.Space.s16)
                            .background(Tokens.Colors.surfaceElevated)
                            .cornerRadius(Tokens.Radius.card)
                        }
                        
                        // Crossfade option
                        Button(action: {
                            transition = .crossfade
                            hasChanges = true
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                                    Text("Crossfade")
                                        .font(Tokens.Typography.title)
                                        .foregroundColor(Tokens.Colors.textPrimary)
                                    
                                    Text("The industry-standard, smooth and safe choice")
                                        .font(Tokens.Typography.caption)
                                        .foregroundColor(Tokens.Colors.textMuted)
                                }
                                
                                Spacer()
                                
                                if transition == .crossfade {
                                    Image(systemName: "checkmark")
                                        .font(.title2)
                                        .foregroundColor(Tokens.Colors.textPrimary)
                                }
                            }
                            .padding(Tokens.Space.s16)
                            .background(Tokens.Colors.surfaceElevated)
                            .cornerRadius(Tokens.Radius.card)
                        }
                        
                        // Slide left to right option
                        Button(action: {
                            transition = .slideLR
                            hasChanges = true
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                                    Text("Slide (left→right)")
                                        .font(Tokens.Typography.title)
                                        .foregroundColor(Tokens.Colors.textPrimary)
                                    
                                    Text("Simple directional motion")
                                        .font(Tokens.Typography.caption)
                                        .foregroundColor(Tokens.Colors.textMuted)
                                }
                                
                                Spacer()
                                
                                if transition == .slideLR {
                                    Image(systemName: "checkmark")
                                        .font(.title2)
                                        .foregroundColor(Tokens.Colors.textPrimary)
                                }
                            }
                            .padding(Tokens.Space.s16)
                            .background(Tokens.Colors.surfaceElevated)
                            .cornerRadius(Tokens.Radius.card)
                        }
                        
                        // Slide right to left option
                        Button(action: {
                            transition = .slideRL
                            hasChanges = true
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                                    Text("Slide (right→left)")
                                        .font(Tokens.Typography.title)
                                        .foregroundColor(Tokens.Colors.textPrimary)
                                    
                                    Text("Simple directional motion")
                                        .font(Tokens.Typography.caption)
                                        .foregroundColor(Tokens.Colors.textMuted)
                                }
                                
                                Spacer()
                                
                                if transition == .slideRL {
                                    Image(systemName: "checkmark")
                                        .font(.title2)
                                        .foregroundColor(Tokens.Colors.textPrimary)
                                }
                            }
                            .padding(Tokens.Space.s16)
                            .background(Tokens.Colors.surfaceElevated)
                            .cornerRadius(Tokens.Radius.card)
                        }
                    }
                }
                
                // Conflicting aspect ratios section
                VStack(alignment: .leading, spacing: Tokens.Space.s16) {
                    Text("Conflicting aspect ratios")
                        .font(Tokens.Typography.title)
                        .foregroundColor(Tokens.Colors.textPrimary)
                    
                    VStack(spacing: Tokens.Space.s12) {
                        // Fill option
                        Button(action: {
                            scaleMode = .fill
                            hasChanges = true
                        }) {
                            HStack {
                                Image(systemName: "rectangle.fill")
                                    .font(.title2)
                                    .foregroundColor(Tokens.Colors.textPrimary)
                                
                                VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                                    Text("Fill")
                                        .font(Tokens.Typography.title)
                                        .foregroundColor(Tokens.Colors.textPrimary)
                                    
                                    Text("Scale the clip to fill the canvas")
                                        .font(Tokens.Typography.caption)
                                        .foregroundColor(Tokens.Colors.textMuted)
                                }
                                
                                Spacer()
                                
                                if scaleMode == .fill {
                                    Image(systemName: "checkmark")
                                        .font(.title2)
                                        .foregroundColor(Tokens.Colors.textPrimary)
                                }
                            }
                            .padding(Tokens.Space.s16)
                            .background(Tokens.Colors.surfaceElevated)
                            .cornerRadius(Tokens.Radius.card)
                        }
                        
                        // Fit option
                        Button(action: {
                            scaleMode = .fit
                            hasChanges = true
                        }) {
                            HStack {
                                Image(systemName: "rectangle")
                                    .font(.title2)
                                    .foregroundColor(Tokens.Colors.textPrimary)
                                
                                VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                                    Text("Fit")
                                        .font(Tokens.Typography.title)
                                        .foregroundColor(Tokens.Colors.textPrimary)
                                    
                                    Text("Fits the whole clip in the canvas")
                                        .font(Tokens.Typography.caption)
                                        .foregroundColor(Tokens.Colors.textMuted)
                                }
                                
                                Spacer()
                                
                                if scaleMode == .fit {
                                    Image(systemName: "checkmark")
                                        .font(.title2)
                                        .foregroundColor(Tokens.Colors.textPrimary)
                                }
                            }
                            .padding(Tokens.Space.s16)
                            .background(Tokens.Colors.surfaceElevated)
                            .cornerRadius(Tokens.Radius.card)
                        }
                    }
                }
                
                Spacer()
            }
            .padding(Tokens.Space.s20)
            .background(Tokens.Colors.bg)
            .navigationTitle("This settings apply across the whole Tape")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Done") {
                    onDismiss()
                },
                trailing: Button("Save") {
                    saveChanges()
                }
                .disabled(!hasChanges)
            )
        }
    }
    
    private func saveChanges() {
        tape.orientation = orientation
        tape.scaleMode = scaleMode
        tape.transition = transition
        tape.transitionDuration = transitionDuration
        onDismiss()
    }
}

#Preview("Dark Mode") {
    TapeSettingsSheet(
        tape: .constant(Tape.sampleTapes[0]),
        onDismiss: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Light Mode") {
    TapeSettingsSheet(
        tape: .constant(Tape.sampleTapes[0]),
        onDismiss: {}
    )
    .preferredColorScheme(.light)
}