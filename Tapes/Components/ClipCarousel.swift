import SwiftUI

struct ClipCarousel: View {
    @Binding var tape: Tape
    let thumbSize: CGSize
    @Binding var insertionIndex: Int
    @Binding var savedCarouselPosition: Int
    @Binding var pendingAdvancement: Int
    @Binding var isNewSession: Bool
    let initialCarouselPosition: Int
    @Binding var pendingTargetItemIndex: Int?
    @Binding var pendingToken: UUID?
    let onPlaceholderTap: (CarouselItem) -> Void
    var onClipTap: ((Clip) -> Void)? = nil
    var onClipDelete: ((Clip) -> Void)? = nil
    
    // Direct observation of tape.clips - no caching
    var items: [CarouselItem] {
        if tape.clips.isEmpty {
            return [.startPlus]
        }
        return [.startPlus] + tape.clips.map { .clip($0) } + [.endPlus]
    }
    
    // Force re-evaluation when tape changes
    private var tapeHash: Int {
        tape.clips.map { "\($0.id)-\($0.hasThumbnail)" }.joined().hashValue
    }
    
    var body: some View {
        // Force re-evaluation by using the hash as an ID
        let carouselId = "carousel-\(tape.id)-\(tapeHash)"
        GeometryReader { container in
            SnappingHScroll(itemWidth: thumbSize.width,
                           leadingInset: 16,
                           trailingInset: 16,
                           containerWidth: container.size.width,
                           targetSnapIndex: pendingTargetItemIndex,
                           currentSnapIndex: isNewSession ? (initialCarouselPosition + 1) : (savedCarouselPosition + 1),
                           pendingToken: pendingToken,
                           tapeId: tape.id,
                           onSnapped: { leftIndex, rightIndex in
                               // Convert from item-space to clip-space
                               let clipLeft = max(0, leftIndex - 1)
                               
                               // Update saved position when carousel snaps
                               let oldPosition = savedCarouselPosition
                               savedCarouselPosition = clipLeft
                               // Clear pending target after applying it
                               if pendingTargetItemIndex != nil {
                                   pendingTargetItemIndex = nil
                                   pendingToken = nil
                               }
                               
                               // Mark session as "opened" after first positioning
                               if isNewSession {
                                   isNewSession = false
                               }
                           }) {
                // Leading 16pt padding INSIDE the card
                Color.clear.frame(width: 16)
                
                ForEach(items) { item in
                    JiggleableClipView(
                        item: item,
                        thumbSize: thumbSize,
                        onPlaceholderTap: onPlaceholderTap,
                        onClipTap: onClipTap,
                        onClipDelete: onClipDelete
                    )
                    .id(item.id)
                }
                
                // Trailing 16pt padding INSIDE the card
                Color.clear.frame(width: 16)
            }
            .id(carouselId) // Force re-evaluation when tape changes
        }
        .frame(height: thumbSize.height)
    }
    
}


private struct JiggleableClipView: View {
    @EnvironmentObject private var tapeStore: TapesStore
    let item: CarouselItem
    let thumbSize: CGSize
    let onPlaceholderTap: (CarouselItem) -> Void
    var onClipTap: ((Clip) -> Void)? = nil
    var onClipDelete: ((Clip) -> Void)? = nil

    private var isJiggling: Bool {
        tapeStore.jigglingTapeID != nil
    }

    var body: some View {
        if isJiggling, case .clip(let clip) = item, !clip.isPlaceholder {
            let seed = Double(clip.id.hashValue & 0xFF) / 255.0
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let baseAngle = 1.5 + seed * 1.5
                let speed = 8.0 + seed * 4.0
                let angle = baseAngle * sin(time * speed)
                ThumbnailView(
                    item: item,
                    onPlaceholderTap: onPlaceholderTap,
                    onClipTap: onClipTap
                )
                .frame(width: thumbSize.width, height: thumbSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Button {
                        onClipDelete?(clip)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Tokens.Colors.primaryText)
                            .frame(width: 24, height: 24)
                            .background(.ultraThinMaterial, in: Circle())
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    }
                    .offset(x: 12, y: -12)
                }
                .scaleEffect(0.92)
                .rotationEffect(.degrees(angle))
            }
        } else {
            ThumbnailView(
                item: item,
                onPlaceholderTap: onPlaceholderTap,
                onClipTap: onClipTap
            )
            .frame(width: thumbSize.width, height: thumbSize.height)
            .clipped()
        }
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
            savedCarouselPosition: .constant(1),
            pendingAdvancement: .constant(0),
            isNewSession: .constant(true),
            initialCarouselPosition: 1,
            pendingTargetItemIndex: .constant(nil),
            pendingToken: .constant(nil),
            onPlaceholderTap: { _ in }
        )
        .frame(height: 84)
        .background(Color.gray.opacity(0.3))
    }
    .padding()
    .background(Tokens.Colors.bg)
}