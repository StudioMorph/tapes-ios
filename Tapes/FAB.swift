import SwiftUI

// MARK: - FAB States

public enum FABMode: CaseIterable {
    case camera
    case gallery
    case transition
    
    var icon: String {
        switch self {
        case .camera:
            return "camera.fill"
        case .gallery:
            return "photo.on.rectangle"
        case .transition:
            return "arrow.left.arrow.right"
        }
    }
    
    var accessibilityLabel: String {
        switch self {
        case .camera:
            return "Record from camera"
        case .gallery:
            return "Add from gallery"
        case .transition:
            return "Add transition"
        }
    }
}

// MARK: - FAB Component

public struct FAB: View {
    @State private var currentMode: FABMode = .camera
    @State private var dragOffset: CGFloat = 0
    @State private var isPressed: Bool = false
    
    let onAction: (FABMode) -> Void
    
    public init(onAction: @escaping (FABMode) -> Void) {
        self.onAction = onAction
    }
    
    public var body: some View {
        Button(action: {
            onAction(currentMode)
        }) {
            Image(systemName: currentMode.icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 64, height: 64)
                .background(
                    Circle()
                        .fill(DesignTokens.Colors.primaryRed)
                        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                )
        }
        .buttonStyle(FABButtonStyle())
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation.width
                }
                .onEnded { value in
                    let threshold: CGFloat = 30
                    let velocity = value.velocity.width
                    
                    if abs(value.translation.width) > threshold || abs(velocity) > 500 {
                        if value.translation.width > 0 || velocity > 0 {
                            // Swipe right - cycle forward
                            cycleMode(forward: true)
                        } else {
                            // Swipe left - cycle backward
                            cycleMode(forward: false)
                        }
                    }
                    
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        dragOffset = 0
                    }
                }
        )
        .onLongPressGesture(minimumDuration: 0) {
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = true
            }
        }
    }
    
    private func cycleMode(forward: Bool) {
        let allModes = FABMode.allCases
        guard let currentIndex = allModes.firstIndex(of: currentMode) else { return }
        
        let nextIndex: Int
        if forward {
            nextIndex = (currentIndex + 1) % allModes.count
        } else {
            nextIndex = (currentIndex - 1 + allModes.count) % allModes.count
        }
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentMode = allModes[nextIndex]
        }
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
}

// MARK: - FAB Button Style

private struct FABButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Preview

struct FAB_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 40) {
            FAB { mode in
                print("FAB tapped: \(mode)")
            }
            
            // Show all modes
            HStack(spacing: 20) {
                ForEach(FABMode.allCases, id: \.self) { mode in
                    VStack {
                        Image(systemName: mode.icon)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 48, height: 48)
                            .background(
                                Circle()
                                    .fill(DesignTokens.Colors.primaryRed)
                            )
                        Text(mode.accessibilityLabel)
                            .font(DesignTokens.Typography.caption)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
        .padding()
        .background(DesignTokens.Colors.surface(.light))
        .previewDisplayName("FAB Component")
    }
}
