import SwiftUI

struct ClipCarousel: View {
    @Binding var tape: Tape
    let thumbSize: CGSize
    @Binding var insertionIndex: Int
    @Binding var savedCarouselPosition: Int
    @Binding var pendingAdvancement: Int
    let onPlaceholderTap: (CarouselItem) -> Void
    let onSnapped: ((Int, Int) -> Void)?
    
    @State private var savedScrollOffset: CGFloat = 0
    @State private var savedSnapIndex: Int = 0
    @State private var lastClipCount: Int = 0
    @State private var shouldAdvance: Bool = false
    @State private var targetPosition: Int = 0
    
    // Direct observation of tape.clips - no caching
    var items: [CarouselItem] {
        let result: [CarouselItem]
        if tape.clips.isEmpty {
            result = [.startPlus]
        } else {
            result = [.startPlus] + tape.clips.map { .clip($0) } + [.endPlus]
        }
        print("📋 Items array: \(result.map { $0.id })")
        return result
    }
    
    // Hash only thumbnail states - not clip count to avoid carousel recreation
    private var thumbnailHash: Int {
        let thumbnailStates = tape.clips.map { "\($0.thumbnail != nil)" }.joined()
        return thumbnailStates.hashValue
    }
    
    var body: some View {
        let _ = print("📋 ClipCarousel: \(tape.clips.count) clips, items count: \(items.count)")
        let _ = thumbnailHash // Force dependency on thumbnail changes
        
        // Calculate target position based on current state
        let currentTargetPosition = calculateTargetPosition()
        
        // Stable ID that doesn't change when clips are added
        let stableCarouselId = "carousel-\(tape.id)"
        
        GeometryReader { container in
            SnappingHScroll(itemWidth: thumbSize.width,
                           leadingInset: 16,
                           trailingInset: 16,
                           containerWidth: container.size.width,
                           targetSnapIndex: pendingAdvancement > 0 ? savedCarouselPosition + pendingAdvancement : nil,
                           onSnapped: { leftIndex, rightIndex in
                               // Update saved position when carousel snaps
                               savedCarouselPosition = leftIndex
                               print("🎯 Carousel snapped to position: \(leftIndex)")
                               
                               // Clear pending advancement after applying it
                               if pendingAdvancement > 0 {
                                   print("🎯 Applied advancement of \(pendingAdvancement), new position: \(leftIndex)")
                                   pendingAdvancement = 0
                               }
                           }) {
                // Leading 16pt padding INSIDE the card
                Color.clear.frame(width: 16)
                
                ForEach(items) { item in
                    let _ = print("🔄 ForEach rendering item: \(item.id)")
                    ThumbnailView(item: item, onPlaceholderTap: onPlaceholderTap)
                        .frame(width: thumbSize.width, height: thumbSize.height)
                        .id(item.id) // Force SwiftUI to recognize each item
                }
                
                // Trailing 16pt padding INSIDE the card
                Color.clear.frame(width: 16)
            }
            .id(stableCarouselId) // Stable ID - doesn't change when clips added
        }
        .frame(height: thumbSize.height) // hug
        .onChange(of: tape.clips.count) { oldValue, newValue in
            print("Timeline sees clips = \(newValue)")
            for (index, clip) in tape.clips.enumerated() {
                print("  Clip \(index): id=\(clip.id), type=\(clip.clipType), hasThumb=\(clip.thumbnail != nil), localURL=\(clip.localURL?.lastPathComponent ?? "nil")")
            }
            
            // If clips were added, advance the carousel by the number of clips added
            if newValue > oldValue {
                let clipsAdded = newValue - oldValue
                targetPosition = savedSnapIndex + clipsAdded
                shouldAdvance = true
                print("🎯 Clips added: \(oldValue) -> \(newValue), advancing by \(clipsAdded) to position \(targetPosition)")
                
                // Reset the flag after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    shouldAdvance = false
                    print("🎯 Advancement flag reset")
                }
            }
        }
    }
    
    // Calculate the target position based on current state
    private func calculateTargetPosition() -> Int {
        // If we should advance due to clips being added, use the calculated target position
        if shouldAdvance && targetPosition > 0 {
            print("🎯 Using calculated target position: \(targetPosition)")
            return targetPosition
        }
        
        // Only return a target position if we have clips and a valid insertion index
        if !tape.clips.isEmpty && insertionIndex > 0 && insertionIndex <= tape.clips.count {
            print("🎯 Using insertion index: \(insertionIndex)")
            return insertionIndex
        }
        
        // No target position - let the carousel stay at its current position
        return 0
    }
    
}


public enum CarouselItem: Identifiable {
    case startPlus
    case clip(Clip)
    case endPlus
    
    public var id: String {
        switch self {
        case .startPlus:
            return "start-plus"
        case .clip(let clip):
            return clip.id.uuidString
        case .endPlus:
            return "end-plus"
        }
    }
}

#Preview {
    VStack {
        ClipCarousel(
            tape: .constant(Tape.sampleTapes[0]),
            thumbSize: CGSize(width: 150, height: 84),
            insertionIndex: .constant(0),
            savedCarouselPosition: .constant(0),
            pendingAdvancement: .constant(0),
            onPlaceholderTap: { _ in }
        )
        .frame(height: 84)
        .background(Color.gray.opacity(0.3))
    }
    .padding()
    .background(Tokens.Colors.bg)
}