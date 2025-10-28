import SwiftUI

struct TransitionDurationSlider: View {
    @Binding var duration: Double
    @Binding var hasChanges: Bool
    
    var body: some View {
        VStack(spacing: Tokens.Spacing.s) {
            HStack {
                Text("0.1s")
                    .font(Tokens.Typography.caption)
                    .foregroundColor(Tokens.Colors.muted)
                
                Slider(value: $duration, in: 0.1...2.0, step: 0.1)
                    .accentColor(Tokens.Colors.red)
                    .onChange(of: duration) { _ in
                        hasChanges = true
                    }
                
                Text("2.0s")
                    .font(Tokens.Typography.caption)
                    .foregroundColor(Tokens.Colors.muted)
            }
            
            Text("\(String(format: "%.1f", duration))s")
                .font(Tokens.Typography.headline)
                .foregroundColor(Tokens.Colors.onSurface)
        }
        .padding(Tokens.Spacing.l)
        .background(Tokens.Colors.elevated)
        .cornerRadius(Tokens.Radius.card)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Transition duration")
        .accessibilityValue("\(String(format: "%.1f", duration)) seconds")
        .accessibilityAdjustableAction { direction in
            let step: Double = 0.1
            switch direction {
            case .increment:
                duration = min(2.0, duration + step)
            case .decrement:
                duration = max(0.1, duration - step)
            @unknown default:
                break
            }
        }
    }
}

#Preview {
    TransitionDurationSlider(
        duration: .constant(0.5),
        hasChanges: .constant(false)
    )
    .padding()
    .background(Tokens.Colors.bg)
}
