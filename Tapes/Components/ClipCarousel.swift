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
    
    @Binding var insertionIndex: Int
    
    @State private var gapCenters: [String: CGFloat] = [:]
    
    private var items: [CarouselItem] {
        var result: [CarouselItem] = []
        
        // Always start with startPlus
        result.append(CarouselItem(id: "startPlus", type: .startPlus, clip: nil))
        
        // Add existing clips
        for clip in tape.clips {
            result.append(CarouselItem(id: clip.id.uuidString, type: .clip, clip: clip))
        }
        
        // Add endPlus only if there are clips
        if !tape.clips.isEmpty {
            result.append(CarouselItem(id: "endPlus", type: .endPlus, clip: nil))
        }
        
        return result
    }
    
    var body: some View {
        GeometryReader { containerGeo in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(items.indices, id: \.self) { i in
                            // item
                            ThumbnailView(item: items[i])
                                .frame(width: thumbSize.width, height: thumbSize.height)
                                .background(Tokens.Colors.elevated)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .id("item-\(i)")
                            
                            // gap between i and i+1 (zero width for zero spacing)
                            if i < items.count - 1 {
                                GapMarker(width: interItem)
                                    .id("gap-\(i)")
                                    .anchorPreference(key: GapCentersKey.self, value: .bounds) { anchor in
                                        ["gap-\(i)": containerGeo[anchor].midX]
                                    }
                            }
                        }
                    }
                }
                .onPreferenceChange(GapCentersKey.self) { gapCenters = $0 }
                .gesture(
                    DragGesture().onEnded { _ in
                        snapToNearestGap(containerWidth: containerGeo.size.width, proxy: proxy)
                    }
                )
                .onAppear {
                    // start position: between startPlus and first clip (or 0 if empty)
                    snapToNearestGap(containerWidth: containerGeo.size.width, proxy: proxy)
                }
            }
        }
        .frame(height: thumbSize.height)   // lock height
    }
    
    private func snapToNearestGap(containerWidth: CGFloat, proxy: ScrollViewProxy) {
        guard !gapCenters.isEmpty else { insertionIndex = 0; return }
        let midX = containerWidth / 2
        let nearest = gapCenters.min { abs($0.value - midX) < abs($1.value - midX) }?.key
        guard let id = nearest, let idx = Int(id.replacingOccurrences(of: "gap-", with: "")) else { return }
        insertionIndex = idx
        withAnimation(.easeOut(duration: 0.22)) {
            proxy.scrollTo(id, anchor: .center)
        }
    }
}

// MARK: - Gap Marker
private struct GapMarker: View {
    let width: CGFloat
    var body: some View { Color.clear.frame(width: width, height: 1) }
}

// MARK: - Gap Centers Key
private struct GapCentersKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - Thumbnail View
private struct ThumbnailView: View {
    let item: CarouselItem
    
    var body: some View {
        switch item.type {
        case .startPlus:
            StartPlusView()
        case .clip:
            if let clip = item.clip {
                Thumbnail(
                    thumbnail: ClipThumbnail(
                        id: clip.id.uuidString,
                        assetLocalId: clip.assetLocalId,
                        index: 0, // Will be set properly by parent
                        isPlaceholder: false
                    ),
                    onDelete: { }
                )
            }
        case .endPlus:
            EndPlusView()
        }
    }
}

// MARK: - Start Plus View
struct StartPlusView: View {
    var body: some View {
        Button(action: {
            // Action for adding a new clip at the start
            print("Add new clip at start")
        }) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Tokens.Colors.elevated)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(Tokens.Colors.text)
                )
        }
    }
}

// MARK: - End Plus View
struct EndPlusView: View {
    var body: some View {
        Button(action: {
            // Action for adding a new clip at the end
            print("Add new clip at end")
        }) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Tokens.Colors.elevated)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(Tokens.Colors.text)
                )
        }
    }
}

// MARK: - Clip Thumbnail (defined in Thumbnail.swift)

// MARK: - Previews
struct ClipCarousel_Previews: PreviewProvider {
    @State static var sampleTapeWithClips = Tape.sampleTapes[0]
    @State static var sampleTapeEmpty = Tape(id: UUID(), title: "Empty Tape", clips: [])
    @State static var insertionIndex: Int = 0
    
    static var previews: some View {
        VStack {
            ClipCarousel(
                tape: sampleTapeWithClips,
                thumbSize: CGSize(width: 128, height: 128 * 9 / 16),
                interItem: 16,
                onThumbnailDelete: { _ in },
                insertionIndex: $insertionIndex
            )
            .previewLayout(.sizeThatFits)
            .preferredColorScheme(.dark)
            .padding()
            .background(Tokens.Colors.bg)
            .previewDisplayName("With Clips - Dark")
            
            ClipCarousel(
                tape: sampleTapeEmpty,
                thumbSize: CGSize(width: 128, height: 128 * 9 / 16),
                interItem: 16,
                onThumbnailDelete: { _ in },
                insertionIndex: $insertionIndex
            )
            .previewLayout(.sizeThatFits)
            .preferredColorScheme(.light)
            .padding()
            .background(Tokens.Colors.bg)
            .previewDisplayName("Empty - Light")
        }
    }
}