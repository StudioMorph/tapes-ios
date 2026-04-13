import SwiftUI

struct ShareModalView: View {
    let tape: Tape
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var entitlementManager: EntitlementManager

    @State private var showingShareFlow = false
    @State private var showingExport = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Tokens.Spacing.l) {
                    shareSection
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
    }

    // MARK: - Share With Others

    private var shareSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
            SectionHeader(title: "Share with Others")

            VStack(spacing: Tokens.Spacing.s) {
                shareOptionRow(
                    icon: "eye",
                    title: "View Only",
                    subtitle: "Recipients can watch and AirPlay but cannot contribute",
                    action: { showingShareFlow = true }
                )

                if entitlementManager.isTogether {
                    shareOptionRow(
                        icon: "person.2",
                        title: "Collaborative",
                        subtitle: "Recipients can add their own clips to the tape",
                        action: { showingShareFlow = true }
                    )
                } else {
                    shareOptionRow(
                        icon: "person.2",
                        title: "Collaborative",
                        subtitle: "Available on Together plan",
                        disabled: true,
                        action: {}
                    )
                }
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
        .environmentObject(EntitlementManager())
}
