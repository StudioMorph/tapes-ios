//
//  PlayerProgressBar.swift
//  Tapes
//
//  Created by AI Assistant on 25/09/2025.
//

import SwiftUI

struct PlayerProgressBar: View {
    let currentTime: Double
    let totalDuration: Double
    let onSeek: (Double) -> Void
    
    private var progressFraction: CGFloat {
        guard totalDuration > 0 else { return 0 }
        return CGFloat(currentTime / totalDuration)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white.opacity(0.3))
                        .frame(height: 6)
                    
                    // Progress track
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white)
                        .frame(width: geometry.size.width * progressFraction, height: 6)
                        .shadow(color: .white.opacity(0.5), radius: 2, x: 0, y: 0)
                    
                    // Progress handle
                    Circle()
                        .fill(.white)
                        .frame(width: 16, height: 16)
                        .offset(x: geometry.size.width * progressFraction - 8)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let progress = max(0, min(1, value.location.x / geometry.size.width))
                            onSeek(totalDuration * progress)
                        }
                )
            }
            .frame(height: 16)
            
            // Time labels
            HStack {
                Text(formatTime(currentTime))
                    .font(Tokens.Typography.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
                
                Spacer()
                
                Text(formatTime(totalDuration))
                    .font(Tokens.Typography.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
            }
        }
    }
    
    private func formatTime(_ time: Double) -> String {
        guard time.isFinite else { return "0:00" }
        let clamped = max(0, time)
        let minutes = Int(clamped) / 60
        let seconds = Int(clamped) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    PlayerProgressBar(
        currentTime: 45.0,
        totalDuration: 120.0,
        onSeek: { _ in }
    )
    .padding()
    .background(Color.black)
}
