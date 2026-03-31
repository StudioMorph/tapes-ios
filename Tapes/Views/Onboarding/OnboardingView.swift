import SwiftUI

struct OnboardingView: View {
    @AppStorage("tapes_onboarding_completed") private var onboardingCompleted = false
    @State private var currentPage = 0
    @State private var dismissScale: CGFloat = 1.0
    @State private var dismissOpacity: Double = 1.0
    @State private var dismissOffset: CGSize = .zero

    var isReopen: Bool = false
    var onComplete: (() -> Void)? = nil

    private func completeOnboarding() {
        withAnimation(.easeIn(duration: 0.35)) {
            dismissScale = 0.15
            dismissOpacity = 0
            dismissOffset = CGSize(
                width: -UIScreen.main.bounds.width / 2 + 50,
                height: UIScreen.main.bounds.height / 2 - 80
            )
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            onboardingCompleted = true
            onComplete?()
        }
    }

    var body: some View {
        ZStack {
            Tokens.Colors.primaryBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    CameraCaptureTutorialPage()
                        .tag(0)

                    FabSwipeTutorialPage()
                        .tag(1)

                    JiggleReorderTutorialPage()
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .contentMargins(.bottom, -4, for: .scrollIndicators)

                Button {
                    if currentPage < 2 {
                        withAnimation { currentPage += 1 }
                    } else {
                        completeOnboarding()
                    }
                } label: {
                    Text(currentPage < 2 ? "Next" : (isReopen ? "Got it" : "Get Started"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, Tokens.Spacing.xl)

                Spacer()
                    .frame(height: Tokens.Spacing.m)

                Button {
                    completeOnboarding()
                } label: {
                    Text(isReopen ? "Dismiss" : "Skip")
                        .font(.body)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .opacity(currentPage < 2 ? 1 : 0)
                .disabled(currentPage >= 2)

                Spacer()
                    .frame(height: Tokens.Spacing.l)
            }
        }
        .scaleEffect(dismissScale)
        .opacity(dismissOpacity)
        .offset(dismissOffset)
    }
}

// MARK: - Tutorial Pages (text + animation)

private struct CameraCaptureTutorialPage: View {
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Tokens.Spacing.s) {
                Text("Build Tapes Through Time")
                    .font(.title.weight(.bold))
                    .foregroundStyle(Tokens.Colors.primaryText)
                    .multilineTextAlignment(.center)

                Text("Start now, continue tomorrow\nor next month")
                    .font(.body)
                    .foregroundStyle(Tokens.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, Tokens.Spacing.xl)

            Spacer()

            VStack(spacing: Tokens.Spacing.m) {
                Text("Add clips one after another and play them as one")
                    .font(.subheadline)
                    .foregroundStyle(Tokens.Colors.secondaryText)
                    .multilineTextAlignment(.center)

                CameraCaptureAnimation()

                Text("Tap the red button to capture")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Tokens.Colors.primaryText)
                    .frame(height: 28)
            }
            .offset(y: -20)

            Spacer()
        }
        .padding(.horizontal, Tokens.Spacing.s)
    }
}

private struct FabSwipeTutorialPage: View {
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Tokens.Spacing.s) {
                Text("The Red Button")
                    .font(.title.weight(.bold))
                    .foregroundStyle(Tokens.Colors.primaryText)
                    .multilineTextAlignment(.center)

                Text("Record between 2 clips,\nadd media or change the transition")
                    .font(.body)
                    .foregroundStyle(Tokens.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, Tokens.Spacing.xl)

            Spacer()

            VStack(spacing: Tokens.Spacing.m) {
                Text("Swipe over it to change its functionality")
                    .font(.subheadline)
                    .foregroundStyle(Tokens.Colors.secondaryText)
                    .multilineTextAlignment(.center)

                FabSwipeAnimation()

                Text("Capture new clips")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Tokens.Colors.primaryText)
                    .frame(height: 28)
            }
            .offset(y: -20)

            Spacer()
        }
        .padding(.horizontal, Tokens.Spacing.s)
    }
}

private struct JiggleReorderTutorialPage: View {
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Tokens.Spacing.s) {
                Text("Make it Jiggle")
                    .font(.title.weight(.bold))
                    .foregroundStyle(Tokens.Colors.primaryText)
                    .multilineTextAlignment(.center)

                Text("In jiggle mode you can rearrange,\nduplicate and delete clips")
                    .font(.body)
                    .foregroundStyle(Tokens.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, Tokens.Spacing.xl)

            Spacer()

            VStack(spacing: Tokens.Spacing.m) {
                Text("Tap and hold to get jiggling")
                    .font(.subheadline)
                    .foregroundStyle(Tokens.Colors.secondaryText)
                    .multilineTextAlignment(.center)

                JiggleReorderAnimation()

                Text("Hold any clip to rearrange")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Tokens.Colors.primaryText)
                    .frame(height: 28)
            }
            .offset(y: -20)

            Spacer()
        }
        .padding(.horizontal, Tokens.Spacing.s)
    }
}

#Preview {
    OnboardingView()
}
