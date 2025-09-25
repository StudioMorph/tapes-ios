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
        VStack(alignment: .leading, spacing: Tokens.Space.l) {
            // Header with title and controls
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
            
            // Carousel with FAB and centerline
            GeometryReader { geometry in
                let outerHPad: CGFloat = 16     // left/right inside the card
                let fabDiameter: CGFloat = 64
                let interItem: CGFloat = 16
                let usable = geometry.size.width - (outerHPad * 2)
                // two thumbnails plus one inter-item gap share space with the FAB visually occupying fabDiameter
                let thumbW = max((usable - fabDiameter - interItem) / 2, 128)
                let thumbH = thumbW * 9.0 / 16.0
                let carouselH = thumbH           // do NOT add extra vertical padding
                
                ZStack(alignment: .center) {
                    // 1. Centerline
                    Rectangle()
                        .fill(Tokens.Colors.brandRed.opacity(0.9))
                        .frame(width: 2)
                        .frame(height: carouselH)
                        .allowsHitTesting(false)
                    
                    // 2. ClipCarousel (beneath)
                    ClipCarousel(
                        tape: tape,
                        thumbSize: CGSize(width: thumbW, height: thumbH),
                        interItem: interItem,
                        onThumbnailDelete: onThumbnailDelete,
                        insertionIndex: $insertionIndex
                    )
                    .frame(height: carouselH)
                    
                    // 3. FAB (above)
                    FAB { _ in }
                        .frame(width: fabDiameter, height: fabDiameter)
                }
                .frame(height: carouselH)
                .clipped()                // prevent overflow
                .padding(.horizontal, outerHPad)
            }
        }
        .padding(Tokens.Space.xl)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .fill(Tokens.Colors.surface)
        )
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