import SwiftUI

struct ThumbnailView: View {
    @EnvironmentObject private var tapeStore: TapesStore
    let item: CarouselItem
    let onPlaceholderTap: (CarouselItem) -> Void
    var onClipTap: ((Clip) -> Void)? = nil
    var tapeID: UUID = UUID()
    var clipCount: Int = 0

    var body: some View {
        ZStack {
            switch item {
            case .startPlus:
                StartPlusView(tapeID: tapeID)
                    .onTapGesture {
                        guard !tapeStore.isFloatingClip else { return }
                        onPlaceholderTap(item)
                    }
            case .clip(let clip):
                ClipThumbnailView(clip: clip, tapeID: tapeID)
                    .onTapGesture {
                        onClipTap?(clip)
                    }
            case .endPlus:
                EndPlusView(tapeID: tapeID, clipCount: clipCount)
                    .onTapGesture {
                        guard !tapeStore.isFloatingClip else { return }
                        onPlaceholderTap(item)
                    }
            }
        }
    }
}

struct StartPlusView: View {
    @EnvironmentObject private var tapeStore: TapesStore
    var tapeID: UUID = UUID()

    var body: some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .global)
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

                if tapeStore.isFloatingClip && tapeStore.jigglingTapeID == tapeID {
                    dashedPhotoStackIcon()
                        .preference(key: DropTargetPreferenceKey.self, value: [
                            DropTargetInfo(tapeID: tapeID, insertionIndex: 0, seamLeftClipID: nil, seamRightClipID: nil, frame: frame, kind: .startPlus)
                        ])
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(Tokens.Colors.primaryText)
                }
            }
        }
    }
}

struct EndPlusView: View {
    @EnvironmentObject private var tapeStore: TapesStore
    var tapeID: UUID = UUID()
    var clipCount: Int = 0

    var body: some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .global)
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

                if tapeStore.isFloatingClip && tapeStore.jigglingTapeID == tapeID {
                    dashedPhotoStackIcon()
                        .preference(key: DropTargetPreferenceKey.self, value: [
                            DropTargetInfo(tapeID: tapeID, insertionIndex: clipCount, seamLeftClipID: nil, seamRightClipID: nil, frame: frame, kind: .endPlus)
                        ])
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(Tokens.Colors.primaryText)
                }
            }
        }
    }
}

private func dashedPhotoStackIcon() -> some View {
    ZStack {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .strokeBorder(Tokens.Colors.primaryText.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .frame(width: 28, height: 28)
        Image(systemName: "photo.stack")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(Tokens.Colors.primaryText)
    }
}

struct ClipThumbnailView: View {
    @EnvironmentObject private var tapeStore: TapesStore
    let clip: Clip
    var tapeID: UUID = UUID()

    private var isJiggling: Bool {
        tapeStore.jigglingTapeID == tapeID
    }

    private var tapeLivePhotosAsVideo: Bool {
        tapeStore.tapes.first(where: { $0.id == tapeID })?.livePhotosAsVideo ?? true
    }
    
    private var livePhotoState: String {
        guard clip.isLivePhoto else { return "" }
        let effective = clip.shouldPlayAsLiveVideo(tapeDefault: tapeLivePhotosAsVideo)
        let override = clip.livePhotoAsVideo.map { "\($0)" } ?? "nil"
        return "-lp\(effective)-ov\(override)"
    }

    var body: some View {
        ResolvedClipThumbnail(clip: clip, isJiggling: isJiggling, livePhotosAsVideo: tapeLivePhotosAsVideo)
            .id("clip-\(clip.id)-\(clip.hasThumbnail)-\(clip.updatedAt.timeIntervalSinceReferenceDate)\(livePhotoState)")
    }
}

private struct ResolvedClipThumbnail: View {
    let clip: Clip
    var isJiggling: Bool = false
    var livePhotosAsVideo: Bool = true

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
            
            if isJiggling {
                ClipBadgePill {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                }
            } else {
                ClipInfoBadge(clip: clip, livePhotosAsVideo: livePhotosAsVideo)
            }
        }
        .overlay(alignment: .topTrailing) {
            Text(clip.hasThumbnail ? "thumb" : "no thumb")
                .font(.caption2)
                .opacity(0.001)
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

struct ClipInfoBadge: View {
    let clip: Clip
    var livePhotosAsVideo: Bool = true

    private var isLiveVideoActive: Bool {
        clip.shouldPlayAsLiveVideo(tapeDefault: livePhotosAsVideo)
    }

    private var icon: String {
        if clip.isLivePhoto && isLiveVideoActive { return "livephoto.play" }
        if clip.isLivePhoto { return "livephoto" }
        return clip.clipType == .image ? "photo" : "play.rectangle"
    }

    private var iconColor: Color {
        if clip.isLivePhoto && isLiveVideoActive { return .yellow }
        return .white
    }

    private var displayDuration: TimeInterval {
        if clip.clipType == .image {
            return clip.imageDuration
        }
        return clip.isTrimmed ? clip.trimmedDuration : clip.duration
    }

    var body: some View {
        ClipBadgePill {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(iconColor)

            if clip.isLivePhoto && isLiveVideoActive {
                Text("Live")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
            } else {
                Text(formatDuration(displayDuration))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
            }

            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.blue)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return String(format: "%ds", Int(duration))
        }
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
