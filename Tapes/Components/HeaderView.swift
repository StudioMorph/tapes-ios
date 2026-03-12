//
//  HeaderView.swift
//  Tapes
//
//  Created by AI Assistant on 25/09/2025.
//

import SwiftUI

struct HeaderView: View {
    @EnvironmentObject private var tapeStore: TapesStore
    let onQAChecklistTapped: () -> Void

    private var isJiggling: Bool {
        tapeStore.jigglingTapeID != nil
    }

    var body: some View {
        HStack {
            Text("TAPES")
                .font(Tokens.Typography.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(Tokens.Colors.systemRed)
                .accessibilityAddTraits(.isHeader)
            
            Spacer()

            if isJiggling {
                Button("Done") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        tapeStore.jigglingTapeID = nil
                    }
                }
                .font(.body.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.blue)
                .accessibilityLabel("Done")
                .accessibilityHint("Exits jiggle editing mode")
            } else {
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
        }
        .padding(.horizontal, Tokens.Spacing.m)
        .padding(.top, Tokens.Spacing.s)
        .padding(.bottom, Tokens.Spacing.xs)
        .animation(.easeInOut(duration: 0.25), value: isJiggling)
    }
}

#Preview {
    HeaderView(onQAChecklistTapped: {})
        .background(Tokens.Colors.primaryBackground)
        .environmentObject(TapesStore())
}
