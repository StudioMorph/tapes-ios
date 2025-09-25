import SwiftUI

// MARK: - Carousel State

public class CarouselState: ObservableObject {
    @Published public var thumbnails: [ClipThumbnail] = []
    @Published public var currentIndex: Int = 0
    @Published public var insertionIndex: Int = 0
    
    public init() {}
    
    public func addThumbnail(_ thumbnail: ClipThumbnail, at index: Int) {
        thumbnails.insert(thumbnail, at: index)
        updateInsertionIndex()
    }
    
    public func removeThumbnail(at index: Int) {
        guard index < thumbnails.count else { return }
        thumbnails.remove(at: index)
        updateInsertionIndex()
    }
    
    public func updateInsertionIndex() {
        // Insertion index is always at the center (where FAB is)
        insertionIndex = thumbnails.count
    }
}

// MARK: - Snap Calculation

public struct SnapCalculator {
    let itemWidth: CGFloat
    let fabWidth: CGFloat = 64
    let spacing: CGFloat = 16
    
    public init(screenWidth: CGFloat) {
        // Width = (screenWidth - 64)/2 as per runbook
        self.itemWidth = (screenWidth - 64) / 2
    }
    
    public func calculateSnapOffset(for scrollOffset: CGFloat) -> CGFloat {
        let totalItemWidth = itemWidth + spacing
        let fabCenter = itemWidth + spacing + fabWidth / 2
        
        // Calculate which items should be on left and right of FAB
        let leftIndex = max(0, Int((scrollOffset + fabCenter - itemWidth / 2) / totalItemWidth))
        _ = leftIndex + 1
        
        // Snap to position where left item is left of FAB, right item is right of FAB
        let snapOffset = CGFloat(leftIndex) * totalItemWidth - (fabCenter - itemWidth / 2)
        
        return snapOffset
    }
    
    public func getInsertionIndex(for scrollOffset: CGFloat, thumbnailsCount: Int) -> Int {
        let totalItemWidth = itemWidth + spacing
        let fabCenter = itemWidth + spacing + fabWidth / 2
        
        // Insertion happens at the gap under the FAB
        let insertionIndex = max(0, Int((scrollOffset + fabCenter) / totalItemWidth))
        return min(insertionIndex, thumbnailsCount)
    }
    
    public func getLeftRightIndices(for scrollOffset: CGFloat) -> (left: Int, right: Int) {
        let totalItemWidth = itemWidth + spacing
        let fabCenter = itemWidth + spacing + fabWidth / 2
        
        let leftIndex = max(0, Int((scrollOffset + fabCenter - itemWidth / 2) / totalItemWidth))
        _ = leftIndex + 1
        
        return (left: leftIndex, right: leftIndex + 1)
    }
}

// MARK: - Carousel Component

public struct Carousel: View {
    @StateObject private var state = CarouselState()
    @State private var scrollOffset: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    
    let screenWidth: CGFloat
    let onThumbnailTap: (ClipThumbnail) -> Void
    let onThumbnailLongPress: (ClipThumbnail) -> Void
    let onFABAction: (FABMode) -> Void
    
    private let calculator: SnapCalculator
    
    public init(
        screenWidth: CGFloat,
        onThumbnailTap: @escaping (ClipThumbnail) -> Void,
        onThumbnailLongPress: @escaping (ClipThumbnail) -> Void,
        onFABAction: @escaping (FABMode) -> Void
    ) {
        self.screenWidth = screenWidth
        self.onThumbnailTap = onThumbnailTap
        self.onThumbnailLongPress = onThumbnailLongPress
        self.onFABAction = onFABAction
        self.calculator = SnapCalculator(screenWidth: screenWidth)
    }
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.clear
                
                // Thumbnails
                HStack(spacing: calculator.spacing) {
                    // Start placeholder
                    if state.thumbnails.isEmpty {
                        Thumbnail(
                            thumbnail: ClipThumbnail(
                                id: "start-placeholder",
                                isPlaceholder: true,
                                index: 0,
                                tapeName: "Tape"
                            ),
                            width: calculator.itemWidth,
                            onTap: { onFABAction(.camera) },
                            onLongPress: {}
                        )
                    } else {
                        ForEach(Array(state.thumbnails.enumerated()), id: \.element.id) { index, thumbnail in
                            Thumbnail(
                                thumbnail: thumbnail,
                                width: calculator.itemWidth,
                                onTap: { onThumbnailTap(thumbnail) },
                                onLongPress: { onThumbnailLongPress(thumbnail) }
                            )
                        }
                        
                        // End placeholder
                        Thumbnail(
                            thumbnail: ClipThumbnail(
                                id: "end-placeholder",
                                isPlaceholder: true,
                                index: state.thumbnails.count,
                                tapeName: "Tape"
                            ),
                            width: calculator.itemWidth,
                            onTap: { onFABAction(.camera) },
                            onLongPress: {}
                        )
                    }
                }
                .offset(x: scrollOffset + dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isDragging = true
                            dragOffset = value.translation.width
                        }
                        .onEnded { value in
                            isDragging = false
                            
                            // Calculate snap position
                            let snapOffset = calculator.calculateSnapOffset(for: scrollOffset + value.translation.width)
                            
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                scrollOffset = snapOffset
                                dragOffset = 0
                            }
                            
                            // Update insertion index
                            state.insertionIndex = calculator.getInsertionIndex(for: scrollOffset, thumbnailsCount: state.thumbnails.count)
                            
                            // Haptic feedback
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                        }
                )
                
                // Fixed FAB at center
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        FAB(onAction: onFABAction)
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
        .onAppear {
            // Initialize with start placeholder
            if state.thumbnails.isEmpty {
                // Update insertion index when thumbnails change
                state.insertionIndex = state.thumbnails.count
            }
        }
    }
    
    // MARK: - Public Methods
    
    public func addThumbnail(_ thumbnail: ClipThumbnail) {
        state.addThumbnail(thumbnail, at: state.insertionIndex)
        
        // Snap to show the new thumbnail
        let snapOffset = calculator.calculateSnapOffset(for: scrollOffset)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            scrollOffset = snapOffset
        }
    }
    
    public func removeThumbnail(_ thumbnail: ClipThumbnail) {
        if let index = state.thumbnails.firstIndex(of: thumbnail) {
            state.removeThumbnail(at: index)
            
            // Snap to maintain proper positioning
            let snapOffset = calculator.calculateSnapOffset(for: scrollOffset)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                scrollOffset = snapOffset
            }
        }
    }
    
    public func getCurrentThumbnails() -> [ClipThumbnail] {
        return state.thumbnails
    }
    
    public func getInsertionIndex() -> Int {
        return state.insertionIndex
    }
}

// MARK: - Preview

struct Carousel_Previews: PreviewProvider {
    static var previews: some View {
        GeometryReader { geometry in
            Carousel(
                screenWidth: geometry.size.width,
                onThumbnailTap: { thumbnail in
                    print("Thumbnail tapped: \(thumbnail.id)")
                },
                onThumbnailLongPress: { thumbnail in
                    print("Thumbnail long pressed: \(thumbnail.id)")
                },
                onFABAction: { mode in
                    print("FAB action: \(mode)")
                }
            )
        }
        .background(DesignTokens.Colors.surface(.light))
        .previewDisplayName("Carousel Component")
    }
}
