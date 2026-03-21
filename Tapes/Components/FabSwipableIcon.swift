import SwiftUI

public struct FabSwipableIcon: View {
    @Binding var mode: FABMode
    var disabledModes: Set<FABMode> = []
    var action: () -> Void

    let size: CGFloat = Tokens.FAB.size
    let bgColor = Tokens.Colors.red
    let iconColor = Color.white

    @State private var iconOffsetX: CGFloat = 0
    @State private var isInteracting = false

    private let swipeThreshold: CGFloat = 36
    private let maxDrag: CGFloat = 44

    public init(mode: Binding<FABMode>, disabledModes: Set<FABMode> = [], action: @escaping () -> Void) {
        self._mode = mode
        self.disabledModes = disabledModes
        self.action = action
    }

    public var body: some View {
        ZStack {
            // OUTER CIRCLE (fixed in place)
            Circle()
                .fill(bgColor)
                .frame(width: size, height: size)
                .shadow(color: Color.black.opacity(isInteracting ? 0.35 : 0.25), radius: isInteracting ? 10 : 8, y: 4)

            // MOVING ICON LAYER — this is what must be masked
            ZStack {
                Image(systemName: mode.icon)
                    .font(.system(size: size * 0.36, weight: .semibold)) // proportional to FAB size
                    .foregroundColor(iconColor)
                    .offset(x: iconOffsetX)               // <-- only the icon moves
                    .animation(.spring(response: 0.28, dampingFraction: 0.88), value: iconOffsetX)
                    .contentTransition(.symbolEffect(.replace)) // subtle icon swap
            }
            .frame(width: size, height: size, alignment: .center) // EXACT frame
            .compositingGroup()
            .mask(
                Circle()
                    .frame(width: size, height: size, alignment: .center)
            )
        }
        .frame(width: size, height: size)
        .contentShape(Circle()) // keep hit target
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
        guard let idx = all.firstIndex(of: mode) else { return }
        let direction = forwards ? 1 : -1
        var next = (idx + direction + all.count) % all.count
        var attempts = 0
        while disabledModes.contains(all[next]) && attempts < all.count {
            next = (next + direction + all.count) % all.count
            attempts += 1
        }
        if !disabledModes.contains(all[next]) {
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
