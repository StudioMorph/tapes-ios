import SwiftUI

// MARK: - Tape Settings Sheet

public struct TapeSettingsSheet: View {
    @Binding var tape: Tape
    let onDismiss: () -> Void
    
    @State private var selectedOrientation: TapeOrientation
    @State private var selectedScaleMode: ScaleMode
    @State private var selectedTransition: TransitionType
    @State private var transitionDuration: Double
    @State private var hasChanges: Bool = false
    
    public init(tape: Binding<Tape>, onDismiss: @escaping () -> Void) {
        self._tape = tape
        self.onDismiss = onDismiss
        self._selectedOrientation = State(initialValue: tape.wrappedValue.orientation)
        self._selectedScaleMode = State(initialValue: tape.wrappedValue.scaleMode)
        self._selectedTransition = State(initialValue: tape.wrappedValue.transition)
        self._transitionDuration = State(initialValue: tape.wrappedValue.transitionDuration)
    }
    
    public var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: DesignTokens.Spacing.s24) {
                    // Header
                    VStack(spacing: DesignTokens.Spacing.s8) {
                        Text("Tape Settings")
                            .font(DesignTokens.Typography.heading(28, weight: .bold))
                            .foregroundColor(DesignTokens.Colors.onSurface(.light))
                        
                        Text(tape.title)
                            .font(DesignTokens.Typography.title)
                            .foregroundColor(DesignTokens.Colors.muted(60))
                    }
                    .padding(.top, DesignTokens.Spacing.s16)
                    
                    // Settings Controls
                    VStack(spacing: DesignTokens.Spacing.s32) {
                        // Orientation Section
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s16) {
                            Text("Orientation")
                                .font(DesignTokens.Typography.title)
                                .foregroundColor(DesignTokens.Colors.onSurface(.light))
                            
                            HStack(spacing: DesignTokens.Spacing.s12) {
                                ForEach(TapeOrientation.allCases, id: \.self) { orientation in
                                    OrientationButton(
                                        orientation: orientation,
                                        isSelected: selectedOrientation == orientation
                                    ) {
                                        selectedOrientation = orientation
                                        updateChanges()
                                    }
                                }
                            }
                        }
                        
                        // Scale Mode Section
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s16) {
                            Text("Scale Mode")
                                .font(DesignTokens.Typography.title)
                                .foregroundColor(DesignTokens.Colors.onSurface(.light))
                            
                            Text("Conflicting aspect ratios")
                                .font(DesignTokens.Typography.caption)
                                .foregroundColor(DesignTokens.Colors.muted(60))
                            
                            HStack(spacing: DesignTokens.Spacing.s12) {
                                ForEach(ScaleMode.allCases, id: \.self) { scaleMode in
                                    ScaleModeButton(
                                        scaleMode: scaleMode,
                                        isSelected: selectedScaleMode == scaleMode
                                    ) {
                                        selectedScaleMode = scaleMode
                                        updateChanges()
                                    }
                                }
                            }
                        }
                        
                        // Transition Section
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s16) {
                            Text("Transition")
                                .font(DesignTokens.Typography.title)
                                .foregroundColor(DesignTokens.Colors.onSurface(.light))
                            
                            VStack(spacing: DesignTokens.Spacing.s12) {
                                ForEach(TransitionType.allCases, id: \.self) { transition in
                                    TransitionButton(
                                        transition: transition,
                                        isSelected: selectedTransition == transition
                                    ) {
                                        selectedTransition = transition
                                        updateChanges()
                                        
                                        // Clamp duration to 0.5s for Randomise
                                        if transition == .randomise {
                                            transitionDuration = min(transitionDuration, 0.5)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Duration Section
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s16) {
                            Text("Transition Duration")
                                .font(DesignTokens.Typography.title)
                                .foregroundColor(DesignTokens.Colors.onSurface(.light))
                            
                            VStack(spacing: DesignTokens.Spacing.s12) {
                                HStack {
                                    Text("0.2s")
                                        .font(DesignTokens.Typography.caption)
                                        .foregroundColor(DesignTokens.Colors.muted(60))
                                    
                                    Spacer()
                                    
                                    Text("\(String(format: "%.1f", transitionDuration))s")
                                        .font(DesignTokens.Typography.body)
                                        .foregroundColor(DesignTokens.Colors.onSurface(.light))
                                        .fontWeight(.medium)
                                    
                                    Spacer()
                                    
                                    Text("1.0s")
                                        .font(DesignTokens.Typography.caption)
                                        .foregroundColor(DesignTokens.Colors.muted(60))
                                }
                                
                                Slider(
                                    value: $transitionDuration,
                                    in: 0.2...1.0,
                                    step: 0.1
                                ) {
                                    Text("Duration")
                                } minimumValueLabel: {
                                    Text("0.2")
                                        .font(DesignTokens.Typography.caption)
                                } maximumValueLabel: {
                                    Text("1.0")
                                        .font(DesignTokens.Typography.caption)
                                }
                                .accentColor(DesignTokens.Colors.primaryRed)
                                .onChange(of: transitionDuration) { _ in
                                    updateChanges()
                                    
                                    // Clamp to 0.5s for Randomise
                                    if selectedTransition == .randomise {
                                        transitionDuration = min(transitionDuration, 0.5)
                                    }
                                }
                                
                                if selectedTransition == .randomise {
                                    Text("Randomise transition is limited to 0.5s maximum")
                                        .font(DesignTokens.Typography.caption)
                                        .foregroundColor(DesignTokens.Colors.muted(60))
                                        .multilineTextAlignment(.center)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.s20)
                    
                    Spacer(minLength: DesignTokens.Spacing.s32)
                }
            }
            .background(DesignTokens.Colors.surface(.light))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    onDismiss()
                }
                .foregroundColor(DesignTokens.Colors.muted(60)),
                trailing: Button("Save") {
                    saveChanges()
                    onDismiss()
                }
                .foregroundColor(hasChanges ? DesignTokens.Colors.primaryRed : DesignTokens.Colors.muted(60))
                .disabled(!hasChanges)
            )
        }
    }
    
    private func updateChanges() {
        hasChanges = selectedOrientation != tape.orientation ||
                    selectedScaleMode != tape.scaleMode ||
                    selectedTransition != tape.transition ||
                    abs(transitionDuration - tape.transitionDuration) > 0.01
    }
    
    private func saveChanges() {
        tape.orientation = selectedOrientation
        tape.scaleMode = selectedScaleMode
        tape.transition = selectedTransition
        tape.transitionDuration = transitionDuration
        tape.updatedAt = Date()
    }
}

// MARK: - Orientation Button

private struct OrientationButton: View {
    let orientation: TapeOrientation
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: DesignTokens.Spacing.s8) {
                // Aspect ratio indicator
                RoundedRectangle(cornerRadius: DesignTokens.Radius.thumbnail)
                    .fill(isSelected ? DesignTokens.Colors.primaryRed : DesignTokens.Colors.muted(20))
                    .frame(
                        width: orientation == .portrait ? 36 : 64,
                        height: orientation == .portrait ? 64 : 36
                    )
                
                Text(orientation.displayName)
                    .font(DesignTokens.Typography.caption)
                    .foregroundColor(isSelected ? DesignTokens.Colors.primaryRed : DesignTokens.Colors.muted(60))
                    .fontWeight(isSelected ? .medium : .regular)
            }
            .padding(.vertical, DesignTokens.Spacing.s12)
            .padding(.horizontal, DesignTokens.Spacing.s16)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.thumbnail)
                    .fill(isSelected ? DesignTokens.Colors.primaryRed.opacity(0.1) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.thumbnail)
                            .stroke(
                                isSelected ? DesignTokens.Colors.primaryRed : DesignTokens.Colors.muted(30),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Scale Mode Button

private struct ScaleModeButton: View {
    let scaleMode: ScaleMode
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(scaleMode.displayName)
                    .font(DesignTokens.Typography.body)
                    .foregroundColor(isSelected ? .white : DesignTokens.Colors.onSurface(.light))
                    .fontWeight(isSelected ? .medium : .regular)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            .padding(.vertical, DesignTokens.Spacing.s12)
            .padding(.horizontal, DesignTokens.Spacing.s16)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.thumbnail)
                    .fill(isSelected ? DesignTokens.Colors.primaryRed : DesignTokens.Colors.muted(10))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.thumbnail)
                            .stroke(
                                isSelected ? DesignTokens.Colors.primaryRed : DesignTokens.Colors.muted(30),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Transition Button

private struct TransitionButton: View {
    let transition: TransitionType
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(transition.displayName)
                    .font(DesignTokens.Typography.body)
                    .foregroundColor(isSelected ? .white : DesignTokens.Colors.onSurface(.light))
                    .fontWeight(isSelected ? .medium : .regular)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            .padding(.vertical, DesignTokens.Spacing.s12)
            .padding(.horizontal, DesignTokens.Spacing.s16)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.thumbnail)
                    .fill(isSelected ? DesignTokens.Colors.primaryRed : DesignTokens.Colors.muted(10))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.thumbnail)
                            .stroke(
                                isSelected ? DesignTokens.Colors.primaryRed : DesignTokens.Colors.muted(30),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

struct TapeSettingsSheet_Previews: PreviewProvider {
    static var previews: some View {
        TapeSettingsSheet(
            tape: .constant(Tape(
                title: "My Test Tape",
                orientation: .portrait,
                scaleMode: .fit,
                transition: .crossfade,
                transitionDuration: 0.5
            )),
            onDismiss: { print("Dismissed") }
        )
        .previewDisplayName("Tape Settings Sheet")
    }
}
