//
//  EmptyStateView.swift
//  Tapes
//
//  Created by AI Assistant on 25/09/2025.
//

import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: Tokens.Spacing.l) {
            Image(systemName: "video.badge.plus")
                .font(.system(size: 64, weight: .light))
                .foregroundColor(Tokens.Colors.tertiaryText)
            
            VStack(spacing: Tokens.Spacing.s) {
                Text("No Tapes Yet")
                    .font(Tokens.Typography.title)
                    .fontWeight(.semibold)
                    .foregroundColor(Tokens.Colors.primaryText)
                
                Text("Create your first tape by tapping the + button")
                    .font(Tokens.Typography.body)
                    .foregroundColor(Tokens.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(Tokens.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.Colors.primaryBackground)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No Tapes Yet. Create your first tape by tapping the + button")
    }
}

#Preview {
    EmptyStateView()
        .background(Tokens.Colors.primaryBackground)
}
