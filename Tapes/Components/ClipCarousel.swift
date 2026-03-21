import SwiftUI

struct DropTargetInfo: Equatable {
    let tapeID: UUID
    let insertionIndex: Int
    let seamLeftClipID: UUID?
    let seamRightClipID: UUID?
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
    @EnvironmentObject private var tapeStore: TapesStore
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
    var onClipDuplicate: ((Clip) -> Void)? = nil
    var onSeamChanged: ((UUID?, UUID?) -> Void)? = nil
    var onScrollFractionChanged: ((CGFloat) -> Void)? = nil
    
    var items: [CarouselItem] {
        let visibleClips = tape.clips.filter { $0.id != tapeStore.floatingClip?.id }
        if visibleClips.isEmpty {
            return [.startPlus]
        }
        return [.startPlus] + visibleClips.map { .clip($0) } + [.endPlus]
    }
    
    private var tapeHash: Int {
        let floatingID = tapeStore.floatingClip?.id.uuidString ?? "none"
        return (tape.clips.map { "\($0.id)-\($0.hasThumbnail)" }.joined() + "-f:\(floatingID)").hashValue
    }
    
    var body: some View {
        GeometryReader { container in
            // After a drop, use the drop index directly so the carousel
            // recreates at the correct position (onChange fires too late).
            let effectiveSavedPos: Int = {
                if !tapeStore.isFloatingClip,
                   tapeStore.dropCompletedTapeID == tape.id,
                   let dropIdx = tapeStore.dropCompletedAtIndex {
                    return dropIdx
                }
                return savedCarouselPosition
            }()
            let floatingIsBeforeFAB: Bool = {
                guard tapeStore.floatingSourceTapeID == tape.id,
                      let srcIdx = tapeStore.floatingSourceIndex else { return false }
                return srcIdx < effectiveSavedPos
            }()
            let adjustedSnapIndex = effectiveSavedPos + 1 - (floatingIsBeforeFAB ? 1 : 0)
            SnappingHScroll(itemWidth: thumbSize.width,
                           leadingInset: 16,
                           trailingInset: 16,
                           containerWidth: container.size.width,
                           targetSnapIndex: tapeStore.isFloatingClip ? nil : pendingTargetItemIndex,
                           currentSnapIndex: isNewSession ? (initialCarouselPosition + 1) : adjustedSnapIndex,
                           pendingToken: pendingToken,
                           tapeId: tape.id,
                           onSnapped: { snapIndex, _ in
                               let clipLeft = max(0, snapIndex - 1)
                               savedCarouselPosition = clipLeft
                               
                               let currentItems = items
                               let leftItemIdx = snapIndex - 1
                               let rightItemIdx = snapIndex
                               var leftID: UUID? = nil
                               var rightID: UUID? = nil
                               if leftItemIdx >= 0 && leftItemIdx < currentItems.count,
                                  case .clip(let clip) = currentItems[leftItemIdx] {
                                   leftID = clip.id
                               }
                               if rightItemIdx >= 0 && rightItemIdx < currentItems.count,
                                  case .clip(let clip) = currentItems[rightItemIdx] {
                                   rightID = clip.id
                               }
                               onSeamChanged?(leftID, rightID)
                               
                               if pendingTargetItemIndex != nil {
                                   pendingTargetItemIndex = nil
                                   pendingToken = nil
                               }
                               if isNewSession {
                                   isNewSession = false
                               }
                           },
                           isLongPressEnabled: tapeStore.jigglingTapeID == tape.id,
                           onItemLongPressStarted: { itemIndex, globalPos, globalFrame in
                               let currentItems = items
                               guard itemIndex >= 0 && itemIndex < currentItems.count,
                                     case .clip(let clip) = currentItems[itemIndex],
                                     !clip.isPlaceholder else { return false }
                               guard !tapeStore.isFloatingClip else { return false }

                               let clipIndex = tape.clips.firstIndex(where: { $0.id == clip.id }) ?? 0
                               tapeStore.liftClip(clip, fromTape: tape.id, atIndex: clipIndex, originFrame: globalFrame, thumbSize: thumbSize)
                               let gen = UIImpactFeedbackGenerator(style: .light)
                               gen.impactOccurred()
                               tapeStore.floatingPosition = globalPos
                               return true
                           },
                           onDragPositionChanged: { globalPos in
                               tapeStore.floatingPosition = globalPos
                           },
                           onDragEnded: {
                               tapeStore.floatingDragDidEnd = true
                           },
                           contentHash: tapeHash,
                           onScrollFractionChanged: onScrollFractionChanged) {
                // Leading 16pt padding INSIDE the card
                Color.clear.frame(width: 16)
                
                ForEach(items) { item in
                    JiggleableClipView(
                        item: item,
                        tapeID: tape.id,
                        thumbSize: thumbSize,
                        onPlaceholderTap: onPlaceholderTap,
                        onClipTap: onClipTap,
                        onClipDelete: onClipDelete,
                        onClipDuplicate: onClipDuplicate
                    )
                    .id(item.id)
                }
                
                // Trailing 16pt padding INSIDE the card
                Color.clear.frame(width: 16)
            }
            .id("carousel-\(tape.id)")
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
    var onClipDuplicate: ((Clip) -> Void)? = nil

    @State private var showingClipOptions = false

    private var isJiggling: Bool {
        tapeStore.jigglingTapeID == tapeID
    }

    var body: some View {
        if isJiggling, case .clip(let clip) = item, !clip.isPlaceholder {
            let seed = Double(clip.id.hashValue & 0xFF) / 255.0
            let phase = Double((clip.id.hashValue >> 8) & 0xFF) / 255.0 * .pi * 2
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate

                let rotAngle = (0.8 + seed * 0.5) * sin(time * (18.0 + seed * 7.0) + phase)
                let offsetX = (0.25 + seed * 0.25) * sin(time * (16.0 + seed * 6.0) + phase + 1.2)
                let offsetY = (0.35 + seed * 0.35) * cos(time * (17.0 + seed * 6.5) + phase + 2.4)

                ThumbnailView(
                    item: item,
                    onPlaceholderTap: onPlaceholderTap,
                    onClipTap: { _ in showingClipOptions = true },
                    tapeID: tapeID,
                    clipCount: tapeStore.getTape(by: tapeID)?.clips.count ?? 0
                )
                .frame(width: thumbSize.width, height: thumbSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .scaleEffect(0.92)
                .offset(x: offsetX, y: offsetY)
                .rotationEffect(.degrees(rotAngle))
                .confirmationDialog("Clip Options", isPresented: $showingClipOptions, titleVisibility: .hidden) {
                    Button("Duplicate Clip") {
                        onClipDuplicate?(clip)
                    }
                    Button("Delete Clip", role: .destructive) {
                        onClipDelete?(clip)
                    }
                    Button("Cancel", role: .cancel) {}
                }
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