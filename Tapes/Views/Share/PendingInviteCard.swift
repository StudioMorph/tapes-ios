import SwiftUI

/// Placeholder card shown in the Shared/Collab tab for a tape that has been
/// shared with the user but not yet downloaded. Mirrors the width and corner
/// radius of `TapeCardView` so it sits naturally in the same list.
struct PendingInviteCard: View {
    let invite: PendingInvite
    let onLoad: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(invite.title)
                .font(Tokens.Typography.headline)
                .foregroundStyle(Tokens.Colors.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, Tokens.Spacing.m)
                .padding(.top, Tokens.Spacing.m)

            VStack(spacing: Tokens.Spacing.m) {
                ownerAttribution

                HStack(spacing: Tokens.Spacing.m) {
                    dismissButton
                    loadButton
                }
            }
            .padding(Tokens.Spacing.m)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.thumb, style: .continuous)
                    .fill(Tokens.Colors.tertiaryBackground.opacity(0.6))
            )
            .padding(.horizontal, Tokens.Spacing.m)
            .padding(.vertical, Tokens.Spacing.m)
        }
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                .fill(Tokens.Colors.secondaryBackground)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }

    // MARK: - Subviews

    private var ownerAttribution: some View {
        HStack(spacing: 4) {
            Text(invite.ownerName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Tokens.Colors.primaryText)

            Text("shared this tape with you")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Tokens.Colors.secondaryText)
        }
    }

    private var dismissButton: some View {
        Button(role: .destructive) {
            onDismiss()
        } label: {
            Text("Dismiss")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .buttonBorderShape(.capsule)
    }

    private var loadButton: some View {
        Button {
            onLoad()
        } label: {
            Label("Load tape", systemImage: "arrow.down.circle")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .buttonBorderShape(.capsule)
        .tint(Tokens.Colors.systemBlue)
    }
}

#Preview {
    PendingInviteCard(
        invite: PendingInvite(
            tapeId: "abc-123",
            title: "Summer Holidays 2025 - Portugal",
            ownerName: "Isabel",
            shareId: "xyz789",
            mode: "view_only",
            receivedAt: Date()
        ),
        onLoad: {},
        onDismiss: {}
    )
    .padding()
    .background(Tokens.Colors.primaryBackground)
}
