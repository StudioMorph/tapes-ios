//
//  TapesList.swift
//  Tapes
//
//  Created by AI Assistant on 25/09/2025.
//

import SwiftUI

struct TapesList: View {
    @Binding var tapes: [Tape]
    let editingTapeID: UUID?
    @Binding var draftTitle: String
    let onSettings: (Tape) -> Void
    let onPlay: (Tape) -> Void
    let onAirPlay: (Tape) -> Void
    let onThumbnailDelete: (Tape, Clip) -> Void
    let onClipInserted: (Tape, Clip, Int) -> Void
    let onClipInsertedAtPlaceholder: (Tape, Clip, CarouselItem) -> Void
    let onMediaInserted: (Tape, [PickedMedia], InsertionStrategy) -> Void
    let onTitleFocusRequest: (UUID, String) -> Void
    let onTitleCommit: () -> Void
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: Tokens.Spacing.m) {
                ForEach($tapes) { $tape in
                    let tapeID = tape.id
                    let currentTape = tape
                    
                    let titleEditingConfig: TapeCardView.TitleEditingConfig? = {
                        guard editingTapeID == tapeID else { return nil }
                        return TapeCardView.TitleEditingConfig(
                            text: Binding(
                                get: { draftTitle },
                                set: { draftTitle = $0 }
                            ),
                            tapeID: tapeID,
                            onCommit: onTitleCommit
                        )
                    }()
                    
                    TapeCardRow(
                        tape: $tape,
                        tapeID: tapeID,
                        onSettings: { onSettings(currentTape) },
                        onPlay: { onPlay(currentTape) },
                        onAirPlay: { onAirPlay(currentTape) },
                        onThumbnailDelete: { clip in onThumbnailDelete(currentTape, clip) },
                        onClipInserted: { clip, index in onClipInserted(currentTape, clip, index) },
                        onClipInsertedAtPlaceholder: { clip, placeholder in onClipInsertedAtPlaceholder(currentTape, clip, placeholder) },
                        onMediaInserted: { media, strategy in onMediaInserted(currentTape, media, strategy) },
                        onTitleFocusRequest: { onTitleFocusRequest(tapeID, currentTape.title) },
                        titleEditingConfig: titleEditingConfig
                    )
                    .id(tapeID)
                }
            }
            .padding(.horizontal, Tokens.Spacing.m)
            .padding(.vertical, Tokens.Spacing.s)
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }
}

#Preview {
    TapesList(
        tapes: .constant(Tape.sampleTapes),
        editingTapeID: nil,
        draftTitle: .constant(""),
        onSettings: { _ in },
        onPlay: { _ in },
        onAirPlay: { _ in },
        onThumbnailDelete: { _, _ in },
        onClipInserted: { _, _, _ in },
        onClipInsertedAtPlaceholder: { _, _, _ in },
        onMediaInserted: { _, _, _ in },
        onTitleFocusRequest: { _, _ in },
        onTitleCommit: {}
    )
    .background(Tokens.Colors.primaryBackground)
}
