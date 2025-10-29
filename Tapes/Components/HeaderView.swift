//
//  HeaderView.swift
//  Tapes
//
//  Created by AI Assistant on 25/09/2025.
//

import SwiftUI

struct HeaderView: View {
    let onQAChecklistTapped: () -> Void
    
    var body: some View {
        HStack {
            Text("TAPES")
                .font(Tokens.Typography.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(Tokens.Colors.systemRed)
                .accessibilityAddTraits(.isHeader)
            
            Spacer()
            
            Button(action: onQAChecklistTapped) {
                Image(systemName: "checklist")
                    .font(.title2)
                    .foregroundColor(Tokens.Colors.systemRed)
                    .frame(width: Tokens.HitTarget.minimum, height: Tokens.HitTarget.minimum)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("QA Checklist")
            .accessibilityHint("Opens the QA checklist for testing")
        }
        .padding(.horizontal, Tokens.Spacing.m)
        .padding(.top, Tokens.Spacing.s)
        .padding(.bottom, Tokens.Spacing.xs)
    }
}

#Preview {
    HeaderView(onQAChecklistTapped: {})
        .background(Tokens.Colors.primaryBackground)
}
