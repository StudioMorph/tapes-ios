import SwiftUI

struct ImageClipSettingsView: View {
    @Binding var tape: Tape
    let clipID: UUID
    let onDismiss: () -> Void
    @EnvironmentObject var tapesStore: TapesStore

    @State private var selectedMotion: MotionStyle
    @State private var duration: Double
    @State private var livePhotoAsVideo: Bool
    @State private var livePhotoMuted: Bool
    @State private var hasChanges = false

    private var clip: Clip? {
        tape.clips.first(where: { $0.id == clipID })
    }

    private var isLivePhoto: Bool {
        clip?.isLivePhoto ?? false
    }

    init(tape: Binding<Tape>, clipID: UUID, onDismiss: @escaping () -> Void) {
        self._tape = tape
        self.clipID = clipID
        self.onDismiss = onDismiss

        if let clip = tape.wrappedValue.clips.first(where: { $0.id == clipID }) {
            self._selectedMotion = State(initialValue: clip.motionStyle)
            self._duration = State(initialValue: clip.imageDuration)
            let tapeDefault = tape.wrappedValue.livePhotosAsVideo
            self._livePhotoAsVideo = State(initialValue: clip.livePhotoAsVideo ?? tapeDefault)
            let muteDefault = tape.wrappedValue.livePhotosMuted
            self._livePhotoMuted = State(initialValue: clip.livePhotoMuted ?? muteDefault)
        } else {
            self._selectedMotion = State(initialValue: .kenBurns)
            self._duration = State(initialValue: 4.0)
            self._livePhotoAsVideo = State(initialValue: tape.wrappedValue.livePhotosAsVideo)
            self._livePhotoMuted = State(initialValue: tape.wrappedValue.livePhotosMuted)
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Tokens.Spacing.xl) {
                    if isLivePhoto {
                        livePhotoSection
                    }
                    motionSection
                        .opacity(isLivePhoto && livePhotoAsVideo ? 0.4 : 1)
                        .disabled(isLivePhoto && livePhotoAsVideo)
                    durationSection
                        .opacity(isLivePhoto && livePhotoAsVideo ? 0.4 : 1)
                        .disabled(isLivePhoto && livePhotoAsVideo)
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

    private var livePhotoSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.l) {
            SectionHeader(title: "Live Photo")

            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "livephoto")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Tokens.Colors.primaryText)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                        Text("Play as video")
                            .font(Tokens.Typography.headline)
                            .foregroundColor(Tokens.Colors.primaryText)

                        Text("Use the Live Photo motion instead of a still image")
                            .font(Tokens.Typography.caption)
                            .foregroundColor(Tokens.Colors.secondaryText)
                    }

                    Spacer()

                    Toggle("", isOn: $livePhotoAsVideo)
                        .labelsHidden()
                        .tint(Color(red: 0, green: 0.533, blue: 1))
                        .onChange(of: livePhotoAsVideo) { _ in hasChanges = true }
                }

                Divider()
                    .padding(.vertical, Tokens.Spacing.s)

                HStack {
                    Image(systemName: livePhotoMuted ? "speaker.slash" : "speaker.wave.2")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(livePhotoAsVideo ? Tokens.Colors.primaryText : Tokens.Colors.secondaryText)
                        .frame(width: 24)

                    Text("Sound")
                        .font(Tokens.Typography.headline)
                        .foregroundColor(livePhotoAsVideo ? Tokens.Colors.primaryText : Tokens.Colors.secondaryText)

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { !livePhotoMuted },
                        set: {
                            livePhotoMuted = !$0
                            hasChanges = true
                        }
                    ))
                        .labelsHidden()
                        .tint(Color(red: 0, green: 0.533, blue: 1))
                        .disabled(!livePhotoAsVideo)
                }
                .opacity(livePhotoAsVideo ? 1 : 0.5)
            }
            .padding(.vertical, Tokens.Spacing.m)
            .padding(.horizontal, Tokens.Spacing.m)
            .background(Tokens.Colors.secondaryBackground)
            .cornerRadius(Tokens.Radius.card)
        }
    }

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
        if clip.isLivePhoto {
            let tapeDefault = tape.livePhotosAsVideo
            clip.livePhotoAsVideo = (livePhotoAsVideo == tapeDefault) ? nil : livePhotoAsVideo
            let muteDefault = tape.livePhotosMuted
            clip.livePhotoMuted = (livePhotoMuted == muteDefault) ? nil : livePhotoMuted
        }
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
