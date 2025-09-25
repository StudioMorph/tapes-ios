import SwiftUI

enum FABMode: CaseIterable {
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
            return "arrow.right.arrow.left"
        }
    }
    
    var title: String {
        switch self {
        case .camera:
            return "Camera"
        case .gallery:
            return "Add from Gallery"
        case .transition:
            return "Transition"
        }
    }
}

struct FAB: View {
    let onAction: (FABMode) -> Void
    
    @State private var currentMode: FABMode = .camera
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    
    var body: some View {
        VStack {
            Image(systemName: currentMode.icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(Tokens.Colors.textOnAccent)
        }
        .frame(width: 60, height: 60)
        .background(Tokens.Colors.brandRed)
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
        .overlay(
            // Vertical lines extending from FAB
            VStack {
                Rectangle()
                    .fill(Tokens.Colors.brandRed)
                    .frame(width: 2, height: 20)
                Spacer()
                Rectangle()
                    .fill(Tokens.Colors.brandRed)
                    .frame(width: 2, height: 20)
            }
        )
        .offset(x: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    isDragging = true
                    dragOffset = value.translation.width
                }
                .onEnded { value in
                    isDragging = false
                    
                    // Cycle through modes based on swipe direction
                    if abs(value.translation.width) > 50 {
                        if value.translation.width > 0 {
                            // Swipe right - next mode
                            cycleToNextMode()
                        } else {
                            // Swipe left - previous mode
                            cycleToPreviousMode()
                        }
                    }
                    
                    withAnimation(.spring()) {
                        dragOffset = 0
                    }
                }
        )
        .onTapGesture {
            onAction(currentMode)
        }
    }
    
    private func cycleToNextMode() {
        let allModes = FABMode.allCases
        if let currentIndex = allModes.firstIndex(of: currentMode) {
            let nextIndex = (currentIndex + 1) % allModes.count
            currentMode = allModes[nextIndex]
        }
    }
    
    private func cycleToPreviousMode() {
        let allModes = FABMode.allCases
        if let currentIndex = allModes.firstIndex(of: currentMode) {
            let previousIndex = currentIndex == 0 ? allModes.count - 1 : currentIndex - 1
            currentMode = allModes[previousIndex]
        }
    }
}

#Preview("Dark Mode") {
    FAB { _ in }
        .preferredColorScheme(.dark)
        .padding()
        .background(Tokens.Colors.bg)
}

#Preview("Light Mode") {
    FAB { _ in }
        .preferredColorScheme(.light)
        .padding()
        .background(Tokens.Colors.bg)
}