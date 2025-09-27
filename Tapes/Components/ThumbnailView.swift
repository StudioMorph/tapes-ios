import SwiftUI

struct ThumbnailView: View {
    let item: CarouselItem
    let onPlaceholderTap: (CarouselItem) -> Void
    
    var body: some View {
        let _ = print("🖼️ ThumbnailView rendering: \(item.id)")
        ZStack {
            switch item {
            case .startPlus:
                StartPlusView()
                    .onTapGesture {
                        onPlaceholderTap(item)
                    }
            case .clip(let clip):
                ClipThumbnailView(clip: clip)
            case .endPlus:
                EndPlusView()
                    .onTapGesture {
                        onPlaceholderTap(item)
                    }
            }
        }
    }
}

struct StartPlusView: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Tokens.Colors.elevated)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: Tokens.Radius.thumb,
                        bottomLeadingRadius: Tokens.Radius.thumb,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                )
            
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(Tokens.Colors.onSurface)
        }
    }
}

struct EndPlusView: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Tokens.Colors.elevated)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: Tokens.Radius.thumb,
                        topTrailingRadius: Tokens.Radius.thumb
                    )
                )
            
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(Tokens.Colors.onSurface)
        }
    }
}

struct ClipThumbnailView: View {
    let clip: Clip
    
    var body: some View {
        let _ = print("🎬 ClipThumbnailView rendering: id=\(clip.id), type=\(clip.clipType), hasThumb=\(clip.thumbnail != nil)")
        ZStack {
            // Thumbnail background - square corners
            Rectangle()
                .fill(Tokens.Colors.elevated)
            
            // Actual thumbnail or placeholder
            if let thumbnail = clip.thumbnailImage {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else {
                // Non-intrusive skeleton (colors from tokens)
                RoundedRectangle(cornerRadius: Tokens.Radius.thumb)
                    .fill(Tokens.Colors.elevated)
                    .overlay {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Tokens.Colors.onSurface)
                    }
            }
            
            // Duration badge in bottom-right corner
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    DurationBadge(duration: clip.duration)
                }
            }
            .padding(8)
        }
        .overlay(alignment: .topTrailing) {
            Text(clip.thumbnail == nil ? "no thumb" : "thumb")
                .font(.caption2)
                .opacity(0.001) // keep essentially invisible; remove later
        }
    }
}

struct ClipBadge: View {
    let count: Int
    
    var body: some View {
        Text("\(count)")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(Tokens.Colors.onSurface)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Tokens.Colors.red)
            )
    }
}

struct DurationBadge: View {
    let duration: TimeInterval
    
    var body: some View {
        Text(formatDuration(duration))
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.7))
            )
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    HStack(spacing: 0) {
        ThumbnailView(item: .startPlus, onPlaceholderTap: { _ in })
            .frame(width: 150, height: 84)
        
        ThumbnailView(item: .clip(Clip(id: UUID(), assetLocalId: "test", duration: 5.0, rotateQuarterTurns: 0, overrideScaleMode: nil, createdAt: Date(), updatedAt: Date())), onPlaceholderTap: { _ in })
            .frame(width: 150, height: 84)
        
        ThumbnailView(item: .endPlus, onPlaceholderTap: { _ in })
            .frame(width: 150, height: 84)
    }
    .background(Tokens.Colors.bg)
}
