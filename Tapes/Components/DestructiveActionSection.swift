import SwiftUI

struct DestructiveActionSection: View {
    let isDeleting: Bool
    let onDelete: () -> Void
    
    var body: some View {
        VStack(spacing: Tokens.Spacing.m) {
            Button(action: onDelete) {
                HStack(spacing: Tokens.Spacing.s) {
                    if isDeleting {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(.circular)
                            .tint(Tokens.Colors.systemRed)
                    } else {
                        Image(systemName: "trash")
                            .font(Tokens.Typography.headline)
                            .foregroundColor(Tokens.Colors.systemRed)
                    }
                    
                    Text("Delete Tape")
                        .font(Tokens.Typography.headline)
                        .foregroundColor(Tokens.Colors.systemRed)
                }
                .padding(.vertical, Tokens.Spacing.m)
                .frame(maxWidth: .infinity)
                .frame(minHeight: Tokens.HitTarget.minimum)
                .background(Tokens.Colors.secondaryBackground)
                .cornerRadius(Tokens.Radius.card)
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)
            .accessibilityLabel("Delete Tape")
            .accessibilityHint("Deletes the tape and its album. Photos and videos remain in your device's Library.")
            .accessibilityAddTraits(.isButton)
            
            VStack(spacing: 2) {
                Text("Also deletes the album from your device.")
                    .font(Tokens.Typography.caption)
                    .foregroundColor(Tokens.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                
                Text("All photos and videos will remain in your device's Library.")
                    .font(Tokens.Typography.caption)
                    .foregroundColor(Tokens.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

#Preview {
    VStack(spacing: Tokens.Spacing.l) {
        DestructiveActionSection(
            isDeleting: false,
            onDelete: {}
        )
        
        DestructiveActionSection(
            isDeleting: true,
            onDelete: {}
        )
    }
    .padding()
    .background(Tokens.Colors.primaryBackground)
}
