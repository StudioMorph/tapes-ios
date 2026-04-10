import SwiftUI

struct TransitionOption: View {
    let transition: TransitionType
    let isSelected: Bool
    var duration: Binding<Double>?
    let onSelect: () -> Void
    
    private var showSlider: Bool {
        isSelected && transition != .none && duration != nil
    }
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                        Text(transition.displayName)
                            .font(Tokens.Typography.headline)
                            .foregroundColor(Tokens.Colors.primaryText)
                        
                        Text(transitionDescription)
                            .font(Tokens.Typography.caption)
                            .foregroundColor(Tokens.Colors.secondaryText)
                    }
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                            .font(Tokens.Typography.title)
                    }
                }

                if showSlider, let duration {
                    TransitionDurationSlider(duration: duration)
                        .padding(.top, Tokens.Spacing.m)
                }
            }
            .padding(.vertical, Tokens.Spacing.m)
            .padding(.horizontal, Tokens.Spacing.m)
            .background(Tokens.Colors.secondaryBackground)
            .cornerRadius(Tokens.Radius.card)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
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
    .background(Tokens.Colors.primaryBackground)
}
