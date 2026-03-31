import SwiftUI

// MARK: - Animation Token

class AnimationToken {
    var isCancelled = false
    func cancel() { isCancelled = true }
}

// MARK: - Camera Capture Animation

struct CameraCaptureAnimation: View {
    @State private var token = AnimationToken()

    @State private var clipAX: CGFloat = 0
    @State private var clipBX: CGFloat = 0
    @State private var newClipX: CGFloat = 0
    @State private var newClipVisible = false
    @State private var newClipScale: CGFloat = 0.1

    @State private var viewfinderVisible = false
    @State private var viewfinderScale: CGFloat = 0.1
    @State private var viewfinderOpacity: Double = 0
    @State private var recording = false

    @State private var fingerPos: CGSize = .zero
    @State private var fingerVisible = false
    @State private var fingerScale: CGFloat = 1.0

    @State private var clipW: CGFloat = 0
    @State private var cardW: CGFloat = 0

    private let fabSize: CGFloat = Tokens.FAB.size
    private let thumbHeight: CGFloat = 80
    private let pad: CGFloat = Tokens.Spacing.s

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let cw = (w - pad * 2) / 2
            let cy = geo.size.height / 2

            let slotL = pad + cw / 2
            let slotR = w - pad - cw / 2
            let slotLL = slotL - cw

            ZStack {
                RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                    .fill(Tokens.Colors.secondaryBackground)

                clipTile(width: cw)
                    .position(x: clipAX, y: cy)

                clipTile(width: cw)
                    .position(x: clipBX, y: cy)

                if newClipVisible {
                    clipTile(width: cw)
                        .scaleEffect(newClipScale)
                        .position(x: newClipX, y: cy)
                }

                plusPlaceholder(width: cw)
                    .position(x: slotR, y: cy)

                Rectangle()
                    .fill(Tokens.Colors.systemRed.opacity(0.9))
                    .frame(width: 2, height: thumbHeight)
                    .position(x: w / 2, y: cy)
                    .zIndex(1)

                cameraFAB
                    .position(x: w / 2, y: cy)
                    .zIndex(2)

                if viewfinderVisible {
                    viewfinderView
                        .scaleEffect(viewfinderScale)
                        .opacity(viewfinderOpacity)
                        .position(x: w / 2, y: cy - thumbHeight / 2 - 70)
                        .zIndex(3)
                }

                fingerCircle
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
                newClipX = slotL
            }
        }
        .frame(height: thumbHeight + pad * 2)
        .padding(.horizontal, Tokens.Spacing.l)
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

    private func startAnimation(token: AnimationToken) {
        guard clipW > 0 else { return }

        func after(_ delay: TimeInterval, _ block: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard !token.isCancelled else { return }
                block()
            }
        }

        let slotL = pad + clipW / 2
        let slotLL = slotL - clipW
        let slotLLL = slotLL - clipW
        let liftY: CGFloat = -(thumbHeight / 2 + 60)
        var t: TimeInterval = 0.3

        clipAX = slotLL; clipBX = slotL
        newClipVisible = false; newClipScale = 0.1; newClipX = slotL
        viewfinderVisible = false; viewfinderScale = 0.1; viewfinderOpacity = 0
        recording = false
        fingerVisible = false; fingerScale = 1.0; fingerPos = .zero

        after(t) {
            withAnimation(.easeInOut(duration: 0.25)) { fingerVisible = true }
        }
        t += 0.5

        after(t) {
            withAnimation(.easeInOut(duration: 0.12)) { fingerScale = 0.8 }
        }
        t += 0.15
        after(t) {
            withAnimation(.easeInOut(duration: 0.12)) { fingerScale = 1.0 }
        }
        t += 0.2

        after(t) {
            viewfinderVisible = true
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                viewfinderScale = 1.0
                viewfinderOpacity = 1.0
            }
        }
        t += 0.8

        after(t) {
            withAnimation(.easeInOut(duration: 0.25)) {
                fingerPos = CGSize(width: 0, height: liftY + 10)
            }
        }
        t += 0.35

        after(t) {
            withAnimation(.easeInOut(duration: 0.12)) { fingerScale = 0.8 }
            withAnimation(.easeInOut(duration: 0.15)) { recording = true }
        }
        t += 0.2
        after(t) {
            withAnimation(.easeInOut(duration: 0.12)) { fingerScale = 1.0 }
        }
        t += 0.8

        after(t) {
            withAnimation(.easeInOut(duration: 0.15)) {
                fingerVisible = false
                recording = false
            }
        }
        t += 0.2

        after(t) {
            withAnimation(.easeInOut(duration: 0.35)) {
                clipAX = slotLLL
                clipBX = slotLL
            }
        }
        t += 0.4

        after(t) {
            newClipX = slotL
            newClipVisible = true
            newClipScale = 0.1
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                viewfinderScale = 0.1
                viewfinderOpacity = 0
                newClipScale = 1.0
            }
        }
        t += 0.4
        after(t) { viewfinderVisible = false }
        t += 1.0

        after(t) { startAnimation(token: token) }
    }

    // MARK: - Sub-views

    private func clipTile(width: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Tokens.Radius.thumb, style: .continuous)
                .fill(Tokens.Colors.tertiaryBackground)
            Image(systemName: "play.rectangle")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Tokens.Colors.secondaryText)
        }
        .frame(width: max(width - 2, 0), height: thumbHeight)
    }

    private func plusPlaceholder(width: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Tokens.Radius.thumb, style: .continuous)
                .fill(Tokens.Colors.tertiaryBackground)
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Tokens.Colors.secondaryText)
        }
        .frame(width: max(width - 2, 0), height: thumbHeight)
    }

    private var cameraFAB: some View {
        ZStack {
            Circle()
                .fill(Tokens.Colors.systemRed)
                .frame(width: fabSize, height: fabSize)
                .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
            Image(systemName: "video.fill")
                .font(.system(size: fabSize * 0.36, weight: .semibold))
                .foregroundColor(.white)
        }
    }

    private var viewfinderView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Tokens.Colors.primaryBackground)
                .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 8)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Tokens.Colors.primaryText.opacity(0.15), lineWidth: 1)

            VStack(spacing: 12) {
                ViewfinderCorners()
                    .stroke(Tokens.Colors.primaryText.opacity(0.6), lineWidth: 2)
                    .frame(width: 60, height: 44)

                Circle()
                    .fill(recording ? Color.red.opacity(0.8) : Tokens.Colors.systemRed)
                    .frame(width: 28, height: 28)
                    .scaleEffect(recording ? 0.7 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: recording)
                    .overlay(
                        Circle().strokeBorder(.white.opacity(0.6), lineWidth: 2)
                    )
            }
            .padding(.vertical, 12)

            VStack {
                Spacer()
                Triangle()
                    .fill(Tokens.Colors.primaryBackground)
                    .frame(width: 16, height: 10)
                    .offset(y: 9)
            }
        }
        .frame(width: 110, height: 110)
    }
}

// MARK: - FAB Swipe Animation

struct FabSwipeAnimation: View {
    @State private var animationPhase = 0
    @State private var fingerX: CGFloat = 0
    @State private var currentMode: FABMode = .camera
    @State private var token = AnimationToken()

    private let fabSize: CGFloat = Tokens.FAB.size
    private let thumbHeight: CGFloat = 80
    private let swipeDuration: TimeInterval = 0.4
    private let pauseDuration: TimeInterval = 1.2

    var body: some View {
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

            fingerCircle
                .offset(x: fingerX)
                .opacity(animationPhase > 0 ? 1 : 0)
        }
        .frame(height: thumbHeight + Tokens.Spacing.s * 2)
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
        animationPhase = 0
        fingerX = Tokens.FAB.size / 2
        currentMode = .camera
    }

    private var clipPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Tokens.Radius.thumb, style: .continuous)
                .fill(Tokens.Colors.tertiaryBackground)
            Image(systemName: "play.rectangle")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Tokens.Colors.secondaryText)
        }
        .frame(height: thumbHeight)
    }

    private func startAnimation(token: AnimationToken) {
        let sequence: [FABMode] = [.gallery, .transition, .camera]
        var t: TimeInterval = 0.8
        let restX = fabSize / 2

        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            guard !token.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) { animationPhase = 1 }
        }
        t += 0.3

        func scheduleSwipe(to mode: FABMode, at time: TimeInterval, then next: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + time) {
                guard !token.isCancelled else { return }
                withAnimation(.easeInOut(duration: swipeDuration)) { fingerX = -restX }
                DispatchQueue.main.asyncAfter(deadline: .now() + swipeDuration / 2) {
                    guard !token.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.15)) { currentMode = mode }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + swipeDuration + 0.1) {
                    guard !token.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.2)) { fingerX = restX }
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

// MARK: - Jiggle Reorder Animation

struct JiggleReorderAnimation: View {
    @State private var token = AnimationToken()

    @State private var isJiggling = false
    @State private var fabIsDropTarget = false

    @State private var clipAX: CGFloat = 0
    @State private var clipBX: CGFloat = 0
    @State private var clipCX: CGFloat = 0
    @State private var clipDX: CGFloat = 0
    @State private var clipCVisible = true

    @State private var floaterPos: CGSize = .zero
    @State private var floaterScale: CGFloat = 1.0
    @State private var floaterVisible = false

    @State private var fingerPos: CGSize = .zero
    @State private var fingerVisible = false
    @State private var fingerScale: CGFloat = 1.0

    @State private var clipW: CGFloat = 0
    @State private var cardW: CGFloat = 0

    private let fabSize: CGFloat = Tokens.FAB.size
    private let thumbHeight: CGFloat = 80
    private let pad: CGFloat = Tokens.Spacing.s

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let cw = (w - pad * 2) / 2
            let cy = geo.size.height / 2

            let slotL = pad + cw / 2
            let slotR = w - pad - cw / 2
            let slotLL = slotL - cw
            let slotRR = slotR + cw

            ZStack {
                RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                    .fill(Tokens.Colors.secondaryBackground)

                jiggleClip(0).position(x: clipAX, y: cy)
                jiggleClip(1).position(x: clipBX, y: cy)
                jiggleClip(2).position(x: clipCX, y: cy).opacity(clipCVisible ? 1 : 0)
                jiggleClip(3).position(x: clipDX, y: cy)

                Rectangle()
                    .fill(fabIsDropTarget ? Tokens.Colors.tertiaryBackground : Tokens.Colors.systemRed.opacity(0.9))
                    .frame(width: 2, height: thumbHeight)
                    .position(x: w / 2, y: cy)
                    .animation(.easeInOut(duration: 0.25), value: fabIsDropTarget)
                    .zIndex(1)

                jiggleFAB
                    .position(x: w / 2, y: cy)
                    .zIndex(2)

                if floaterVisible {
                    floaterView(cw: cw)
                        .position(x: w / 2, y: cy)
                        .zIndex(3)
                }

                fingerCircle
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

    private func jiggleClip(_ index: Int) -> some View {
        let seed = Double(index) * 0.3
        let phase = Double(index) * 1.5
        return ZStack {
            RoundedRectangle(cornerRadius: Tokens.Radius.thumb, style: .continuous)
                .fill(Tokens.Colors.tertiaryBackground)
            Image(systemName: "play.rectangle")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Tokens.Colors.secondaryText)
        }
        .frame(width: clipW > 0 ? clipW - 2 : 100, height: thumbHeight)
        .modifier(JiggleModifier(isJiggling: isJiggling, seed: seed, phase: phase))
    }

    private var jiggleFAB: some View {
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

    private func floaterView(cw: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Tokens.Radius.thumb, style: .continuous)
                .fill(Tokens.Colors.tertiaryBackground)
            Image(systemName: "play.rectangle")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Tokens.Colors.secondaryText)
        }
        .frame(width: cw, height: thumbHeight)
        .scaleEffect(floaterScale)
        .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
        .offset(floaterPos)
    }

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

        let clipCentreX = slotR - cardW / 2
        let liftY: CGFloat = -(thumbHeight * 0.8)
        var t: TimeInterval = 0.4

        clipAX = slotLL; clipBX = slotL; clipCX = slotR; clipDX = slotRR
        clipCVisible = true; floaterVisible = false; floaterScale = 1.0; floaterPos = .zero
        fabIsDropTarget = false; isJiggling = false
        fingerVisible = false; fingerScale = 1.0; fingerPos = .zero

        after(t) {
            withAnimation(.easeInOut(duration: 0.2)) {
                fingerPos = CGSize(width: clipCentreX, height: 0)
                fingerVisible = true
            }
        }
        t += 0.5

        after(t) {
            withAnimation(.easeInOut(duration: 0.15)) { fingerScale = 0.8 }
        }
        t += 0.6
        after(t) {
            withAnimation(.easeInOut(duration: 0.3)) { isJiggling = true }
        }
        t += 1.3

        after(t) {
            withAnimation(.easeInOut(duration: 0.15)) { fingerScale = 1.0 }
        }
        t += 0.5

        after(t) {
            withAnimation(.easeInOut(duration: 0.15)) { fingerScale = 0.8 }
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

        after(t) {
            withAnimation(.easeInOut(duration: 0.4)) { clipDX = slotR }
        }
        t += 1.3

        after(t) {
            withAnimation(.easeInOut(duration: 0.15)) { fingerScale = 1.0 }
        }
        t += 0.4

        after(t) {
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

        after(t) {
            withAnimation(.easeInOut(duration: 0.3)) {
                fingerPos = CGSize(width: clipCentreX, height: liftY)
            }
        }
        t += 0.4
        after(t) {
            withAnimation(.easeInOut(duration: 0.15)) { fingerScale = 0.8 }
        }
        t += 0.3

        after(t) {
            withAnimation(.easeInOut(duration: 0.6)) {
                floaterPos = .zero
                fingerPos = .zero
                floaterScale = 0.5
            }
        }
        t += 0.7

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

        after(t) {
            withAnimation(.easeInOut(duration: 0.3)) { isJiggling = false }
        }
        t += 1.5

        after(t) { startAnimation(token: token) }
    }
}

// MARK: - Shared Components

var fingerCircle: some View {
    Circle()
        .fill(.white.opacity(0.3))
        .frame(width: 44, height: 44)
        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
}

struct ViewfinderCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let len: CGFloat = 10
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + len))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + len, y: rect.minY))
        p.move(to: CGPoint(x: rect.maxX - len, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + len))
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - len))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - len, y: rect.maxY))
        p.move(to: CGPoint(x: rect.minX + len, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - len))
        return p
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

struct JiggleModifier: ViewModifier, Animatable {
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
