import SwiftUI

struct TransitionOption: View {
    let transition: TransitionType
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                    Text(transition.displayName)
                        .font(Tokens.Typography.headline)
                        .foregroundColor(Tokens.Colors.onSurface)
                    
                    Text(transitionDescription)
                        .font(Tokens.Typography.caption)
                        .foregroundColor(Tokens.Colors.muted)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Tokens.Colors.red)
                        .font(Tokens.Typography.title)
                }
            }
            .padding(.vertical, Tokens.Spacing.s)
            .padding(.horizontal, Tokens.Spacing.m)
            .background(Tokens.Colors.elevated)
            .cornerRadius(Tokens.Radius.card)
        }
        .buttonStyle(.plain)
        .frame(minHeight: Tokens.HitTarget.minimum)
        .accessibilityLabel(transition.displayName)
        .accessibilityHint(transitionDescription)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
    
    private var transitionDescription: String {
        switch transition {
        case .none:
            return "Default for speed and clarity"
        case .crossfade:
            return "The industry-standard, smooth and safe choice"
        case .slideLR:
            return "Horizontal slide between clips"
        case .slideRL:
            return "Horizontal slide between clips"
        case .randomise:
            return "Randomly selects from available transitions"
        }
    }
}

#Preview {
    VStack(spacing: Tokens.Spacing.m) {
        TransitionOption(
            transition: .none,
            isSelected: true,
            onSelect: {}
        )
        
        TransitionOption(
            transition: .crossfade,
            isSelected: false,
            onSelect: {}
        )
    }
    .padding()
    .background(Tokens.Colors.bg)
}
