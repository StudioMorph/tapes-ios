import SwiftUI

struct TapeCardView: View {
    let tape: Tape
    let onSettings: () -> Void
    let onPlay: () -> Void
    let onAirPlay: () -> Void
    let onThumbnailDelete: (Clip) -> Void
    
    @StateObject private var castManager = CastManager.shared
    
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
            
            // Carousel with FAB
            Carousel(
                tape: tape,
                onThumbnailDelete: onThumbnailDelete
            )
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