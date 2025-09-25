import SwiftUI

struct TapeCardView: View {
    let tape: Tape
    let onSettings: () -> Void
    let onPlay: () -> Void
    let onAirPlay: () -> Void
    let onThumbnailDelete: (Clip) -> Void
    
    @StateObject private var castManager = CastManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s16) {
            // Header with title and controls
            HStack {
                // Title with edit icon
                HStack(spacing: Tokens.Space.s8) {
                    Text(tape.title)
                        .font(Tokens.Typography.title)
                        .foregroundColor(Tokens.Colors.textPrimary)
                    
                    Image(systemName: "pencil")
                        .font(Tokens.Typography.caption)
                        .foregroundColor(Tokens.Colors.textPrimary)
                }
                
                Spacer()
                
                // Action buttons
                HStack(spacing: Tokens.Space.s16) {
                    // Settings button
                    Button(action: onSettings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(Tokens.Colors.textPrimary)
                    }
                    
                    // AirPlay button (only show if available devices)
                    if castManager.hasAvailableDevices {
                        Button(action: onAirPlay) {
                            Image(systemName: "airplayvideo")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(Tokens.Colors.textPrimary)
                        }
                    }
                    
                    // Play button
                    Button(action: onPlay) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(Tokens.Colors.textPrimary)
                    }
                }
            }
            
            // Carousel with FAB
            Carousel(
                tape: tape,
                onThumbnailDelete: onThumbnailDelete
            )
        }
        .padding(Tokens.Space.s20)
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