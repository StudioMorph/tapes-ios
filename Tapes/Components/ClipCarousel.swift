import SwiftUI

extension Notification.Name {
    static let floatingClipDragEnded = Notification.Name("floatingClipDragEnded")
}

struct DropTargetInfo: Equatable {
    let tapeID: UUID
    let insertionIndex: Int
    let frame: CGRect
    let kind: Kind
    enum Kind: Equatable { case startPlus, endPlus, fab }
}

struct DropTargetPreferenceKey: PreferenceKey {
    static var defaultValue: [DropTargetInfo] = []
    static func reduce(value: inout [DropTargetInfo], nextValue: () -> [DropTargetInfo]) {
        value.append(contentsOf: nextValue())
    }
}

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
                        tapeID: tape.id,
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
    let tapeID: UUID
    let thumbSize: CGSize
    let onPlaceholderTap: (CarouselItem) -> Void
    var onClipTap: ((Clip) -> Void)? = nil
    var onClipDelete: ((Clip) -> Void)? = nil

    private var isJiggling: Bool {
        tapeStore.jigglingTapeID != nil
    }

    private var isThisClipFloating: Bool {
        guard case .clip(let clip) = item else { return false }
        return tapeStore.floatingClip?.id == clip.id
    }

    var body: some View {
        if isJiggling, case .clip(let clip) = item, !clip.isPlaceholder {
            let seed = Double(clip.id.hashValue & 0xFF) / 255.0
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let baseAngle = 1.5 + seed * 1.5
                let speed = 8.0 + seed * 4.0
                let angle = baseAngle * sin(time * speed)

                let isLifted = tapeStore.floatingClip?.id == clip.id
                GeometryReader { geo in
                    let globalFrame = geo.frame(in: .named("tapesListCoordinateSpace"))
                    ThumbnailView(
                        item: item,
                        onPlaceholderTap: onPlaceholderTap,
                        onClipTap: onClipTap,
                        tapeID: tapeID,
                        clipCount: tapeStore.getTape(by: tapeID)?.clips.count ?? 0
                    )
                    .frame(width: thumbSize.width, height: thumbSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(alignment: .top) {
                        if !isLifted {
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
                            .offset(y: -12)
                        }
                    }
                    .scaleEffect(isLifted ? 0.001 : 0.92)
                    .rotationEffect(.degrees(isLifted ? 0 : angle))
                    .opacity(isLifted ? 0 : 1)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isLifted)
                    .gesture(
                        DragGesture(minimumDistance: 20, coordinateSpace: .named("tapesListCoordinateSpace"))
                            .onChanged { value in
                                if !tapeStore.isFloatingClip {
                                    let clipIndex = tapeStore.getTape(by: tapeID)?.clips.firstIndex(where: { $0.id == clip.id }) ?? 0
                                    tapeStore.liftClip(clip, fromTape: tapeID, atIndex: clipIndex, originFrame: globalFrame, thumbSize: thumbSize)
                                }
                                tapeStore.floatingPosition = value.location
                            }
                            .onEnded { value in
                                if tapeStore.isFloatingClip {
                                    NotificationCenter.default.post(
                                        name: .floatingClipDragEnded,
                                        object: nil,
                                        userInfo: ["x": value.location.x, "y": value.location.y]
                                    )
                                }
                            }
                    )
                }
                .frame(width: thumbSize.width, height: thumbSize.height)
            }
        } else {
            ThumbnailView(
                item: item,
                onPlaceholderTap: onPlaceholderTap,
                onClipTap: onClipTap,
                tapeID: tapeID,
                clipCount: tapeStore.getTape(by: tapeID)?.clips.count ?? 0
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