import SwiftUI

struct ShareModalView: View {
    let tape: Tape
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var uploadCoordinator: ShareUploadCoordinator
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var tapesStore: TapesStore

    private var isCollaborativeShared: Bool {
        tape.shareInfo?.mode == "collaborative"
    }

    private var unsyncedClips: [Clip] {
        tape.clips.filter { !$0.isPlaceholder && !$0.isSynced }
    }

    private var hasContributions: Bool {
        !unsyncedClips.isEmpty
    }

    /// Disable the share section entirely for tapes received by the
    /// current user as view-only (they cannot re-share what they don't own).
    private var canOwnShare: Bool {
        tape.shareInfo == nil || tape.shareInfo?.mode == "collaborative"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Tokens.Spacing.l) {
                    if isCollaborativeShared {
                        contributeSection
                    }

                    if canOwnShare && !isCollaborativeShared {
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
        .onChange(of: uploadCoordinator.isUploading) { _, isUploading in
            // When the background upload starts, collapse the modal so the
            // global progress overlay (owned by the parent view) stays visible.
            if isUploading {
                dismiss()
            }
        }
    }

    // MARK: - Contribute

    private var contributeSection: some View {
        VStack(spacing: Tokens.Spacing.m) {
            Button {
                guard let api = authManager.apiClient else { return }
                uploadCoordinator.contributeClips(tape: tape, api: api) { syncedIds in
                    for clipId in syncedIds {
                        tapesStore.markClipSynced(clipId, inTape: tape.id)
                    }
                }
            } label: {
                HStack(spacing: Tokens.Spacing.s) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22, weight: .medium))
                    Text("Contribute Your Changes")
                        .font(.system(size: 17, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(hasContributions ? Tokens.Colors.systemBlue : Tokens.Colors.secondaryBackground)
                .foregroundStyle(hasContributions ? .white : Tokens.Colors.tertiaryText)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
            }
            .disabled(!hasContributions)

            Text("When you contribute, everyone collaborating on this tape gets your clips.")
                .font(Tokens.Typography.caption)
                .foregroundStyle(Tokens.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Tokens.Spacing.m)
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
