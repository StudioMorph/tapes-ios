import SwiftUI

// MARK: - Tapes List View

public struct TapesListView: View {
    @StateObject private var tapesStore = TapesStore()
    @State private var showingSettings = false
    @State private var showingPlayOptions = false
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with New Tape button
                HStack {
                    Text("Tapes")
                        .font(DesignTokens.Typography.heading(24, weight: .bold))
                        .foregroundColor(DesignTokens.Colors.onSurface(.light))
                    
                    Spacer()
                    
                    Button(action: createNewTape) {
                        HStack(spacing: DesignTokens.Spacing.s8) {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .medium))
                            Text("New Tape")
                                .font(DesignTokens.Typography.body)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, DesignTokens.Spacing.s16)
                        .padding(.vertical, DesignTokens.Spacing.s8)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.thumbnail)
                                .fill(DesignTokens.Colors.primaryRed)
                        )
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.s20)
                .padding(.top, DesignTokens.Spacing.s16)
                .padding(.bottom, DesignTokens.Spacing.s20)
                
                // Tapes list
                if tapesStore.tapes.isEmpty {
                    // Empty state
                    VStack(spacing: DesignTokens.Spacing.s16) {
                        Image(systemName: "video.badge.plus")
                            .font(.system(size: 48, weight: .light))
                            .foregroundColor(DesignTokens.Colors.muted(40))
                        
                        Text("No Tapes Yet")
                            .font(DesignTokens.Typography.title)
                            .foregroundColor(DesignTokens.Colors.muted(60))
                        
                        Text("Create your first tape to get started")
                            .font(DesignTokens.Typography.body)
                            .foregroundColor(DesignTokens.Colors.muted(60))
                            .multilineTextAlignment(.center)
                        
                        Button(action: createNewTape) {
                            Text("Create New Tape")
                                .font(DesignTokens.Typography.body)
                                .foregroundColor(.white)
                                .padding(.horizontal, DesignTokens.Spacing.s24)
                                .padding(.vertical, DesignTokens.Spacing.s12)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignTokens.Radius.thumbnail)
                                        .fill(DesignTokens.Colors.primaryRed)
                                )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Tapes list
                    ScrollView {
                        LazyVStack(spacing: DesignTokens.Spacing.s20) {
                            ForEach(tapesStore.tapes) { tape in
                                TapeCardView(
                                    tape: tape,
                                    onSettings: {
                                        tapesStore.selectTape(tape)
                                        showingSettings = true
                                    },
                                    onPlay: {
                                        tapesStore.selectTape(tape)
                                        showingPlayOptions = true
                                    },
                                    onAirPlay: {
                                        handleAirPlay(for: tape)
                                    },
                                    onThumbnailTap: { thumbnail in
                                        handleThumbnailTap(thumbnail, in: tape)
                                    },
                                    onThumbnailLongPress: { thumbnail in
                                        handleThumbnailLongPress(thumbnail, in: tape)
                                    },
                                    onThumbnailDelete: { thumbnail in
                                        handleThumbnailDelete(thumbnail, in: tape)
                                    },
                                    onFABAction: { mode in
                                        handleFABAction(mode, for: tape)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, DesignTokens.Spacing.s20)
                        .padding(.bottom, DesignTokens.Spacing.s32)
                    }
                }
            }
            .background(DesignTokens.Colors.muted(10))
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingSettings) {
            if let selectedTape = tapesStore.selectedTape {
                TapeSettingsSheet(tape: Binding(
                    get: { selectedTape },
                    set: { tapesStore.updateTape($0) }
                )) {
                    showingSettings = false
                }
            }
        }
        .actionSheet(isPresented: $showingPlayOptions) {
            ActionSheet(
                title: Text("Play Options"),
                message: Text("Choose how to play this tape"),
                buttons: [
                    .default(Text("Preview Tape")) {
                        handlePreviewTape()
                    },
                    .default(Text("Merge & Save")) {
                        handleMergeAndSave()
                    },
                    .cancel()
                ]
            )
        }
    }
    
    // MARK: - Actions
    
    private func createNewTape() {
        let newTape = tapesStore.createNewTape()
        print("Created new tape: \(newTape.id)")
    }
    
    private func handleAirPlay(for tape: Tape) {
        print("AirPlay for tape: \(tape.title)")
        // TODO: Implement AirPlay functionality
    }
    
    private func handleThumbnailTap(_ thumbnail: ClipThumbnail, in tape: Tape) {
        print("Thumbnail tapped: \(thumbnail.id) in tape: \(tape.title)")
        // TODO: Implement thumbnail tap functionality
    }
    
    private func handleThumbnailLongPress(_ thumbnail: ClipThumbnail, in tape: Tape) {
        print("Thumbnail long pressed: \(thumbnail.id) in tape: \(tape.title)")
        // TODO: Implement thumbnail long press functionality
    }
    
    private func handleThumbnailDelete(_ thumbnail: ClipThumbnail, in tape: Tape) {
        print("Thumbnail delete: \(thumbnail.id) in tape: \(tape.title)")
        
        // Find the clip by ID and delete it
        if let clipId = UUID(uuidString: thumbnail.id) {
            tapesStore.deleteClip(from: tape.id, clip: Clip(id: clipId, assetLocalId: "", createdAt: Date(), updatedAt: Date()))
        }
    }
    
    private func handleFABAction(_ mode: FABMode, for tape: Tape) {
        print("FAB action: \(mode) for tape: \(tape.title)")
        // TODO: Implement FAB action functionality
    }
    
    private func handlePreviewTape() {
        print("Preview tape")
        // TODO: Implement preview functionality
    }
    
    private func handleMergeAndSave() {
        print("Merge and save tape")
        // TODO: Implement merge and save functionality
    }
}


// MARK: - Preview

struct TapesListView_Previews: PreviewProvider {
    static var previews: some View {
        TapesListView()
            .previewDisplayName("Tapes List")
    }
}
