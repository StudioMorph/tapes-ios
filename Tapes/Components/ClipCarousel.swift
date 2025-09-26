import SwiftUI

struct ClipCarousel: View {
    let tape: Tape
    let thumbSize: CGSize
    @Binding var insertionIndex: Int
    let onPlaceholderTap: (CarouselItem) -> Void
    
    
    var items: [CarouselItem] {
        if tape.clips.isEmpty {
            return [.startPlus]
        } else {
            return [.startPlus] + tape.clips.map { .clip($0) } + [.endPlus]
        }
    }
    
    var body: some View {
        GeometryReader { container in
            SnappingHScroll(itemWidth: thumbSize.width,
                           leadingInset: 16,
                           trailingInset: 16,
                           containerWidth: container.size.width) {
                // Leading 16pt padding INSIDE the card
                Color.clear.frame(width: 16)
                
                ForEach(items.indices, id: \.self) { i in
                    ThumbnailView(item: items[i], onPlaceholderTap: onPlaceholderTap)
                        .frame(width: thumbSize.width, height: thumbSize.height)
                        .id("item-\(i)")
                }
                
                // Trailing 16pt padding INSIDE the card
                Color.clear.frame(width: 16)
            }
        }
        .frame(height: thumbSize.height) // hug
    }
    
}


public enum CarouselItem {
    case startPlus
    case clip(Clip)
    case endPlus
}

#Preview {
    VStack {
        ClipCarousel(
            tape: Tape.sampleTapes[0],
            thumbSize: CGSize(width: 150, height: 84),
            insertionIndex: .constant(0),
            onPlaceholderTap: { _ in }
        )
        .frame(height: 84)
        .background(Color.gray.opacity(0.3))
    }
    .padding()
    .background(Tokens.Colors.bg)
}