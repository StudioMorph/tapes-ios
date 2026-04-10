import SwiftUI

struct TransitionPickerView: View {
    @Binding var tape: Tape

    var body: some View {
        ScrollView {
            VStack(spacing: Tokens.Spacing.xl) {
                VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
                    SectionHeader(title: "Choose default transition")

                    VStack(spacing: Tokens.Spacing.s) {
                        ForEach(TransitionType.allCases, id: \.self) { transition in
                            TransitionOption(
                                transition: transition,
                                isSelected: tape.transition == transition,
                                duration: $tape.transitionDuration,
                                onSelect: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        tape.transition = transition
                                    }
                                    provideHapticFeedback()
                                }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, Tokens.Spacing.l)
            .padding(.vertical, Tokens.Spacing.l)
        }
        .background(Tokens.Colors.primaryBackground.ignoresSafeArea())
        .navigationTitle("Transitions")
        .navigationBarTitleDisplayMode(.large)
    }

    private func provideHapticFeedback() {
        #if os(iOS)
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        #endif
    }
}

#Preview {
    NavigationView {
        TransitionPickerView(tape: .constant(Tape.sampleTapes[0]))
    }
}
