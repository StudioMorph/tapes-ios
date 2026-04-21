import SwiftUI

struct ShareModalView: View {
    let tape: Tape
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

                    exportSection
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

    // MARK: - Export

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
            SectionHeader(title: "Export Tape")

            shareOptionRow(
                icon: "square.and.arrow.down",
                title: "Export as Video",
                subtitle: "Save a single video to your Photos library",
                action: {
                    dismiss()
                    // TODO: Trigger export coordinator
                }
            )
        }
    }

    // MARK: - Option Row

    private func shareOptionRow(
        icon: String,
        title: String,
        subtitle: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Tokens.Spacing.m) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(disabled ? Tokens.Colors.tertiaryText : Tokens.Colors.primaryText)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(disabled ? Tokens.Colors.tertiaryText : Tokens.Colors.primaryText)

                    Text(subtitle)
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(Tokens.Colors.secondaryText)
                }

                Spacer()

                if disabled {
                    Text("Together")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Tokens.Colors.systemBlue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Tokens.Colors.systemBlue.opacity(0.15))
                        .clipShape(Capsule())
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Tokens.Colors.tertiaryText)
                }
            }
            .padding(Tokens.Spacing.m)
            .background(Tokens.Colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

#Preview {
    ShareModalView(tape: Tape.sampleTapes[1])
        .environmentObject(ShareUploadCoordinator())
}
