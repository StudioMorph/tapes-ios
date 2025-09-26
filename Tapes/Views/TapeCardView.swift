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
            // Title row
            HStack {
                // Title with edit icon
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.s) {
                    Text(tape.title)
                        .font(Tokens.Typography.title)
                        .foregroundColor(Tokens.Colors.onSurface)
                        .alignmentGuide(.firstTextBaseline) { d in d[.firstTextBaseline] }
                    
                    Image(systemName: "pencil")
                        .font(Tokens.Typography.title)
                        .foregroundColor(Tokens.Colors.onSurface)
                        .alignmentGuide(.firstTextBaseline) { d in d[.firstTextBaseline] }
                }
                
                Spacer()
                
                // Action buttons with 16pt spacing
                HStack(spacing: Tokens.Spacing.m) {
                    // Settings button
                    Button(action: onSettings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(Tokens.Colors.onSurface)
                    }
                    
                    // AirPlay button (only show if available devices)
                    if castManager.hasAvailableDevices {
                        Button(action: onAirPlay) {
                            Image(systemName: "airplayvideo")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(Tokens.Colors.onSurface)
                        }
                    }
                    
                    // Play button
                    Button(action: onPlay) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(Tokens.Colors.onSurface)
                    }
                }
            }
            .padding(.horizontal, Tokens.Spacing.m)
            .padding(.top, Tokens.Spacing.m)
            
            // Timeline container
            let screenW = UIScreen.main.bounds.width
            let thumbW = floor((screenW - Tokens.FAB.size) / 2.0)
            let thumbH = floor(thumbW * 9.0 / 16.0)
            
            ZStack(alignment: .center) {
                // 1) Thumbnails / scrollable carousel
                ClipCarousel(
                    tape: tape,
                    thumbSize: CGSize(width: thumbW, height: thumbH),
                    insertionIndex: $insertionIndex
                )
                .zIndex(0) // always behind the line and FAB
                
                // 2) Red center line (between clips and FAB)
                Rectangle()
                    .fill(Tokens.Colors.red.opacity(0.9))
                    .frame(width: 2, height: thumbH)
                    .allowsHitTesting(false)
                    .zIndex(1) // above thumbnails, below FAB
                
                // 3) Floating action button (camera)
                FAB { _ in }
                    .frame(width: Tokens.FAB.size, height: Tokens.FAB.size)
                    .zIndex(2) // on top of everything
            }
            .frame(height: thumbH)
            .padding(.vertical, Tokens.Spacing.m)
        }
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .fill(Tokens.Colors.card)
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