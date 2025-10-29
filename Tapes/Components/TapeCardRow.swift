//
//  TapeCardRow.swift
//  Tapes
//
//  Created by AI Assistant on 25/09/2025.
//

import SwiftUI

struct TapeCardRow: View {
    @Binding var tape: Tape
    let tapeID: UUID
    let onSettings: () -> Void
    let onPlay: () -> Void
    let onAirPlay: () -> Void
    let onThumbnailDelete: (Clip) -> Void
    let onClipInserted: (Clip, Int) -> Void
    let onClipInsertedAtPlaceholder: (Clip, CarouselItem) -> Void
    let onMediaInserted: ([PickedMedia], InsertionStrategy) -> Void
    let onTitleFocusRequest: () -> Void
    let titleEditingConfig: TapeCardView.TitleEditingConfig?
    
    var body: some View {
        VStack(spacing: 0) {
            TapeCardView(
                tape: $tape,
                tapeID: tapeID,
                onSettings: onSettings,
                onPlay: onPlay,
                onAirPlay: onAirPlay,
                onThumbnailDelete: onThumbnailDelete,
                onClipInserted: onClipInserted,
                onClipInsertedAtPlaceholder: onClipInsertedAtPlaceholder,
                onMediaInserted: onMediaInserted,
                onTitleFocusRequest: onTitleFocusRequest,
                titleEditingConfig: titleEditingConfig
            )
        }
        .background(Tokens.Colors.primaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
        .shadow(
            color: Color.black.opacity(0.1),
            radius: 4,
            x: 0,
            y: 2
        )
    }
}

#Preview {
    TapeCardRow(
        tape: .constant(Tape.sampleTapes[0]),
        tapeID: Tape.sampleTapes[0].id,
        onSettings: {},
        onPlay: {},
        onAirPlay: {},
        onThumbnailDelete: { _ in },
        onClipInserted: { _, _ in },
        onClipInsertedAtPlaceholder: { _, _ in },
        onMediaInserted: { _, _ in },
        onTitleFocusRequest: {},
        titleEditingConfig: nil
    )
    .padding()
    .background(Tokens.Colors.primaryBackground)
}
