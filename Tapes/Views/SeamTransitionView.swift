import SwiftUI

struct SeamTransitionView: View {
    @Binding var tape: Tape
    let leftClipID: UUID
    let rightClipID: UUID
    let onDismiss: () -> Void
    @EnvironmentObject var tapesStore: TapesStore

    @State private var selectedStyle: TransitionType
    @State private var duration: Double
    @State private var isOverridden: Bool
    @State private var hasChanges = false

    /// Per-seam options exclude `.randomise` — that's a tape-level concept only.
    private static let availableStyles: [TransitionType] = [.none, .crossfade, .slideLR, .slideRL]

    init(
        tape: Binding<Tape>,
        leftClipID: UUID,
        rightClipID: UUID,
        onDismiss: @escaping () -> Void
    ) {
        self._tape = tape
        self.leftClipID = leftClipID
        self.rightClipID = rightClipID
        self.onDismiss = onDismiss

        let existing = tape.wrappedValue.seamTransition(leftClipID: leftClipID, rightClipID: rightClipID)
        if let existing {
            self._selectedStyle = State(initialValue: existing.style)
            self._duration = State(initialValue: existing.duration)
            self._isOverridden = State(initialValue: true)
        } else {
            let tapeDefault = tape.wrappedValue.transition
            let style = (tapeDefault == .randomise) ? .crossfade : tapeDefault
            self._selectedStyle = State(initialValue: style)
            self._duration = State(initialValue: tape.wrappedValue.transitionDuration)
            self._isOverridden = State(initialValue: false)
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Tokens.Spacing.xl) {
                    transitionSection

                    if selectedStyle != .none {
                        durationSection
                    }

                    if isOverridden {
                        resetSection
                    }
                }
                .padding(.horizontal, Tokens.Spacing.l)
                .padding(.vertical, Tokens.Spacing.l)
            }
            .background(Tokens.Colors.primaryBackground.ignoresSafeArea())
            .navigationTitle("Seam Transition")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onDismiss()
                    }
                    .foregroundColor(Tokens.Colors.primaryText)
                    .accessibilityLabel("Cancel and close")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        save()
                        onDismiss()
                    }
                    .foregroundColor(hasChanges ? .blue : Tokens.Colors.secondaryText)
                    .disabled(!hasChanges)
                    .accessibilityLabel(hasChanges ? "Save changes" : "No changes to save")
                }
            }
        }
        .onChange(of: duration) { _ in hasChanges = true }
    }

    // MARK: - Sections

    private var transitionSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.l) {
            SectionHeader(title: "Transition style")

            VStack(spacing: Tokens.Spacing.s) {
                ForEach(Self.availableStyles, id: \.self) { style in
                    TransitionOption(
                        transition: style,
                        isSelected: selectedStyle == style,
                        onSelect: {
                            selectedStyle = style
                            isOverridden = true
                            hasChanges = true
                            provideHaptic()
                        }
                    )
                }
            }
        }
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.l) {
            SectionHeader(title: "Duration")

            TransitionDurationSlider(
                duration: $duration,
                hasChanges: $hasChanges
            )
        }
    }

    private var resetSection: some View {
        Button {
            resetToDefault()
            provideHaptic()
        } label: {
            HStack {
                Image(systemName: "arrow.uturn.backward")
                Text("Use Tape Default")
            }
            .font(Tokens.Typography.headline)
            .foregroundColor(.blue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Tokens.Spacing.m)
            .background(Tokens.Colors.secondaryBackground)
            .cornerRadius(Tokens.Radius.card)
        }
        .buttonStyle(.plain)
        .frame(minHeight: Tokens.HitTarget.minimum)
        .accessibilityLabel("Reset to tape default transition")
    }

    // MARK: - Actions

    private func save() {
        if isOverridden {
            let override = SeamTransition(style: selectedStyle, duration: duration)
            tape.setSeamTransition(override, leftClipID: leftClipID, rightClipID: rightClipID)
        } else {
            tape.setSeamTransition(nil, leftClipID: leftClipID, rightClipID: rightClipID)
        }
        tapesStore.updateTape(tape)
    }

    private func resetToDefault() {
        let tapeDefault = tape.transition
        let style = (tapeDefault == .randomise) ? .crossfade : tapeDefault
        selectedStyle = style
        duration = tape.transitionDuration
        isOverridden = false
        hasChanges = true
    }

    private func provideHaptic() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

#Preview("Default State") {
    SeamTransitionView(
        tape: .constant(Tape.sampleTapes[1]),
        leftClipID: Tape.sampleTapes[1].clips[0].id,
        rightClipID: Tape.sampleTapes[1].clips[1].id,
        onDismiss: {}
    )
    .environmentObject(TapesStore())
}

#Preview("Dark Mode") {
    SeamTransitionView(
        tape: .constant(Tape.sampleTapes[1]),
        leftClipID: Tape.sampleTapes[1].clips[0].id,
        rightClipID: Tape.sampleTapes[1].clips[1].id,
        onDismiss: {}
    )
    .environmentObject(TapesStore())
    .preferredColorScheme(.dark)
}
