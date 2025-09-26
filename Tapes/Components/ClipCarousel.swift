import SwiftUI

struct ClipCarousel: View {
    let tape: Tape
    let thumbSize: CGSize
    @Binding var insertionIndex: Int
    
    @State private var centers: [Int: CGFloat] = [:]
    @State private var widths: [Int: CGFloat] = [:]
    
    var items: [CarouselItem] {
        if tape.clips.isEmpty {
            return [.startPlus]
        } else {
            return [.startPlus] + tape.clips.map { .clip($0) } + [.endPlus]
        }
    }
    
    var body: some View {
        GeometryReader { container in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {                        // ZERO GAP
                        ForEach(items.indices, id: \.self) { i in
                            ThumbnailView(item: items[i])
                                .frame(width: thumbSize.width, height: thumbSize.height)
                                .background(Tokens.Colors.elevated)
                                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.thumb))
                                .background(GeometryReader { g in
                                    let f = g.frame(in: .named("carousel"))
                                    Color.clear
                                        .preference(key: ItemCentersKey.self, value: [i: f.midX])
                                        .preference(key: ItemWidthsKey.self, value: [i: f.size.width])
                                })
                                .id("item-\(i)")
                        }
                    }
                    .coordinateSpace(name: "carousel")
                }
                .onPreferenceChange(ItemCentersKey.self) { centers.merge($0, uniquingKeysWith: { _, new in new }) }
                .onPreferenceChange(ItemWidthsKey.self) { widths.merge($0, uniquingKeysWith: { _, new in new }) }
                .gesture(DragGesture().onEnded { _ in snap(container: container.size, proxy: proxy) })
                .onAppear { snap(container: container.size, proxy: proxy) }
            }
        }
        .frame(height: thumbSize.height) // hug
    }
    
    private func snap(container: CGSize, proxy: ScrollViewProxy) {
        guard !centers.isEmpty, !widths.isEmpty else { insertionIndex = 0; return }
        let midX = container.width / 2
        // trailing edge of item i = centers[i] + widths[i]/2
        let trailing = centers.compactMap { (i, cx) -> (Int, CGFloat)? in
            guard let w = widths[i] else { return nil }
            return (i, cx + w/2)
        }
        guard let best = trailing.min(by: { abs($0.1 - midX) < abs($1.1 - midX) }) else { return }
        insertionIndex = best.0 // gap is between i and i+1
        withAnimation(.easeOut(duration: 0.22)) {
            proxy.scrollTo("item-\(best.0)", anchor: .trailing)
        }
    }
}

struct ItemCentersKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, n in n })
    }
}

struct ItemWidthsKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, n in n })
    }
}

enum CarouselItem {
    case startPlus
    case clip(Clip)
    case endPlus
}

#Preview {
    VStack {
        ClipCarousel(
            tape: Tape.sampleTapes[0],
            thumbSize: CGSize(width: 150, height: 84),
            insertionIndex: .constant(0)
        )
        .frame(height: 84)
        .background(Color.gray.opacity(0.3))
    }
    .padding()
    .background(Tokens.Colors.bg)
}