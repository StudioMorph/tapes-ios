import SwiftUI

struct ShareModalView: View {
    let tape: Tape
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var uploadCoordinator: ShareUploadCoordinator
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var tapesStore: TapesStore

    @State private var showingShareFlow = false
    @State private var showingExport = false

    private var isCollaborativeShared: Bool {
        tape.shareInfo?.mode == "collaborative"
    }

    private var unsyncedClips: [Clip] {
        tape.clips.filter { !$0.isPlaceholder && !$0.isSynced }
    }

    private var hasContributions: Bool {
        !unsyncedClips.isEmpty
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Tokens.Spacing.l) {
                    if isCollaborativeShared {
                        contributeSection
                    }
                    if !isCollaborativeShared {
                        shareSection
                    }
                    exportSection
                    saveToDeviceSection
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
        .sheet(isPresented: $showingShareFlow) {
            ShareFlowView(tape: tape)
        }
        .onChange(of: uploadCoordinator.isUploading) { _, isUploading in
            if isUploading {
                showingShareFlow = false
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

    // MARK: - Share With Others

    private var shareSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
            shareOptionRow(
                icon: "square.and.arrow.up",
                title: "Share This Tape",
                subtitle: "Allow your family and friends to rebuild this tape on their devices, so they can play and edit it",
                action: { showingShareFlow = true }
            )
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

    // MARK: - Save to Device

    private var saveToDeviceSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
            SectionHeader(title: "Save to Device")

            shareOptionRow(
                icon: "photo.on.rectangle.angled",
                title: "Save Clips to Album",
                subtitle: "Save all clips individually to a Photos album",
                action: {
                    dismiss()
                    // TODO: Trigger save to device
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
