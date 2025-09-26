import SwiftUI

struct Carousel: View {
    let tape: Tape
    let onThumbnailDelete: (Clip) -> Void
    
    @StateObject private var state = CarouselState()
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    
    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let itemWidth: CGFloat = 80
            let spacing: CGFloat = Tokens.Spacing.l
            let fabWidth: CGFloat = 60
            
            ZStack {
                // Vertical centerline behind FAB
                Rectangle()
                    .fill(Tokens.Colors.red)
                    .frame(width: 2, height: 80)
                    .position(x: screenWidth / 2, y: 40)
                
                // Carousel content that moves beneath the FAB
                HStack(spacing: spacing) {
                    // Start placeholder
                    if tape.clips.isEmpty {
                        VStack {
                            Image(systemName: "plus")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(Tokens.Colors.onSurface)
                        }
                        .frame(width: itemWidth, height: itemWidth * 9/16)
                        .background(Tokens.Colors.elevated)
                        .cornerRadius(8)
                    }
                    
                    // Thumbnails
                    ForEach(Array(tape.clips.enumerated()), id: \.element.id) { index, clip in
                        Thumbnail(
                            thumbnail: ClipThumbnail(
                                id: clip.id.uuidString,
                                assetLocalId: clip.assetLocalId ?? "",
                                index: index + 1,
                                isPlaceholder: false
                            ),
                            onDelete: { onThumbnailDelete(clip) }
                        )
                    }
                    
                    // End placeholder
                    if !tape.clips.isEmpty {
                        VStack {
                            Image(systemName: "plus")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(Tokens.Colors.onSurface)
                        }
                        .frame(width: itemWidth, height: itemWidth * 9/16)
                        .background(Tokens.Colors.elevated)
                        .cornerRadius(8)
                    }
                }
                .offset(x: dragOffset)
                .gesture(
                    DragGesture()
                    .onChanged { value in
                        isDragging = true
                        dragOffset = value.translation.width
                    }
                        .onEnded { value in
                            isDragging = false
                            withAnimation(.spring()) {
                                dragOffset = 0
                            }
                        }
                )
                
                // FAB - Fixed in center, always visible
                VStack {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Tokens.Colors.onSurface)
                }
                .frame(width: fabWidth, height: fabWidth)
                .background(Tokens.Colors.red)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
                .position(x: screenWidth / 2, y: 40)
            }
        }
        .frame(height: 80)
    }
}

// MARK: - Carousel State

class CarouselState: ObservableObject {
    @Published var thumbnails: [ClipThumbnail] = []
    @Published var currentIndex: Int = 0
    @Published var scrollOffset: CGFloat = 0
}

// MARK: - Snap Calculator

struct SnapCalculator {
    let itemWidth: CGFloat
    let fabWidth: CGFloat
    let spacing: CGFloat
    let screenWidth: CGFloat
    
    init(itemWidth: CGFloat, fabWidth: CGFloat, spacing: CGFloat, screenWidth: CGFloat) {
        self.itemWidth = itemWidth
        self.fabWidth = fabWidth
        self.spacing = spacing
        self.screenWidth = screenWidth
    }
    
    func getLeftIndex(for scrollOffset: CGFloat) -> Int {
        let centerX = screenWidth / 2
        let fabCenterX = centerX
        let leftEdge = fabCenterX - fabWidth / 2 - spacing - itemWidth
        return max(0, Int((leftEdge - scrollOffset) / (itemWidth + spacing)))
    }
    
    func getRightIndex(for scrollOffset: CGFloat) -> Int {
        let centerX = screenWidth / 2
        let fabCenterX = centerX
        let rightEdge = fabCenterX + fabWidth / 2 + spacing
        return Int((rightEdge - scrollOffset) / (itemWidth + spacing))
    }
    
    func getInsertionIndex(for scrollOffset: CGFloat, thumbnailsCount: Int) -> Int {
        let centerX = screenWidth / 2
        let fabCenterX = centerX
        let leftIndex = getLeftIndex(for: scrollOffset)
        let rightIndex = getRightIndex(for: scrollOffset)
        
        if scrollOffset < fabCenterX - fabWidth / 2 {
            return leftIndex
        } else {
            return min(thumbnailsCount, rightIndex)
        }
    }
}

#Preview("Dark Mode") {
    Carousel(
        tape: Tape.sampleTapes[0],
        onThumbnailDelete: { _ in }
    )
    .preferredColorScheme(.dark)
    .padding()
    .background(Tokens.Colors.bg)
}

#Preview("Light Mode") {
    Carousel(
        tape: Tape.sampleTapes[0],
        onThumbnailDelete: { _ in }
    )
    .preferredColorScheme(.light)
    .padding()
    .background(Tokens.Colors.bg)
}