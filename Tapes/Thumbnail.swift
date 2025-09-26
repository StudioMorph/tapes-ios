import SwiftUI

struct ClipThumbnail: Identifiable {
    let id: String
    let assetLocalId: String
    let index: Int
    let isPlaceholder: Bool
}

struct Thumbnail: View {
    let thumbnail: ClipThumbnail
    let onDelete: () -> Void
    
    @State private var dragOffset: CGFloat = 0
    @State private var isLongPressing = false
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        thumbnailContent
            .overlay(indexLabel)
            .overlay(deleteOverlay)
            .offset(y: dragOffset)
            .gesture(thumbnailGesture)
            .alert("Delete Clip", isPresented: $showDeleteConfirmation) {
                deleteAlertButtons
            } message: {
                Text("Are you sure you want to delete this clip?")
            }
    }
    
    private var thumbnailContent: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Tokens.Colors.elevated)
            .overlay(thumbnailIcon)
    }
    
    private var thumbnailIcon: some View {
        Group {
            if thumbnail.isPlaceholder {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(Tokens.Colors.onSurface)
            } else {
                Image(systemName: "video.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Tokens.Colors.onSurface)
            }
        }
    }
    
    private var indexLabel: some View {
        VStack {
            HStack {
                Spacer()
                Text("\(thumbnail.index)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(Tokens.Colors.onSurface)
                    .padding(Tokens.Spacing.s)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(Tokens.Spacing.s)
            }
            Spacer()
        }
        .padding(Tokens.Spacing.s)
    }
    
    private var deleteOverlay: some View {
        Group {
            if isLongPressing {
                VStack {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Tokens.Colors.onSurface)
                        .padding(Tokens.Spacing.s)
                        .background(Tokens.Colors.red)
                        .clipShape(Circle())
                }
                .background(Color.black.opacity(0.7))
                .cornerRadius(8)
            }
        }
    }
    
    private var thumbnailGesture: some Gesture {
        SimultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onChanged { _ in
                    isLongPressing = true
                }
                .onEnded { _ in
                    isLongPressing = false
                },
            DragGesture()
                .onChanged { value in
                    if isLongPressing {
                        dragOffset = value.translation.height
                        if value.translation.height < -50 {
                            showDeleteConfirmation = true
                        }
                    }
                }
                .onEnded { _ in
                    if !showDeleteConfirmation {
                        withAnimation(.spring()) {
                            dragOffset = 0
                        }
                    }
                    isLongPressing = false
                }
        )
    }
    
    private var deleteAlertButtons: some View {
        Group {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {
                withAnimation(.spring()) {
                    dragOffset = 0
                }
            }
        }
    }
}

#Preview("Dark Mode") {
    Thumbnail(
        thumbnail: ClipThumbnail(id: "1", assetLocalId: "test", index: 1, isPlaceholder: false),
        onDelete: {}
    )
    .preferredColorScheme(ColorScheme.dark)
    .padding()
    .background(Tokens.Colors.bg)
}

#Preview("Light Mode") {
    Thumbnail(
        thumbnail: ClipThumbnail(id: "1", assetLocalId: "test", index: 1, isPlaceholder: false),
        onDelete: {}
    )
    .preferredColorScheme(ColorScheme.light)
    .padding()
    .background(Tokens.Colors.bg)
}