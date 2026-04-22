import SwiftUI

struct ShareModalView: View {
    @Binding var tape: Tape
    @Binding var pendingMergeTape: Tape?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var uploadCoordinator: ShareUploadCoordinator

    /// The share section is visible for:
    /// - My Tapes (not shared, not collab) — view-only sharing
    /// - Owner's collab tape (isCollabTape) — collaborative sharing
    /// Hidden for all received tapes (both view-only and collaborative).
    private var canOwnShare: Bool {
        if tape.isCollabTape { return true }
        if tape.isShared { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Tokens.Spacing.l) {
                    if canOwnShare {
                        ShareLinkSection(tape: tape)
                    }

                    mergeAndSaveSection
                }
                .padding(.horizontal, Tokens.Spacing.l)
                .padding(.top, Tokens.Spacing.l)
                .padding(.bottom, Tokens.Spacing.xxl)
            }
            .background(Tokens.Colors.primaryBackground.ignoresSafeArea())
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Tokens.Colors.primaryText)
                    }
                }
            }
        }
        .overlay {
            if uploadCoordinator.showProgressDialog {
                ShareUploadProgressDialog(coordinator: uploadCoordinator) {
                    dismiss()
                }
            }
            if uploadCoordinator.showCompletionDialog {
                ShareUploadCompletionDialog(coordinator: uploadCoordinator)
            }
            if uploadCoordinator.uploadError != nil {
                ShareUploadErrorAlert(coordinator: uploadCoordinator)
            }
        }
    }

    // MARK: - Merge and Save

    private var mergeAndSaveSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
            SectionHeader(title: "Merge and Save")

            if tape.duration > Tokens.Timing.maxTapeDuration || tape.clips.count > Tokens.Timing.maxTapeClipCount {
                HStack(spacing: Tokens.Spacing.m) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Tokens.Colors.secondaryText)

                    Text("Merge and export are only available for tapes under \(Int(Tokens.Timing.maxTapeDuration / 60)) minutes or with fewer than \(Tokens.Timing.maxTapeClipCount) clips.")
                        .font(Tokens.Typography.caption)
                        .foregroundColor(Tokens.Colors.secondaryText)
                }
                .padding(.vertical, Tokens.Spacing.m)
                .padding(.horizontal, Tokens.Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Tokens.Colors.secondaryBackground)
                .cornerRadius(Tokens.Radius.card)
            } else {
                VStack(spacing: Tokens.Spacing.s) {
                    ForEach(ExportOrientation.allCases) { orientation in
                        exportOrientationCell(orientation)
                    }
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
                        pendingMergeTape = tape
                        dismiss()
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

    // MARK: - Helpers

    private func provideHapticFeedback() {
        #if os(iOS)
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        #endif
    }
}

#Preview {
    ShareModalView(tape: .constant(Tape.sampleTapes[1]), pendingMergeTape: .constant(nil))
        .environmentObject(ShareUploadCoordinator())
}
