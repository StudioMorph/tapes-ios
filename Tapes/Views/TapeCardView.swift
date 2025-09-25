import SwiftUI

// MARK: - Tape Card View

public struct TapeCardView: View {
    let tape: Tape
    let onSettings: () -> Void
    let onPlay: () -> Void
    let onAirPlay: () -> Void
    let onThumbnailTap: (ClipThumbnail) -> Void
    let onThumbnailLongPress: (ClipThumbnail) -> Void
    let onThumbnailDelete: (ClipThumbnail) -> Void
    let onFABAction: (FABMode) -> Void
    
    @StateObject private var castManager = CastManager.shared
    @State private var showingClipEditSheet = false
    @State private var selectedClip: ClipThumbnail?
    
    public init(
        tape: Tape,
        onSettings: @escaping () -> Void,
        onPlay: @escaping () -> Void,
        onAirPlay: @escaping () -> Void,
        onThumbnailTap: @escaping (ClipThumbnail) -> Void,
        onThumbnailLongPress: @escaping (ClipThumbnail) -> Void,
        onThumbnailDelete: @escaping (ClipThumbnail) -> Void,
        onFABAction: @escaping (FABMode) -> Void
    ) {
        self.tape = tape
        self.onSettings = onSettings
        self.onPlay = onPlay
        self.onAirPlay = onAirPlay
        self.onThumbnailTap = onThumbnailTap
        self.onThumbnailLongPress = onThumbnailLongPress
        self.onThumbnailDelete = onThumbnailDelete
        self.onFABAction = onFABAction
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header with title and controls
            HStack {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.s4) {
                    Text(tape.title)
                        .font(DesignTokens.Typography.title)
                        .foregroundColor(DesignTokens.Colors.onSurface(.light))
                        .lineLimit(1)
                    
                    Text("\(tape.clipCount) clips • \(formatDuration(tape.duration))")
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(DesignTokens.Colors.muted(60))
                }
                
                Spacer()
                
                // Control buttons
                HStack(spacing: DesignTokens.Spacing.s12) {
                    // Settings button
                    Button(action: onSettings) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(DesignTokens.Colors.muted(60))
                    }
                    
                    // AirPlay button (only show if available devices)
                    if castManager.hasAvailableDevices {
                        Button(action: onAirPlay) {
                            Image(systemName: "airplayvideo")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(DesignTokens.Colors.muted(60))
                        }
                    }
                    
                    // Play button
                    Button(action: onPlay) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(DesignTokens.Colors.primaryRed)
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.s20)
            .padding(.top, DesignTokens.Spacing.s16)
            
            // Carousel with FAB
            GeometryReader { geometry in
                Carousel(
                    tape: tape,
                    screenWidth: geometry.size.width,
                    onThumbnailTap: { thumbnail in
                        if !thumbnail.isPlaceholder {
                            selectedClip = thumbnail
                            showingClipEditSheet = true
                        } else {
                            onFABAction(.camera)
                        }
                    },
                    onThumbnailLongPress: { thumbnail in
                        onThumbnailLongPress(thumbnail)
                    },
                    onThumbnailDelete: { thumbnail in
                        onThumbnailDelete(thumbnail)
                    },
                    onFABAction: onFABAction
                )
                .frame(height: 120) // Fixed height for carousel
            }
            .padding(.horizontal, DesignTokens.Spacing.s20)
            .padding(.vertical, DesignTokens.Spacing.s16)
        }
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .fill(DesignTokens.Colors.surface(.light))
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
        .sheet(isPresented: $showingClipEditSheet) {
            if let selectedClip = selectedClip {
                ClipEditSheet(
                    thumbnail: selectedClip,
                    onAction: { action in
                        handleClipEditAction(action, for: selectedClip)
                    },
                    onDismiss: {
                        showingClipEditSheet = false
                        self.selectedClip = nil
                    }
                )
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func handleClipEditAction(_ action: ClipEditAction, for thumbnail: ClipThumbnail) {
        switch action {
        case .trim:
            // TODO: Implement trim functionality
            print("Trim clip: \(thumbnail.id)")
        case .rotate:
            // TODO: Implement rotate functionality
            print("Rotate clip: \(thumbnail.id)")
        case .fitFill:
            // TODO: Implement fit/fill functionality
            print("Toggle fit/fill for clip: \(thumbnail.id)")
        case .share:
            // TODO: Implement share functionality
            print("Share clip: \(thumbnail.id)")
        case .remove:
            // TODO: Implement remove functionality
            print("Remove clip: \(thumbnail.id)")
        }
    }
}

// MARK: - Preview

struct TapeCardView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleTape = Tape(
            title: "My First Tape",
            clips: [
                Clip(assetLocalId: "sample1"),
                Clip(assetLocalId: "sample2")
            ]
        )
        
        TapeCardView(
            tape: sampleTape,
            onSettings: { print("Settings tapped") },
            onPlay: { print("Play tapped") },
            onAirPlay: { print("AirPlay tapped") },
            onThumbnailTap: { thumbnail in
                print("Thumbnail tapped: \(thumbnail.id)")
            },
            onThumbnailLongPress: { thumbnail in
                print("Thumbnail long pressed: \(thumbnail.id)")
            },
            onThumbnailDelete: { thumbnail in
                print("Thumbnail delete: \(thumbnail.id)")
            },
            onFABAction: { mode in
                print("FAB action: \(mode)")
            }
        )
        .padding()
        .background(DesignTokens.Colors.muted(10))
        .previewDisplayName("Tape Card")
    }
}
