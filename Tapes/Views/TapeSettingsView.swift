import SwiftUI

struct TapeSettingsView: View {
    @Binding var tape: Tape
    let onDismiss: () -> Void
    let onTapeDeleted: (() -> Void)?
    let onMergeAndSave: ((Tape) -> Void)?
    @EnvironmentObject var tapesStore: TapesStore
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var showingDeleteError = false

    init(
        tape: Binding<Tape>,
        onDismiss: @escaping () -> Void = {},
        onTapeDeleted: (() -> Void)? = nil,
        onMergeAndSave: ((Tape) -> Void)? = nil
    ) {
        self._tape = tape
        self.onDismiss = onDismiss
        self.onTapeDeleted = onTapeDeleted
        self.onMergeAndSave = onMergeAndSave
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Tokens.Spacing.xl) {
                    transitionSection
                        .accessibilitySortPriority(1)

                    mergeAndSaveSection
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
        VStack(alignment: .leading, spacing: Tokens.Spacing.l) {
            SectionHeader(title: "Choose default transition")
            
            VStack(spacing: Tokens.Spacing.s) {
                ForEach(TransitionType.allCases, id: \.self) { transition in
                    TransitionOption(
                        transition: transition,
                        isSelected: tape.transition == transition,
                        duration: $tape.transitionDuration,
                        onSelect: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                tape.transition = transition
                            }
                            provideHapticFeedback()
                        }
                    )
                }
            }
        }
    }
    
    private var mergeAndSaveSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.l) {
            SectionHeader(title: "Merge and Save")

            VStack(spacing: Tokens.Spacing.s) {
                ForEach(ExportOrientation.allCases) { orientation in
                    exportOrientationCell(orientation)
                }
            }
        }
    }

    private func exportOrientationCell(_ orientation: ExportOrientation) -> some View {
        let isSelected = tape.exportOrientation == orientation

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                tape.exportOrientation = orientation
            }
            provideHapticFeedback()
        } label: {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                        HStack(spacing: Tokens.Spacing.s) {
                            Image(systemName: orientation.icon)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(Tokens.Colors.primaryText)
                                .frame(width: 24)

                            Text(orientation.displayName)
                                .font(Tokens.Typography.headline)
                                .foregroundColor(Tokens.Colors.primaryText)
                        }

                        Text(orientation.description)
                            .font(Tokens.Typography.caption)
                            .foregroundColor(Tokens.Colors.secondaryText)
                            .padding(.leading, 24 + Tokens.Spacing.s)
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                            .font(Tokens.Typography.title)
                    }
                }

                if isSelected {
                    Toggle(isOn: $tape.blurExportBackground) {
                        Text("Background Blur")
                            .font(.subheadline)
                            .foregroundColor(Tokens.Colors.primaryText)
                    }
                    .tint(Color(red: 0, green: 0.533, blue: 1))
                    .padding(.top, Tokens.Spacing.l)

                    Button {
                        let tapeSnapshot = tape
                        onDismiss()
                        onMergeAndSave?(tapeSnapshot)
                    } label: {
                        Text("Save and Merge")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .buttonBorderShape(.capsule)
                    .tint(Color(red: 0, green: 0.533, blue: 1))
                    .padding(.top, Tokens.Spacing.l)
                }
            }
            .padding(.vertical, Tokens.Spacing.m)
            .padding(.horizontal, Tokens.Spacing.m)
            .background(Tokens.Colors.secondaryBackground)
            .cornerRadius(Tokens.Radius.card)
        }
        .buttonStyle(.plain)
        .frame(minHeight: Tokens.HitTarget.minimum)
        .accessibilityLabel(orientation.displayName)
        .accessibilityHint(orientation.description)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
        
        Task {
            await MainActor.run {
                tapesStore.deleteTape(tape)
            }
            
            #if os(iOS)
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.notificationOccurred(.success)
            #endif
            
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
}
