import SwiftUI

struct ThumbnailView: View {
    let item: CarouselItem
    
    var body: some View {
        ZStack {
            switch item {
            case .startPlus:
                StartPlusView()
            case .clip(let clip):
                ClipThumbnailView(clip: clip)
            case .endPlus:
                EndPlusView()
            }
        }
    }
}

struct StartPlusView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Tokens.Radius.thumb)
                .fill(Tokens.Colors.elevated)
            
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(Tokens.Colors.onSurface)
        }
    }
}

struct EndPlusView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Tokens.Radius.thumb)
                .fill(Tokens.Colors.elevated)
            
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(Tokens.Colors.onSurface)
        }
    }
}

struct ClipThumbnailView: View {
    let clip: Clip
    
    var body: some View {
        ZStack {
            // Thumbnail background
            RoundedRectangle(cornerRadius: Tokens.Radius.thumb)
                .fill(Tokens.Colors.elevated)
            
            // Placeholder content (replace with actual thumbnail)
            VStack {
                Image(systemName: "video")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Tokens.Colors.onSurface)
                
                Text("\(clip.assetLocalId)")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Tokens.Colors.onSurface)
            }
            
            // Clip count badge in top-right corner
            if clip.id.hashValue % 3 == 0 { // Show badge for some clips as example
                VStack {
                    HStack {
                        Spacer()
                        ClipBadge(count: clip.id.hashValue % 10)
                    }
                    Spacer()
                }
                .offset(x: -8, y: 8)
            }
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

#Preview {
    HStack(spacing: 0) {
        ThumbnailView(item: .startPlus)
            .frame(width: 150, height: 84)
        
        ThumbnailView(item: .clip(Clip(id: UUID(), assetLocalId: "test", rotateQuarterTurns: 0, overrideScaleMode: nil, createdAt: Date(), updatedAt: Date())))
            .frame(width: 150, height: 84)
        
        ThumbnailView(item: .endPlus)
            .frame(width: 150, height: 84)
    }
    .background(Tokens.Colors.bg)
}
