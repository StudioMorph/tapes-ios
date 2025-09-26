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
            // Header section with padding
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
            .padding(.horizontal, Tokens.Space.xl)
            .padding(.top, 16)
            
            // Carousel section - 16pt margin from screen edges
            GeometryReader { geometry in
                let screenW = UIScreen.main.bounds.width
                let thumbW = floor((screenW - 64 - 32) / 2) // 32pt for 16pt margins on both sides
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
                        interItem: 0,
                        onThumbnailDelete: onThumbnailDelete,
                        insertionIndex: $insertionIndex
                    )
                    .frame(height: thumbH)
                    
                    // 3. FAB (above)
                    FAB { _ in }
                        .frame(width: 64, height: 64)
                }
                .frame(height: thumbH)
                .clipped()
                .padding(.horizontal, 16) // 16pt margin from screen edges
            }
            .frame(height: nil)
            .padding(.bottom, 16)
        }
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