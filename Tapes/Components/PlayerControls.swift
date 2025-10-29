//
//  PlayerControls.swift
//  Tapes
//
//  Created by AI Assistant on 25/09/2025.
//

import SwiftUI

struct PlayerControls: View {
    let isPlaying: Bool
    let canGoBack: Bool
    let canGoForward: Bool
    let onPlayPause: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    
    var body: some View {
        HStack(spacing: 32) {
            // Previous button
            Button(action: onPrevious) {
                Image(systemName: "backward.fill")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(canGoBack ? .white : .white.opacity(0.4))
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial, in: Circle())
                    .contentShape(Circle())
            }
            .disabled(!canGoBack)
            .accessibilityLabel("Previous clip")
            .accessibilityHint("Goes to the previous clip in the tape")
            
            // Play/Pause button
            Button(action: onPlayPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(.ultraThinMaterial, in: Circle())
                    .contentShape(Circle())
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            }
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            .accessibilityHint(isPlaying ? "Pauses video playback" : "Starts video playback")
            
            // Next button
            Button(action: onNext) {
                Image(systemName: "forward.fill")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(canGoForward ? .white : .white.opacity(0.4))
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial, in: Circle())
                    .contentShape(Circle())
            }
            .disabled(!canGoForward)
            .accessibilityLabel("Next clip")
            .accessibilityHint("Goes to the next clip in the tape")
        }
        .padding(.horizontal, 20)
    }
}

#Preview {
    PlayerControls(
        isPlaying: false,
        canGoBack: true,
        canGoForward: true,
        onPlayPause: {},
        onPrevious: {},
        onNext: {}
    )
    .padding()
    .background(Color.black)
}
