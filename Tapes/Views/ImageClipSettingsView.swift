import SwiftUI

struct ImageClipSettingsView: View {
    @Binding var tape: Tape
    let clipID: UUID
    let onDismiss: () -> Void
    @EnvironmentObject var tapesStore: TapesStore

    @State private var selectedMotion: MotionStyle
    @State private var duration: Double
    @State private var hasChanges = false

    init(tape: Binding<Tape>, clipID: UUID, onDismiss: @escaping () -> Void) {
        self._tape = tape
        self.clipID = clipID
        self.onDismiss = onDismiss

        if let clip = tape.wrappedValue.clips.first(where: { $0.id == clipID }) {
            self._selectedMotion = State(initialValue: clip.motionStyle)
            self._duration = State(initialValue: clip.imageDuration)
        } else {
            self._selectedMotion = State(initialValue: .kenBurns)
            self._duration = State(initialValue: 4.0)
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Tokens.Spacing.xl) {
                    motionSection
                    durationSection
                }
                .padding(.horizontal, Tokens.Spacing.l)
                .padding(.vertical, Tokens.Spacing.l)
            }
            .background(Tokens.Colors.primaryBackground.ignoresSafeArea())
            .navigationTitle("Image Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { onDismiss() }
                        .foregroundColor(Tokens.Colors.primaryText)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        save()
                        onDismiss()
                    }
                    .foregroundColor(hasChanges ? .blue : Tokens.Colors.secondaryText)
                    .disabled(!hasChanges)
                }
            }
        }
        .onChange(of: duration) { _ in hasChanges = true }
    }

    // MARK: - Sections

    private var motionSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.l) {
            SectionHeader(title: "Motion style")

            VStack(spacing: Tokens.Spacing.s) {
                ForEach(MotionStyle.allCases, id: \.self) { style in
                    MotionOptionRow(
                        style: style,
                        isSelected: selectedMotion == style,
                        onSelect: {
                            selectedMotion = style
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
            SectionHeader(title: "Display duration")

            ImageDurationSlider(
                duration: $duration,
                hasChanges: $hasChanges
            )
        }
    }

    // MARK: - Actions

    private func save() {
        guard var clip = tape.clips.first(where: { $0.id == clipID }) else { return }
        clip.motionStyle = selectedMotion
        clip.imageDuration = duration
        clip.duration = duration
        clip.updatedAt = Date()
        tape.updateClip(clip)
        tapesStore.updateTape(tape)
    }

    private func provideHaptic() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

// MARK: - Motion Option Row

private struct MotionOptionRow: View {
    let style: MotionStyle
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                    Text(style.displayName)
                        .font(Tokens.Typography.headline)
                        .foregroundColor(Tokens.Colors.primaryText)

                    Text(style.description)
                        .font(Tokens.Typography.caption)
                        .foregroundColor(Tokens.Colors.secondaryText)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(Tokens.Typography.title)
                }
            }
            .padding(.vertical, Tokens.Spacing.m)
            .padding(.horizontal, Tokens.Spacing.m)
            .background(Tokens.Colors.secondaryBackground)
            .cornerRadius(Tokens.Radius.card)
        }
        .buttonStyle(.plain)
        .frame(minHeight: Tokens.HitTarget.minimum)
        .accessibilityLabel(style.displayName)
        .accessibilityHint(style.description)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Image Duration Slider

private struct ImageDurationSlider: View {
    @Binding var duration: Double
    @Binding var hasChanges: Bool

    var body: some View {
        VStack(spacing: Tokens.Spacing.s) {
            HStack {
                Text("4s")
                    .font(Tokens.Typography.caption)
                    .foregroundColor(Tokens.Colors.secondaryText)

                Slider(value: $duration, in: 4.0...10.0, step: 0.5)
                    .accentColor(.blue)
                    .onChange(of: duration) { _ in
                        hasChanges = true
                    }

                Text("10s")
                    .font(Tokens.Typography.caption)
                    .foregroundColor(Tokens.Colors.secondaryText)
            }

            Text("\(String(format: "%.1f", duration))s")
                .font(Tokens.Typography.headline)
                .foregroundColor(Tokens.Colors.primaryText)
        }
        .padding(Tokens.Spacing.l)
        .background(Tokens.Colors.secondaryBackground)
        .cornerRadius(Tokens.Radius.card)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Display duration")
        .accessibilityValue("\(String(format: "%.1f", duration)) seconds")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                duration = min(10.0, duration + 0.5)
            case .decrement:
                duration = max(4.0, duration - 0.5)
            @unknown default:
                break
            }
        }
    }
}
