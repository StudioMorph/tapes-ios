import SwiftUI

public struct FabSwipableIcon: View {
    // Bind to your VM so taps/swipes still switch the real mode
    @Binding var mode: FABMode
    var action: () -> Void

    // Tokens
    let size: CGFloat = Tokens.FAB.size       // circle diameter
    let bgColor = Tokens.Colors.red          // red
    let iconColor = Color.white

    // Gesture state (icon only)
    @State private var iconOffsetX: CGFloat = 0
    @State private var isInteracting = false

    // Tuning
    private let swipeThreshold: CGFloat = 36    // when crossed → change mode
    private let maxDrag: CGFloat = 44           // clamp visual range

    public init(mode: Binding<FABMode>, action: @escaping () -> Void) {
        self._mode = mode
        self.action = action
    }

    public var body: some View {
        ZStack {
            // OUTER CIRCLE (fixed in place)
            Circle()
                .fill(bgColor)
                .frame(width: size, height: size)
                .shadow(color: Color.black.opacity(isInteracting ? 0.35 : 0.25), radius: isInteracting ? 10 : 8, y: 4)

            // ICON (moves with drag, then snaps back)
            Image(systemName: mode.icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(iconColor)
                .frame(width: size, height: size)     // match FAB circle exactly
                .clipShape(Circle().size(width: size, height: size))  // exact circle mask
                .contentShape(Circle().size(width: size, height: size)) // exact hit testing
                .compositingGroup()                   // apply mask after offset
                .offset(x: iconOffsetX)               // <-- only the icon moves
                .animation(.spring(response: 0.28, dampingFraction: 0.88), value: iconOffsetX)
                .contentTransition(.symbolEffect(.replace)) // subtle icon swap
        }
        .overlay(
            // Invisible big tap target
            Circle().fill(Color.clear)
                .contentShape(Circle())
                .onTapGesture { action() }
        )
        .gesture(dragGesture)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                isInteracting = true
                iconOffsetX = clamp(value.translation.width, -maxDrag, maxDrag)
            }
            .onEnded { value in
                defer {
                    // Always snap icon back to center
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                        iconOffsetX = 0
                        isInteracting = false
                    }
                }

                let dx = value.translation.width
                if abs(dx) >= swipeThreshold {
                    // Decide direction
                    let forwards = dx > 0
                    updateMode(forwards: forwards)
                    lightHaptic()
                }
            }
    }

    private func updateMode(forwards: Bool) {
        let all = FABMode.allCases
        if let idx = all.firstIndex(of: mode) {
            let next = forwards ? (idx + 1) % all.count : (idx - 1 + all.count) % all.count
            mode = all[next]
        }
    }

    private func lightHaptic() {
        #if os(iOS)
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()
        #endif
    }

    private func clamp(_ v: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat {
        min(max(v, a), b)
    }

    private var accessibilityLabel: String {
        return mode.title
    }
}
