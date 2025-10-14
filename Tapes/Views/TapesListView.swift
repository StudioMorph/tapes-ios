import SwiftUI

struct TapesListView: View {
    @EnvironmentObject var tapesStore: TapesStore
    @StateObject private var exportCoordinator = ExportCoordinator()
    @State private var showingPlayer = false
    @State private var showingPlayOptions = false
    @State private var showingQAChecklist = false
    @State private var tapeToPreview: Tape?
    
    var body: some View {
        NavigationView {
            VStack {
                headerView
                tapesList
                Spacer()
            }
            .navigationBarHidden(true)
        }
        .background(Tokens.Colors.bg)
        .sheet(isPresented: $tapesStore.showingSettingsSheet) {
            settingsSheet
        }
        .actionSheet(isPresented: $showingPlayOptions) {
            playOptionsSheet
        }
        .fullScreenCover(isPresented: $showingPlayer) {
            playerView
        }
        .overlay(exportOverlay)
        .sheet(isPresented: $showingQAChecklist) {
            QAChecklistView()
        }
    }
    
    private var headerView: some View {
        HStack {
            Text("TAPES")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Tokens.Colors.red)
            
            Spacer()
            
            Button(action: { showingQAChecklist = true }) {
                Image(systemName: "checklist")
                    .font(.title2)
                    .foregroundColor(Tokens.Colors.red)
            }
        }
        .padding(.horizontal, Tokens.Spacing.m)
        .padding(.top, Tokens.Spacing.s)
    }
    
    private var tapesList: some View {
        ScrollView {
            LazyVStack(spacing: Tokens.Spacing.m) {  // 16pt vertical spacing between cards
                ForEach($tapesStore.tapes) { $tape in
                    TapeCardView(
                        tape: $tape,
                        onSettings: { tapesStore.selectTape($tape.wrappedValue) },
                        onPlay: {
                            tapeToPreview = $tape.wrappedValue
                            showingPlayOptions = true
                        },
                        onAirPlay: { },
                        onThumbnailDelete: { clip in
                            tapesStore.deleteClip(from: $tape.wrappedValue.id, clip: clip)
                        },
                        onClipInserted: { clip, index in
                            tapesStore.insertClip(clip, in: $tape.wrappedValue.id, atCenterOfCarouselIndex: index)
                        },
                        onClipInsertedAtPlaceholder: { clip, placeholder in
                            tapesStore.insertClipAtPlaceholder(clip, in: $tape.wrappedValue.id, placeholder: placeholder)
                        },
                        onMediaInserted: { pickedMedia, strategy in
                            tapesStore.insertMedia(pickedMedia, at: strategy, in: $tape.wrappedValue.id)
                        }
                    )
                    .padding(.horizontal, Tokens.Spacing.m)  // 16pt outer padding
                }
            }
        }
    }
    
    private var settingsSheet: some View {
        if let selectedTape = tapesStore.selectedTape {
            return AnyView(TapeSettingsSheet(
                tape: Binding(
                    get: { selectedTape },
                    set: { tapesStore.updateTape($0) }
                ),
                onDismiss: {
                    tapesStore.showingSettingsSheet = false
                    tapesStore.clearSelectedTape()
                }
            ))
        } else {
            return AnyView(EmptyView())
        }
    }
    
    private var playOptionsSheet: ActionSheet {
        ActionSheet(
            title: Text("Play Options"),
            buttons: [
                .default(Text("Preview Tape")) {
                    if tapeToPreview == nil {
                        tapeToPreview = tapesStore.tapes.first(where: { !$0.clips.isEmpty })
                    }
                    showingPlayer = tapeToPreview != nil
                },
                .default(Text("Merge & Save")) {
                    if let tape = tapesStore.tapes.first {
                        exportCoordinator.exportTape(tape)
                    }
                },
                .cancel()
            ]
        )
    }
    
    private var playerView: some View {
        if let tape = tapeToPreview {
            return AnyView(TapePlayerView(tape: tape, onDismiss: {
                showingPlayer = false
                tapeToPreview = nil
            }))
        } else {
            return AnyView(EmptyView())
        }
    }
    
    private var exportOverlay: some View {
        return ZStack {
            if exportCoordinator.isExporting {
                ExportProgressOverlay(coordinator: exportCoordinator)
            }
            if exportCoordinator.showCompletionToast {
                CompletionToast(coordinator: exportCoordinator)
            }
            if exportCoordinator.exportError != nil {
                ExportErrorAlert(coordinator: exportCoordinator)
            }
        }
    }
}

#Preview("Dark Mode") {
    TapesListView()
        .environmentObject(TapesStore())  // lightweight preview store
        .preferredColorScheme(.dark)
}

#Preview("Light Mode") {
    TapesListView()
        .environmentObject(TapesStore())  // lightweight preview store
        .preferredColorScheme(.light)
}