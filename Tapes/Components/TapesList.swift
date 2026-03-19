//
//  TapesList.swift
//  Tapes
//
//  Created by AI Assistant on 25/09/2025.
//

import SwiftUI

struct TapesList: View {
    @EnvironmentObject private var tapeStore: TapesStore
    @Binding var tapes: [Tape]
    let editingTapeID: UUID?
    @Binding var draftTitle: String
    let onSettings: (Tape) -> Void
    let onPlay: (Tape) -> Void
    let onMergeAndSave: (Tape) -> Void
    let onThumbnailDelete: (Tape, Clip) -> Void
    let onClipInserted: (Tape, Clip, Int) -> Void
    let onClipInsertedAtPlaceholder: (Tape, Clip, CarouselItem) -> Void
    let onMediaInserted: (Tape, [PickedMedia], InsertionStrategy) -> Void
    let onCameraCapture: (@escaping ([PickedMedia]) -> Void) -> Void
    let onTitleFocusRequest: (UUID, String) -> Void
    let onTitleCommit: () -> Void

    private let columnSpacing: CGFloat = 16

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            let contentWidth = geometry.size.width - (Tokens.Spacing.m * 2)
            let tapeWidth: CGFloat = isLandscape
                ? (contentWidth - columnSpacing) / 2
                : contentWidth

            ScrollView {
                if isLandscape {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: columnSpacing),
                            GridItem(.flexible(), spacing: columnSpacing)
                        ],
                        spacing: Tokens.Spacing.m
                    ) {
                        tapeCards(tapeWidth: tapeWidth, isLandscape: isLandscape)
                    }
                    .padding(.horizontal, Tokens.Spacing.m)
                    .padding(.vertical, Tokens.Spacing.s)
                } else {
                    LazyVStack(spacing: Tokens.Spacing.m) {
                        tapeCards(tapeWidth: tapeWidth, isLandscape: isLandscape)
                    }
                    .padding(.horizontal, Tokens.Spacing.m)
                    .padding(.vertical, Tokens.Spacing.s)
                }
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    @ViewBuilder
    private func tapeCards(tapeWidth: CGFloat, isLandscape: Bool) -> some View {
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

            TapeCardView(
                tape: $tape,
                tapeID: tapeID,
                tapeWidth: tapeWidth,
                isLandscape: isLandscape,
                onSettings: { onSettings(currentTape) },
                onPlay: { onPlay(currentTape) },
                onMergeAndSave: { onMergeAndSave(currentTape) },
                onThumbnailDelete: { clip in onThumbnailDelete(currentTape, clip) },
                onClipInserted: { clip, index in onClipInserted(currentTape, clip, index) },
                onClipInsertedAtPlaceholder: { clip, placeholder in onClipInsertedAtPlaceholder(currentTape, clip, placeholder) },
                onMediaInserted: { media, strategy in onMediaInserted(currentTape, media, strategy) },
                onCameraCapture: onCameraCapture,
                onTitleFocusRequest: { onTitleFocusRequest(tapeID, currentTape.title) },
                titleEditingConfig: titleEditingConfig
            )
            .background(Tokens.Colors.primaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
            .compositingGroup()
            .opacity(tapeStore.jigglingTapeID != nil && tapeStore.jigglingTapeID != tapeID ? 0.4 : 1)
            .disabled(tapeStore.jigglingTapeID != nil && tapeStore.jigglingTapeID != tapeID)
            .animation(.easeInOut(duration: 0.25), value: tapeStore.jigglingTapeID)
            .id(tapeID)
        }
    }
}

#Preview {
    TapesList(
        tapes: .constant(Tape.sampleTapes),
        editingTapeID: nil,
        draftTitle: .constant(""),
        onSettings: { _ in },
        onPlay: { _ in },
        onMergeAndSave: { _ in },
        onThumbnailDelete: { _, _ in },
        onClipInserted: { _, _, _ in },
        onClipInsertedAtPlaceholder: { _, _, _ in },
        onMediaInserted: { _, _, _ in },
        onCameraCapture: { _ in },
        onTitleFocusRequest: { _, _ in },
        onTitleCommit: {}
    )
    .background(Tokens.Colors.primaryBackground)
}
