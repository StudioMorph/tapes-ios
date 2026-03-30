import SwiftUI

struct OnboardingView: View {
    @AppStorage("tapes_onboarding_completed") private var onboardingCompleted = false
    @State private var currentPage = 0

    var body: some View {
        ZStack {
            Tokens.Colors.primaryBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    FabSwipeTutorial()
                        .tag(0)

                    JiggleReorderTutorial()
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Button {
                    if currentPage == 0 {
                        withAnimation { currentPage = 1 }
                    } else {
                        onboardingCompleted = true
                    }
                } label: {
                    Text(currentPage == 0 ? "Next" : "Get Started")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(Tokens.Colors.systemRed)
                .padding(.horizontal, Tokens.Spacing.xl)
                .padding(.bottom, Tokens.Spacing.xl)
            }
        }
    }
}

private class AnimationToken {
    var isCancelled = false
    func cancel() { isCancelled = true }
}

// MARK: - FAB Swipe Tutorial

private struct FabSwipeTutorial: View {
    @State private var animationPhase = 0
    @State private var fingerX: CGFloat = 0
    @State private var currentMode: FABMode = .camera
    @State private var token = AnimationToken()

    private let fabSize: CGFloat = Tokens.FAB.size
    private let thumbHeight: CGFloat = 80
    private let modes: [(FABMode, String)] = [
        (.camera, "Capture new clips"),
        (.gallery, "Add from your library"),
        (.transition, "Change seam transitions")
    ]

    var body: some View {
        VStack(spacing: Tokens.Spacing.xl) {
            Spacer()

            Text("Swipe to switch modes")
                .font(.title.weight(.bold))
                .foregroundStyle(Tokens.Colors.primaryText)
                .multilineTextAlignment(.center)

            Text("Your FAB does it all. Just swipe.")
                .font(.body)
                .foregroundStyle(Tokens.Colors.secondaryText)
                .multilineTextAlignment(.center)

            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                    .fill(Tokens.Colors.secondaryBackground)

                HStack(spacing: 0) {
                    clipPlaceholder
                        .frame(maxWidth: .infinity)
                    clipPlaceholder
                        .frame(maxWidth: .infinity)
                }
                .padding(Tokens.Spacing.s)

                Rectangle()
                    .fill(Tokens.Colors.systemRed.opacity(0.9))
                    .frame(width: 2, height: thumbHeight)

                Circle()
                    .fill(Tokens.Colors.systemRed)
                    .frame(width: fabSize, height: fabSize)
                    .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)

                Image(systemName: currentMode.icon)
                    .font(.system(size: fabSize * 0.36, weight: .semibold))
                    .foregroundColor(.white)
                    .id(currentMode)
                    .transition(.opacity)

                Circle()
                    .fill(.white.opacity(0.3))
                    .frame(width: 44, height: 44)
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                    .offset(x: fingerX)
                    .opacity(animationPhase > 0 ? 1 : 0)
            }
            .frame(height: thumbHeight + Tokens.Spacing.s * 2)
            .padding(.horizontal, Tokens.Spacing.l)

            Text(modes.first { $0.0 == currentMode }?.1 ?? "")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Tokens.Colors.primaryText)
                .id(currentMode)
                .transition(.opacity)
                .frame(height: 20)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, Tokens.Spacing.s)
        .onAppear {
            token.cancel()
            token = AnimationToken()
            resetState()
            startAnimation(token: token)
        }
        .onDisappear {
            token.cancel()
            resetState()
        }
    }

    private func resetState() {
        animationPhase = 0
        fingerX = Tokens.FAB.size / 2
        currentMode = .camera
    }

    private var clipPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Tokens.Radius.thumb, style: .continuous)
                .fill(Tokens.Colors.tertiaryBackground)

            Image(systemName: "photo")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Tokens.Colors.secondaryText)
        }
        .frame(height: thumbHeight)
    }

    private let swipeDuration: TimeInterval = 0.4
    private let pauseDuration: TimeInterval = 1.2

    private func startAnimation(token: AnimationToken) {
        let sequence: [FABMode] = [.gallery, .transition, .camera]
        var t: TimeInterval = 0.8

        let restX = fabSize / 2

        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            guard !token.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                animationPhase = 1
            }
        }
        t += 0.3

        func scheduleSwipe(to mode: FABMode, at time: TimeInterval, then next: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + time) {
                guard !token.isCancelled else { return }
                withAnimation(.easeInOut(duration: swipeDuration)) {
                    fingerX = -restX
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + swipeDuration / 2) {
                    guard !token.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.15)) {
                        currentMode = mode
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + swipeDuration + 0.1) {
                    guard !token.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        fingerX = restX
                    }
                    next()
                }
            }
        }

        for mode in sequence {
            let capturedT = t
            let isLast = mode == sequence.last
            scheduleSwipe(to: mode, at: capturedT) {
                if isLast {
                    DispatchQueue.main.asyncAfter(deadline: .now() + pauseDuration) {
                        guard !token.isCancelled else { return }
                        startAnimation(token: token)
                    }
                }
            }
            t += swipeDuration + 0.1 + 0.2 + pauseDuration
        }
    }
}

// MARK: - Jiggle & Reorder Tutorial

private struct JiggleReorderTutorial: View {
    @State private var isJiggling = false
    @State private var liftedIndex: Int? = nil
    @State private var liftedOffset: CGSize = .zero
    @State private var statusText = "Hold any clip to rearrange"
    @State private var clipOrder = [0, 1, 2, 3]
    @State private var token = AnimationToken()

    private let clipSize = CGSize(width: 72, height: 96)
    private let clipSpacing: CGFloat = 8
    private let clipColors: [Color] = [
        .blue.opacity(0.6), .green.opacity(0.6),
        .orange.opacity(0.6), .purple.opacity(0.6)
    ]

    var body: some View {
        VStack(spacing: Tokens.Spacing.xl) {
            Spacer()

            Text("Rearrange your timeline")
                .font(.title.weight(.bold))
                .foregroundStyle(Tokens.Colors.primaryText)
                .multilineTextAlignment(.center)

            Text("Hold, drag, and drop to tell your story your way.")
                .font(.body)
                .foregroundStyle(Tokens.Colors.secondaryText)
                .multilineTextAlignment(.center)

            Spacer()

            ZStack {
                HStack(spacing: clipSpacing) {
                    ForEach(Array(clipOrder.enumerated()), id: \.element) { index, colorIdx in
                        JiggleClip(
                            colorIdx: colorIdx,
                            color: clipColors[colorIdx],
                            size: clipSize,
                            isJiggling: isJiggling,
                            isLifted: liftedIndex == index,
                            liftedOffset: liftedIndex == index ? liftedOffset : .zero
                        )
                    }
                }

                if liftedIndex != nil {
                    Circle()
                        .fill(.white.opacity(0.3))
                        .frame(width: 44, height: 44)
                        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                        .offset(x: liftedOffset.width, y: liftedOffset.height + clipSize.height * 0.3)
                }
            }

            Text(statusText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Tokens.Colors.primaryText)
                .animation(.easeInOut(duration: 0.2), value: statusText)
                .frame(height: 20)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, Tokens.Spacing.l)
        .onAppear {
            token.cancel()
            token = AnimationToken()
            resetState()
            startAnimation(token: token)
        }
        .onDisappear {
            token.cancel()
            resetState()
        }
    }

    private func resetState() {
        isJiggling = false
        liftedIndex = nil
        liftedOffset = .zero
        statusText = "Hold any clip to rearrange"
        clipOrder = [0, 1, 2, 3]
    }

    private func startAnimation(token: AnimationToken) {
        let totalCycle: TimeInterval = 5.5

        func runCycle() {
            guard !token.isCancelled else { return }
            resetState()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                guard !token.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    isJiggling = true
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard !token.isCancelled else { return }
                statusText = "Drag to a new position"
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    liftedIndex = 1
                    liftedOffset = CGSize(width: 0, height: -20)
                }
            }

            let dragStep = (clipSize.width + clipSpacing) * 2
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                guard !token.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.8)) {
                    liftedOffset = CGSize(width: dragStep, height: -20)
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                guard !token.isCancelled else { return }
                statusText = "Drop to reorder your story"
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    liftedOffset = .zero
                    liftedIndex = nil
                    clipOrder = [0, 2, 3, 1]
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + totalCycle) {
                guard !token.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    isJiggling = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    guard !token.isCancelled else { return }
                    runCycle()
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard !token.isCancelled else { return }
            runCycle()
        }
    }
}

// MARK: - Jiggle Clip

private struct JiggleClip: View {
    let colorIdx: Int
    let color: Color
    let size: CGSize
    let isJiggling: Bool
    let isLifted: Bool
    let liftedOffset: CGSize

    var body: some View {
        let seed = Double(colorIdx) * 0.3
        let phase = Double(colorIdx) * 1.5

        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color)

            Image(systemName: "photo")
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.5))

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text("\(colorIdx + 1)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(4)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(isLifted ? 1.1 : (isJiggling ? 0.92 : 1.0))
        .shadow(color: .black.opacity(isLifted ? 0.3 : 0), radius: 12, x: 0, y: 6)
        .offset(liftedOffset)
        .opacity(isLifted ? 0.9 : 1.0)
        .modifier(JiggleModifier(isJiggling: isJiggling && !isLifted, seed: seed, phase: phase))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isLifted)
        .animation(.easeInOut(duration: 0.3), value: isJiggling)
    }
}

private struct JiggleModifier: ViewModifier, Animatable {
    let isJiggling: Bool
    let seed: Double
    let phase: Double

    func body(content: Content) -> some View {
        if isJiggling {
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let rot = (0.8 + seed * 0.5) * sin(time * (18.0 + seed * 7.0) + phase)
                let offX = (0.25 + seed * 0.25) * sin(time * (16.0 + seed * 6.0) + phase + 1.2)
                let offY = (0.35 + seed * 0.35) * cos(time * (17.0 + seed * 6.5) + phase + 2.4)

                content
                    .rotationEffect(.degrees(rot))
                    .offset(x: offX, y: offY)
            }
        } else {
            content
        }
    }
}

#Preview {
    OnboardingView()
}
