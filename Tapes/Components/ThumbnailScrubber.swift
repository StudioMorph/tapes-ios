import SwiftUI
import AVFoundation

/// Phase 3: Thumbnail scrubber for precise seeking
struct ThumbnailScrubber: View {
    let currentTime: Double
    let totalDuration: Double
    let thumbnails: [(time: Double, image: UIImage)] // Sorted by time
    let onSeek: (Double) -> Void
    
    @State private var isDragging = false
    @State private var dragTime: Double?
    @State private var previewTime: Double?
    
    var body: some View {
        VStack(spacing: 8) {
            // Preview thumbnail
            if let previewTime = previewTime ?? dragTime, let thumbnail = thumbnailForTime(previewTime) {
                Image(uiImage: thumbnail.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 90)
                    .cornerRadius(8)
                    .shadow(radius: 4)
            }
            
            // Scrubber bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track with thumbnails
                    HStack(spacing: 0) {
                        ForEach(Array(thumbnails.enumerated()), id: \.offset) { index, item in
                            Image(uiImage: item.image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geometry.size.width / CGFloat(thumbnails.count), height: geometry.size.height)
                                .clipped()
                            
                            if index < thumbnails.count - 1 {
                                // Transition indicator
                                Rectangle()
                                    .fill(.white.opacity(0.3))
                                    .frame(width: 2)
                            }
                        }
                    }
                    .opacity(0.6)
                    
                    // Progress overlay
                    Rectangle()
                        .fill(.black.opacity(0.3))
                        .frame(width: geometry.size.width * progressFraction, height: geometry.size.height)
                    
                    // Progress indicator
                    Circle()
                        .fill(.white)
                        .frame(width: 12, height: 12)
                        .shadow(radius: 2)
                        .offset(x: geometry.size.width * progressFraction - 6)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let progress = max(0, min(1, value.location.x / geometry.size.width))
                            let seekTime = totalDuration * Double(progress)
                            dragTime = seekTime
                            previewTime = seekTime
                        }
                        .onEnded { _ in
                            if let dragTime = dragTime {
                                onSeek(dragTime)
                            }
                            isDragging = false
                            dragTime = nil
                            previewTime = nil
                        }
                )
            }
            .frame(height: 60)
            
            // Time labels
            HStack {
                Text(formatTime(dragTime ?? currentTime))
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(.white)
                
                Spacer()
                
                Text(formatTime(totalDuration))
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(.white)
            }
        }
    }
    
    private var progressFraction: CGFloat {
        guard totalDuration > 0 else { return 0 }
        let time = dragTime ?? currentTime
        return CGFloat(time / totalDuration)
    }
    
    private func thumbnailForTime(_ time: Double) -> (time: Double, image: UIImage)? {
        // Find closest thumbnail
        guard !thumbnails.isEmpty else { return nil }
        
        var closest = thumbnails[0]
        var minDiff = abs(closest.time - time)
        
        for item in thumbnails {
            let diff = abs(item.time - time)
            if diff < minDiff {
                minDiff = diff
                closest = item
            }
        }
        
        return closest
    }
    
    private func formatTime(_ time: Double) -> String {
        guard time.isFinite else { return "0:00" }
        let clamped = max(0, time)
        let minutes = Int(clamped) / 60
        let seconds = Int(clamped) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

