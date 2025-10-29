//
//  PlayerHeader.swift
//  Tapes
//
//  Created by AI Assistant on 25/09/2025.
//

import SwiftUI

struct PlayerHeader: View {
    let currentClipIndex: Int
    let totalClips: Int
    let onDismiss: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .contentShape(Circle())
            }
            .accessibilityLabel("Close player")
            .accessibilityHint("Dismisses the video player")
            
            Spacer()
            
            Text("\(currentClipIndex + 1) of \(totalClips)")
                .font(Tokens.Typography.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

#Preview {
    PlayerHeader(
        currentClipIndex: 2,
        totalClips: 5,
        onDismiss: {}
    )
    .background(Color.black)
}
