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
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
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
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Tokens.Colors.primaryText)
                    .id(currentMode)
                    .transition(.opacity)
                    .frame(height: 28)
            }
            .offset(y: -20)

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
    @State private var token = AnimationToken()

    @State private var isJiggling = false
    @State private var fabIsDropTarget = false

    // Per-clip X positions (relative to card centre), set dynamically from GeometryReader
    @State private var clipAX: CGFloat = 0
    @State private var clipBX: CGFloat = 0
    @State private var clipCX: CGFloat = 0
    @State private var clipDX: CGFloat = 0
    @State private var clipCVisible = true

    // Floating clip
    @State private var floaterPos: CGSize = .zero
    @State private var floaterScale: CGFloat = 1.0
    @State private var floaterVisible = false

    // Finger
    @State private var fingerPos: CGSize = .zero
    @State private var fingerVisible = false
    @State private var fingerScale: CGFloat = 1.0

    @State private var statusText = "Hold any clip to rearrange"

    // Stored from geometry so animation can use them
    @State private var clipW: CGFloat = 0
    @State private var cardW: CGFloat = 0

    private let fabSize: CGFloat = Tokens.FAB.size
    private let thumbHeight: CGFloat = 80
    private let pad: CGFloat = Tokens.Spacing.s

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

                GeometryReader { geo in
                    let w = geo.size.width
                    let cw = (w - pad * 2) / 2
                    let cy = geo.size.height / 2

                    // Slot positions (centre X of each slot relative to card)
                    let slotL = pad + cw / 2             // left of FAB
                    let slotR = w - pad - cw / 2         // right of FAB
                    let slotLL = slotL - cw              // off-screen left
                    let slotRR = slotR + cw              // off-screen right

                    ZStack {
                        RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                            .fill(Tokens.Colors.secondaryBackground)

                        // Clips at explicit positions (z-index 0, under FAB)
                        clipView(0).position(x: clipAX, y: cy)
                        clipView(1).position(x: clipBX, y: cy)
                        clipView(2).position(x: clipCX, y: cy).opacity(clipCVisible ? 1 : 0)
                        clipView(3).position(x: clipDX, y: cy)

                        // Seam line (z-index 1)
                        Rectangle()
                            .fill(fabIsDropTarget ? Tokens.Colors.tertiaryBackground : Tokens.Colors.systemRed.opacity(0.9))
                            .frame(width: 2, height: thumbHeight)
                            .position(x: w / 2, y: cy)
                            .animation(.easeInOut(duration: 0.25), value: fabIsDropTarget)
                            .zIndex(1)

                        // FAB (z-index 2)
                        fabView
                            .position(x: w / 2, y: cy)
                            .zIndex(2)

                        // Floating clip (z-index 3)
                        if floaterVisible {
                            floaterView(cw: cw)
                                .position(x: w / 2, y: cy)
                                .zIndex(3)
                        }

                        // Finger (z-index 4)
                        Circle()
                            .fill(.white.opacity(0.3))
                            .frame(width: 44, height: 44)
                            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                            .scaleEffect(fingerScale)
                            .position(x: w / 2, y: cy)
                            .offset(fingerPos)
                            .opacity(fingerVisible ? 1 : 0)
                            .zIndex(4)
                    }
                    .onAppear {
                        cardW = w
                        clipW = cw
                        clipAX = slotLL
                        clipBX = slotL
                        clipCX = slotR
                        clipDX = slotRR
                    }
                }
                .frame(height: thumbHeight + pad * 2)
                .padding(.horizontal, Tokens.Spacing.l)

                Text(statusText)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Tokens.Colors.primaryText)
                    .animation(.easeInOut(duration: 0.2), value: statusText)
                    .frame(height: 28)
            }
            .offset(y: -20)

            Spacer()
        }
        .padding(.horizontal, Tokens.Spacing.s)
        .onAppear {
            token.cancel()
            token = AnimationToken()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                startAnimation(token: token)
            }
        }
        .onDisappear {
            token.cancel()
        }
    }

    // MARK: - Clip view

    private func clipView(_ index: Int) -> some View {
        let seed = Double(index) * 0.3
        let phase = Double(index) * 1.5
        return ZStack {
            RoundedRectangle(cornerRadius: Tokens.Radius.thumb, style: .continuous)
                .fill(Tokens.Colors.tertiaryBackground)
            Image(systemName: "photo")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Tokens.Colors.secondaryText)
        }
        .frame(width: clipW > 0 ? clipW - 2 : 100, height: thumbHeight)
        .modifier(JiggleModifier(isJiggling: isJiggling, seed: seed, phase: phase))
    }

    // MARK: - FAB

    private var fabView: some View {
        ZStack {
            Circle()
                .fill(fabIsDropTarget ? Tokens.Colors.tertiaryBackground : Tokens.Colors.systemRed)
                .frame(width: fabSize, height: fabSize)
                .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
                .animation(.easeInOut(duration: 0.25), value: fabIsDropTarget)

            if fabIsDropTarget {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Tokens.Colors.primaryText.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(width: 28, height: 28)
                    Image(systemName: "photo.stack")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Tokens.Colors.primaryText)
                }
                .transition(.opacity)
            } else {
                Image(systemName: "video.fill")
                    .font(.system(size: fabSize * 0.36, weight: .semibold))
                    .foregroundColor(.white)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Floater

    private func floaterView(cw: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Tokens.Radius.thumb, style: .continuous)
                .fill(Tokens.Colors.tertiaryBackground)
            Image(systemName: "photo")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Tokens.Colors.secondaryText)
        }
        .frame(width: cw, height: thumbHeight)
        .scaleEffect(floaterScale)
        .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
        .offset(floaterPos)
    }

    // MARK: - Animation

    private func startAnimation(token: AnimationToken) {
        guard clipW > 0 else { return }

        func after(_ delay: TimeInterval, _ block: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard !token.isCancelled else { return }
                block()
            }
        }

        let slotL = pad + clipW / 2
        let slotR = cardW - pad - clipW / 2
        let slotLL = slotL - clipW
        let slotRR = slotR + clipW
        let slotRRR = slotRR + clipW

        let clipCentreX = slotR - cardW / 2  // offset from card centre to clip C
        let liftY: CGFloat = -(thumbHeight * 0.8)
        var t: TimeInterval = 0.4

        // Reset positions
        clipAX = slotLL; clipBX = slotL; clipCX = slotR; clipDX = slotRR
        clipCVisible = true; floaterVisible = false; floaterScale = 1.0; floaterPos = .zero
        fabIsDropTarget = false; isJiggling = false
        fingerVisible = false; fingerScale = 1.0; fingerPos = .zero
        statusText = "Hold any clip to rearrange"

        // 1) Finger appears on clip C (right of FAB)
        after(t) {
            withAnimation(.easeInOut(duration: 0.2)) {
                fingerPos = CGSize(width: clipCentreX, height: 0)
                fingerVisible = true
            }
        }
        t += 0.5

        // 2) First hold → jiggle mode
        after(t) {
            withAnimation(.easeInOut(duration: 0.15)) { fingerScale = 0.8 }
        }
        t += 0.6
        after(t) {
            withAnimation(.easeInOut(duration: 0.3)) { isJiggling = true }
        }
        t += 1.3

        // 3) Release
        after(t) {
            withAnimation(.easeInOut(duration: 0.15)) { fingerScale = 1.0 }
        }
        t += 0.5

        // 4) Second hold → lift clip C
        after(t) {
            withAnimation(.easeInOut(duration: 0.15)) { fingerScale = 0.8 }
            statusText = "Hold and drag the clip out"
        }
        t += 0.4
        after(t) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                clipCVisible = false
                floaterVisible = true
                floaterPos = CGSize(width: clipCentreX, height: liftY)
                fingerPos = CGSize(width: clipCentreX, height: liftY)
                fabIsDropTarget = true
            }
        }
        t += 0.4

        // 5) D slides left to close gap (D → slotR)
        after(t) {
            withAnimation(.easeInOut(duration: 0.4)) { clipDX = slotR }
        }
        t += 1.3

        // 6) Release floater, finger lifts
        after(t) {
            withAnimation(.easeInOut(duration: 0.15)) { fingerScale = 1.0 }
        }
        t += 0.4

        // 7) Finger swipes → all 3 clips shift RIGHT one position
        after(t) {
            statusText = "Swipe to find the right spot"
            withAnimation(.easeInOut(duration: 0.2)) {
                fingerPos = CGSize(width: -60, height: 0)
            }
        }
        t += 0.3
        after(t) {
            withAnimation(.easeInOut(duration: 0.5)) {
                fingerPos = CGSize(width: 60, height: 0)
                clipAX = slotL
                clipBX = slotR
                clipDX = slotRR
            }
        }
        t += 1.3

        // 8) Finger grabs floater, drags to FAB
        after(t) {
            statusText = "Drop the clip in new position"
            withAnimation(.easeInOut(duration: 0.3)) {
                fingerPos = CGSize(width: clipCentreX, height: liftY)
            }
        }
        t += 0.4
        after(t) {
            withAnimation(.easeInOut(duration: 0.15)) { fingerScale = 0.8 }
        }
        t += 0.3

        // 9) Drag to FAB → scale 50%
        after(t) {
            withAnimation(.easeInOut(duration: 0.6)) {
                floaterPos = .zero
                fingerPos = .zero
                floaterScale = 0.5
            }
        }
        t += 0.7

        // 10) Drop → B and D shift right, floater placed at slotR
        // A stays slotL, B: slotR→slotRR, D: slotRR→slotRRR, floater→slotR
        after(t) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                clipBX = slotRR
                clipDX = slotRRR
                floaterVisible = false
                floaterScale = 1.0
                clipCVisible = true
                clipCX = slotR
                fabIsDropTarget = false
                fingerScale = 1.0
                fingerVisible = false
            }
        }
        t += 0.5

        // 11) Jiggle stops, pause, loop
        after(t) {
            withAnimation(.easeInOut(duration: 0.3)) { isJiggling = false }
        }
        t += 1.5

        after(t) {
            startAnimation(token: token)
        }
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
