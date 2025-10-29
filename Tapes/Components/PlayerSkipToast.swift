//
//  PlayerSkipToast.swift
//  Tapes
//
//  Created by AI Assistant on 25/09/2025.
//

import SwiftUI

struct PlayerSkipToast: View {
    let skippedCount: Int
    let isVisible: Bool
    
    var body: some View {
        VStack {
            Spacer()
            
            if isVisible {
                HStack(spacing: 8) {
                    Image(systemName: "forward.fill")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                    
                    Text("Skipped \(skippedCount) clip\(skippedCount == 1 ? "" : "s")")
                        .font(Tokens.Typography.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                .padding(.bottom, 60)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black
        
        PlayerSkipToast(
            skippedCount: 2,
            isVisible: true
        )
    }
}
