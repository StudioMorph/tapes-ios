import SwiftUI

struct ThumbnailView: View {
    let item: CarouselItem
    let onPlaceholderTap: (CarouselItem) -> Void
    
    var body: some View {
        ZStack {
            switch item {
            case .startPlus:
                StartPlusView()
                    .onTapGesture {
                        onPlaceholderTap(item)
                    }
            case .clip(let clip):
                ClipThumbnailView(clip: clip)
                    .onTapGesture {
                        // TODO: This should open the TapePlayerView, not play individual videos
                    }
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
                .fill(Tokens.Colors.tertiaryBackground)
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
                .foregroundColor(Tokens.Colors.primaryText)
        }
    }
}

struct EndPlusView: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Tokens.Colors.tertiaryBackground)
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
                .foregroundColor(Tokens.Colors.primaryText)
        }
    }
}

struct ClipThumbnailView: View {
    @EnvironmentObject private var tapeStore: TapesStore
    let clip: Clip
    
    var body: some View {
        Group {
            if clip.isPlaceholder {
                PlaceholderClipView(state: tapeStore.clipLoadingStates[clip.id])
            } else {
                ResolvedClipThumbnail(clip: clip)
            }
        }
        .id("clip-\(clip.id)-\(clip.thumbnail != nil)-\(clip.isPlaceholder)")
    }
}

private struct ResolvedClipThumbnail: View {
    let clip: Clip
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Tokens.Colors.elevated)
            
            if let thumbnail = clip.thumbnailImage {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: Tokens.Radius.thumb)
                    .fill(Tokens.Colors.elevated)
                    .overlay {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Tokens.Colors.onSurface)
                    }
            }
            
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    DurationBadge(duration: clip.duration)
                        .opacity(clip.duration > 0 ? 1 : 0)
                }
            }
            .padding(8)
        }
        .overlay(alignment: .topTrailing) {
            Text(clip.thumbnail == nil ? "no thumb" : "thumb")
                .font(.caption2)
                .opacity(0.001)
        }
    }
}

private struct PlaceholderClipView: View {
    let state: ClipLoadingState?
    
    private var statusText: String {
        guard let state else { return "Queued" }
        switch state.phase {
        case .queued:
            return "Queued"
        case .transferring:
            return "Loading…"
        case .processing:
            return "Processing…"
        case .ready:
            return "Ready"
        case .error(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Failed" : trimmed
        }
    }
    
    private var isError: Bool {
        guard let state else { return false }
        if case .error = state.phase {
            return true
        }
        return false
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Tokens.Radius.thumb)
                .fill(Tokens.Colors.tertiaryBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Radius.thumb)
                        .strokeBorder(isError ? Color.red : Tokens.Colors.primaryText.opacity(0.1), lineWidth: 1)
                )
            VStack(spacing: 8) {
                if isError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.yellow)
                } else {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(Tokens.Colors.primaryText)
                }
                Text(statusText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Tokens.Colors.primaryText)
            }
            .padding(12)
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
    .background(Tokens.Colors.primaryBackground)
    .environmentObject(TapesStore())
}
