import SwiftUI

struct TapeCardView: View {
    let tape: Tape
    let onSettings: () -> Void
    let onPlay: () -> Void
    let onAirPlay: () -> Void
    let onThumbnailDelete: (Clip) -> Void
    
    @StateObject private var castManager = CastManager.shared
    @State private var insertionIndex: Int = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with title and controls - with card padding
            VStack(alignment: .leading, spacing: Tokens.Space.l) {
                HStack {
                    // Title with edit icon
                    HStack(spacing: Tokens.Space.s) {
                        Text(tape.title)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Tokens.Colors.text)
                        
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(Tokens.Colors.text)
                    }
                    
                    Spacer()
                    
                    // Action buttons
                    HStack(spacing: Tokens.Space.l) {
                        // Settings button
                        Button(action: onSettings) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(Tokens.Colors.text)
                        }
                        
                        // AirPlay button (only show if available devices)
                        if castManager.hasAvailableDevices {
                            Button(action: onAirPlay) {
                                Image(systemName: "airplayvideo")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(Tokens.Colors.text)
                            }
                        }
                        
                        // Play button
                        Button(action: onPlay) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(Tokens.Colors.text)
                        }
                    }
                }
            }
            .padding(Tokens.Space.xl)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.card)
                    .fill(Tokens.Colors.surface)
            )
            
            // Dynamic carousel with FAB and centerline - NO card padding, full width
            GeometryReader { geometry in
                let screenW = UIScreen.main.bounds.width
                let thumbW = floor((screenW - 64) / 2)
                let thumbH = floor(thumbW * 9.0 / 16.0)
                
                ZStack(alignment: .center) {
                    // 1. Centerline
                    Rectangle()
                        .fill(Tokens.Colors.brandRed.opacity(0.9))
                        .frame(width: 2)
                        .frame(height: thumbH)
                        .allowsHitTesting(false)
                    
                    // 2. ClipCarousel (beneath)
                    ClipCarousel(
                        tape: tape,
                        thumbSize: CGSize(width: thumbW, height: thumbH),
                        interItem: 0, // Zero spacing - thumbnails sit directly side by side
                        onThumbnailDelete: onThumbnailDelete,
                        insertionIndex: $insertionIndex
                    )
                    .frame(height: thumbH)
                    
                    // 3. FAB (above) - vertically centered between thumbnails
                    FAB { _ in }
                        .frame(width: 64, height: 64)
                }
                .frame(height: thumbH)  // Container height hugs content
                .clipped()
            }
            .frame(height: nil)  // Remove fixed height constraint
            .padding(.vertical, 16)     // Card hugs content: title + 16 + thumbnails + 16
        }
    }
}

#Preview("Dark Mode") {
    TapeCardView(
        tape: Tape.sampleTapes[0],
        onSettings: {},
        onPlay: {},
        onAirPlay: {},
        onThumbnailDelete: { _ in }
    )
    .preferredColorScheme(.dark)
    .padding()
    .background(Tokens.Colors.bg)
}

#Preview("Light Mode") {
    TapeCardView(
        tape: Tape.sampleTapes[0],
        onSettings: {},
        onPlay: {},
        onAirPlay: {},
        onThumbnailDelete: { _ in }
    )
    .preferredColorScheme(.light)
    .padding()
    .background(Tokens.Colors.bg)
}