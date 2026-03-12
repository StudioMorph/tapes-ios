//
//  MoodOptionCell.swift
//  Tapes
//
//  Created by AI Assistant on 26/01/2026.
//

import SwiftUI

struct MoodOptionCell: View {
    let mood: MubertAPIClient.Mood
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: Tokens.Spacing.xs) {
                Image(systemName: mood.icon)
                    .font(.title3)
                    .foregroundColor(isSelected ? .white : Tokens.Colors.primaryText)

                Text(mood.displayName)
                    .font(.caption2)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(isSelected ? .white : Tokens.Colors.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.thumb)
                    .fill(isSelected ? Tokens.Colors.systemRed : Tokens.Colors.tertiaryBackground)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mood.displayName) mood")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    HStack {
        MoodOptionCell(mood: .chill, isSelected: true, onSelect: {})
        MoodOptionCell(mood: .cinematic, isSelected: false, onSelect: {})
        MoodOptionCell(mood: .epic, isSelected: false, onSelect: {})
    }
    .padding()
    .background(Tokens.Colors.primaryBackground)
}
