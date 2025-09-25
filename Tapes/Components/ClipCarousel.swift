import SwiftUI

// MARK: - Carousel Item
struct CarouselItem: Identifiable {
    let id: String
    let type: ItemType
    let clip: Clip?
    
    enum ItemType {
        case startPlus
        case clip
        case endPlus
    }
}

// MARK: - Clip Carousel
struct ClipCarousel: View {
    let tape: Tape
    let thumbSize: CGSize
    let interItem: CGFloat
    let onThumbnailDelete: (Clip) -> Void
    
    @State private var insertionIndex: Int = 0
    
    private var items: [CarouselItem] {
        var result: [CarouselItem] = []
        
        // Always start with startPlus
        result.append(CarouselItem(id: "item-0", type: .startPlus, clip: nil))
        
        // Add clips
        for (index, clip) in tape.clips.enumerated() {
            result.append(CarouselItem(id: "item-\(index + 1)", type: .clip, clip: clip))
        }
        
        // Add endPlus only if there are clips
        if !tape.clips.isEmpty {
            result.append(CarouselItem(id: "item-\(tape.clips.count + 1)", type: .endPlus, clip: nil))
        }
        
        return result
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: interItem) {
                ForEach(items) { item in
                    itemView(for: item)
                }
            }
            .padding(.horizontal, 16) // Container padding
        }
    }
    
    @ViewBuilder
    private func itemView(for item: CarouselItem) -> some View {
        switch item.type {
        case .startPlus:
            StartPlusView()
                .frame(width: thumbSize.width, height: thumbSize.height)
        case .clip:
            if let clip = item.clip {
                Thumbnail(
                    thumbnail: ClipThumbnail(
                        id: clip.id.uuidString,
                        assetLocalId: clip.assetLocalId,
                        index: tape.clips.firstIndex(where: { $0.id == clip.id }) ?? 0,
                        isPlaceholder: false
                    ),
                    onDelete: { onThumbnailDelete(clip) }
                )
                .frame(width: thumbSize.width, height: thumbSize.height)
            }
        case .endPlus:
            EndPlusView()
                .frame(width: thumbSize.width, height: thumbSize.height)
        }
    }
}

// MARK: - Start Plus View
struct StartPlusView: View {
    var body: some View {
        Button(action: {
            // Handle start plus tap
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Tokens.Colors.elevated)
                    .frame(width: 100, height: 100)
                
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(Tokens.Colors.text)
            }
        }
    }
}

// MARK: - End Plus View
struct EndPlusView: View {
    var body: some View {
        Button(action: {
            // Handle end plus tap
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Tokens.Colors.elevated)
                    .frame(width: 100, height: 100)
                
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(Tokens.Colors.text)
            }
        }
    }
}

// MARK: - Record FAB
struct RecordFAB: View {
    var body: some View {
        Button(action: {
            // Handle record action
        }) {
            ZStack {
                Circle()
                    .fill(Tokens.Colors.brandRed)
                    .frame(width: 64, height: 64)
                    .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
                
                Image(systemName: "video.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(Tokens.Colors.onAccent)
            }
        }
    }
}

// MARK: - Preview
#Preview("Empty Tape") {
    ClipCarousel(
        tape: Tape(title: "Empty Tape", clips: []),
        thumbSize: CGSize(width: 128, height: 72),
        interItem: 16,
        onThumbnailDelete: { _ in }
    )
    .frame(height: 100)
    .background(Tokens.Colors.surface)
}

#Preview("With Clips") {
    ClipCarousel(
        tape: Tape.sampleTapes[1],
        thumbSize: CGSize(width: 128, height: 72),
        interItem: 16,
        onThumbnailDelete: { _ in }
    )
    .frame(height: 100)
    .background(Tokens.Colors.surface)
}
