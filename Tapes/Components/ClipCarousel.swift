import SwiftUI

struct ClipCarousel: View {
    @Binding var tape: Tape
    let thumbSize: CGSize
    @Binding var insertionIndex: Int
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
    
    // Force re-evaluation when tape changes
    private var tapeHash: Int {
        // Hash clip count and thumbnail states to detect changes
        let clipCount = tape.clips.count
        let thumbnailStates = tape.clips.map { "\($0.thumbnail != nil)" }.joined()
        return "\(clipCount)-\(thumbnailStates)".hashValue
    }
    
    var body: some View {
        let _ = print("📋 ClipCarousel: \(tape.clips.count) clips, items count: \(items.count)")
        let _ = tapeHash // Force dependency on tape changes
        
        // Calculate target position based on current state
        let currentTargetPosition = calculateTargetPosition()
        
        // Force re-evaluation by using the hash as an ID
        let carouselId = "carousel-\(tape.id)-\(tapeHash)"
        GeometryReader { container in
            SnappingHScroll(itemWidth: thumbSize.width,
                           leadingInset: 16,
                           trailingInset: 16,
                           containerWidth: container.size.width,
                           onSnapped: { leftIndex, totalCount in
                               print("🎯 Snap position: leftIndex=\(leftIndex), totalCount=\(totalCount)")
                               savedSnapIndex = leftIndex
                               onSnapped?(leftIndex, totalCount)
                           },
                           savedOffset: savedScrollOffset,
                           onOffsetChanged: { offset in
                               print("🎯 Scroll position changed: \(offset)")
                               savedScrollOffset = offset
                           },
                           targetSnapIndex: currentTargetPosition > 0 ? currentTargetPosition : nil) {
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
            .id(carouselId) // Use stable ID to preserve scroll position
        }
        .frame(height: thumbSize.height) // hug
        .onChange(of: tape.clips.count) { oldValue, newValue in
            print("Timeline sees clips = \(newValue)")
            for (index, clip) in tape.clips.enumerated() {
                print("  Clip \(index): id=\(clip.id), type=\(clip.clipType), hasThumb=\(clip.thumbnail != nil), localURL=\(clip.localURL?.lastPathComponent ?? "nil")")
            }
        }
    }
    
    // Calculate the target position based on current state
    private func calculateTargetPosition() -> Int {
        // If we have clips and the insertion index is set, use that
        if !tape.clips.isEmpty && insertionIndex > 0 {
            print("🎯 Using insertion index: \(insertionIndex)")
            return insertionIndex
        }
        
        // Default to showing the first clip
        return 1
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
            onPlaceholderTap: { _ in },
            onSnapped: nil
        )
        .frame(height: 84)
        .background(Color.gray.opacity(0.3))
    }
    .padding()
    .background(Tokens.Colors.bg)
}