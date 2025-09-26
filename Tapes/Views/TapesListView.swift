import SwiftUI

struct TapesListView: View {
    @StateObject private var tapesStore = TapesStore()
    @StateObject private var exportCoordinator = ExportCoordinator()
    @State private var showingPlayer = false
    @State private var showingPlayOptions = false
    @State private var showingQAChecklist = false
    
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
                ForEach(tapesStore.tapes) { tape in
                    TapeCardView(
                        tape: tape,
                        onSettings: { tapesStore.selectTape(tape) },
                        onPlay: { showingPlayOptions = true },
                        onAirPlay: { },
                        onThumbnailDelete: { clip in
                            tapesStore.deleteClip(from: tape.id, clip: clip)
                        },
                        onClipInserted: { clip, index in
                            tapesStore.insertClip(clip, in: tape.id, atCenterOfCarouselIndex: index)
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
                )
            ))
        } else {
            return AnyView(EmptyView())
        }
    }
    
    private var playOptionsSheet: ActionSheet {
        ActionSheet(
            title: Text("Play Options"),
            buttons: [
                .default(Text("Preview Tape")) { showingPlayer = true },
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
        if let tape = tapesStore.tapes.first {
            return AnyView(TapePlayerView(tape: tape, onDismiss: { showingPlayer = false }))
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
        .preferredColorScheme(.dark)
}

#Preview("Light Mode") {
    TapesListView()
        .preferredColorScheme(.light)
}