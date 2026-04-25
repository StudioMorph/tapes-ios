//
//  TapesList.swift
//  Tapes
//
//  Created by AI Assistant on 25/09/2025.
//

import SwiftUI

struct TapesList: View {
    @EnvironmentObject private var tapeStore: TapesStore
    @EnvironmentObject private var uploadCoordinator: ShareUploadCoordinator
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @Binding var tapes: [Tape]
    let editingTapeID: UUID?
    @Binding var draftTitle: String
    let onShare: (Tape) -> Void
    let onSettings: (Tape) -> Void
    let onPlay: (Tape, Int) -> Void
    let onThumbnailDelete: (Tape, Clip) -> Void
    let onCameraCapture: (@escaping ([PickedMedia]) -> Void) -> Void
    let onTitleFocusRequest: (UUID, String) -> Void
    let onTitleCommit: () -> Void
    var onSyncUpload: ((Tape) -> Void)?
    @Binding var showInlineTitle: Bool

    private let columnSpacing: CGFloat = 16

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = verticalSizeClass == .compact
            let contentWidth = geometry.size.width - (Tokens.Spacing.m * 2)
            let tapeWidth: CGFloat = isLandscape
                ? (contentWidth - columnSpacing) / 2
                : contentWidth

            ScrollViewReader { scrollProxy in
                ScrollView {
                    Image(colorScheme == .dark ? "Tapes_logo-Dark mode" : "Tapes_logo-Light mode")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 40)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Tokens.Spacing.m)
                        .padding(.top, Tokens.Spacing.s)
                        .padding(.bottom, Tokens.Spacing.m)

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

                    AmbientTutorialCarousel()
                        .padding(.top, 40)
                }
                .scrollDisabled(tapeStore.isFloatingDragActive)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .onScrollGeometryChange(for: Bool.self) { geo in
                    geo.contentOffset.y > 40
                } action: { _, scrolledPastTitle in
                    showInlineTitle = scrolledPastTitle
                }
                .onChange(of: editingTapeID) { _, newID in
                    guard let id = newID else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        scrollProxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tapeCards(tapeWidth: CGFloat, isLandscape: Bool) -> some View {
        ForEach($tapes) { $tape in
            if tape.isShared || tape.isCollabTape { EmptyView() } else {
            let tapeID = tape.id

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
                onShare: { onShare(tape) },
                onSettings: { onSettings(tape) },
                onPlay: { startIndex in onPlay(tape, startIndex) },
                onThumbnailDelete: { clip in onThumbnailDelete(tape, clip) },
                onCameraCapture: onCameraCapture,
                onTitleFocusRequest: { onTitleFocusRequest(tapeID, tape.title) },
                titleEditingConfig: titleEditingConfig
            )
            .background(Tokens.Colors.primaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
            .overlay(alignment: .bottomTrailing) {
                let isUploadingThisTape = uploadCoordinator.isUploading && uploadCoordinator.sourceTape?.id == tape.id
                if tape.pendingUploadCount > 0, !isUploadingThisTape, tapeStore.jigglingTapeID == nil {
                    SyncBadge(count: tape.pendingUploadCount, direction: .upload) {
                        onSyncUpload?(tape)
                    }
                }
            }
            .compositingGroup()
            .opacity(tapeStore.jigglingTapeID != nil && tapeStore.jigglingTapeID != tapeID ? 0.4 : 1)
            .disabled(tapeStore.jigglingTapeID != nil && tapeStore.jigglingTapeID != tapeID)
            .animation(.easeInOut(duration: 0.25), value: tapeStore.jigglingTapeID)
            .id(tapeID)
            }
        }
    }
}

// MARK: - Ambient Tutorial Carousel

struct AmbientTutorialCarousel: View {
    @State private var page = 0
    @State private var timer: Timer?

    private let loopDurations: [TimeInterval] = [5.3, 6.8, 10.5]
    private let pageCount = 3
    private let loopsBeforeAdvance = 2

    var body: some View {
        TabView(selection: $page) {
            VStack {
                Spacer()
                CameraCaptureAnimation()
                    .padding(.horizontal, Tokens.Spacing.s)
                Spacer()
                    .frame(height: 56)
            }
            .tag(0)

            VStack {
                Spacer()
                FabSwipeAnimation()
                    .padding(.horizontal, Tokens.Spacing.s)
                Spacer()
                    .frame(height: 56)
            }
            .tag(1)

            VStack {
                Spacer()
                JiggleReorderAnimation()
                    .padding(.horizontal, Tokens.Spacing.s)
                Spacer()
                    .frame(height: 56)
            }
            .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .frame(height: 280)
        .compositingGroup()
        .opacity(0.4)
        .onAppear { scheduleAdvance() }
        .onDisappear { timer?.invalidate(); timer = nil }
        .onChange(of: page) { _, _ in scheduleAdvance() }
    }

    private func scheduleAdvance() {
        timer?.invalidate()
        let delay = loopDurations[page] * Double(loopsBeforeAdvance)
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.4)) {
                    page = (page + 1) % pageCount
                }
            }
        }
    }
}

#Preview {
    TapesList(
        tapes: .constant(Tape.sampleTapes),
        editingTapeID: nil,
        draftTitle: .constant(""),
        onShare: { _ in },
        onSettings: { _ in },
        onPlay: { _, _ in },
        onThumbnailDelete: { _, _ in },
        onCameraCapture: { _ in },
        onTitleFocusRequest: { _, _ in },
        onTitleCommit: {},
        onSyncUpload: { _ in },
        showInlineTitle: .constant(false)
    )
    .background(Tokens.Colors.primaryBackground)
}
