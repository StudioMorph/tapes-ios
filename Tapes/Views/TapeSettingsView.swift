import SwiftUI

struct TapeSettingsView: View {
    @Binding var tape: Tape
    let onDismiss: () -> Void
    let onTapeDeleted: (() -> Void)?
    @EnvironmentObject var tapesStore: TapesStore
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var showingDeleteError = false

    init(
        tape: Binding<Tape>,
        onDismiss: @escaping () -> Void = {},
        onTapeDeleted: (() -> Void)? = nil
    ) {
        self._tape = tape
        self.onDismiss = onDismiss
        self.onTapeDeleted = onTapeDeleted
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Tokens.Spacing.xl) {
                    transitionSection
                        .accessibilitySortPriority(1)

                    livePhotosSection
                        .accessibilitySortPriority(2)

                    destructiveActionSection
                        .accessibilitySortPriority(3)
                }
                .padding(.horizontal, Tokens.Spacing.l)
                .padding(.vertical, Tokens.Spacing.l)
            }
            .background(Tokens.Colors.primaryBackground.ignoresSafeArea())
            .navigationTitle("Tape Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                    .foregroundColor(.blue)
                    .accessibilityLabel("Close settings")
                }
            }
        }
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
        VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
            SectionHeader(title: "Transitions")

            NavigationLink {
                TransitionPickerView(tape: $tape)
            } label: {
                HStack(spacing: Tokens.Spacing.m) {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Tokens.Colors.primaryText)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                        Text("Current transition")
                            .font(Tokens.Typography.caption)
                            .foregroundColor(Tokens.Colors.secondaryText)

                        Text(tape.transition.displayName)
                            .font(Tokens.Typography.headline)
                            .foregroundColor(Tokens.Colors.primaryText)
                    }

                    Spacer()

                    HStack(spacing: Tokens.Spacing.xs) {
                        Text("Edit")
                            .font(Tokens.Typography.body)
                            .foregroundColor(Tokens.Colors.secondaryText)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Tokens.Colors.secondaryText)
                    }
                }
                .padding(.vertical, Tokens.Spacing.m)
                .padding(.horizontal, Tokens.Spacing.m)
                .background(Tokens.Colors.secondaryBackground)
                .cornerRadius(Tokens.Radius.card)
            }
            .buttonStyle(.plain)
        }
    }
    
    private var livePhotosSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
            SectionHeader(title: "Live Photos")

            VStack(spacing: Tokens.Spacing.m) {
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

                        Text("Live Photos will play as short videos instead of still images")
                            .font(Tokens.Typography.caption)
                            .foregroundColor(Tokens.Colors.secondaryText)
                    }

                    Spacer()

                    Toggle("", isOn: $tape.livePhotosAsVideo)
                        .labelsHidden()
                        .tint(Color(red: 0, green: 0.533, blue: 1))
                }

                Divider()
                    .padding(.vertical, Tokens.Spacing.s)

                HStack {
                    Image(systemName: tape.livePhotosMuted ? "speaker.slash" : "speaker.wave.2")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(tape.livePhotosAsVideo ? Tokens.Colors.primaryText : Tokens.Colors.secondaryText)
                        .frame(width: 24)

                    Text("Sound")
                        .font(Tokens.Typography.headline)
                        .foregroundColor(tape.livePhotosAsVideo ? Tokens.Colors.primaryText : Tokens.Colors.secondaryText)

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { !tape.livePhotosMuted },
                        set: { tape.livePhotosMuted = !$0 }
                    ))
                        .labelsHidden()
                        .tint(Color(red: 0, green: 0.533, blue: 1))
                        .disabled(!tape.livePhotosAsVideo)
                }
                .opacity(tape.livePhotosAsVideo ? 1 : 0.5)
            }
                .padding(.vertical, Tokens.Spacing.m)
                .padding(.horizontal, Tokens.Spacing.m)
                .background(Tokens.Colors.secondaryBackground)
                .cornerRadius(Tokens.Radius.card)

                if hasLivePhotoOverrides {
                    Button {
                        resetLivePhotoDefaults()
                        provideHapticFeedback()
                    } label: {
                        Text("Reset all to defaults")
                            .font(Tokens.Typography.body)
                            .foregroundColor(.blue)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var hasLivePhotoOverrides: Bool {
        tape.livePhotosAsVideo != true ||
        tape.livePhotosMuted != true ||
        tape.clips.contains(where: { $0.isLivePhoto && ($0.livePhotoAsVideo != nil || $0.livePhotoMuted != nil) })
    }

    private func resetLivePhotoDefaults() {
        var updated = tape
        updated.livePhotosAsVideo = true
        updated.livePhotosMuted = true
        for i in updated.clips.indices where updated.clips[i].isLivePhoto {
            updated.clips[i].livePhotoAsVideo = nil
            updated.clips[i].livePhotoMuted = nil
        }
        tape = updated
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
    
    private func deleteTape() {
        isDeleting = true
        let tapeSnapshot = tape

        onDismiss()
        onTapeDeleted?()

        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif

        DispatchQueue.main.async {
            tapesStore.deleteTape(tapeSnapshot)
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
}
