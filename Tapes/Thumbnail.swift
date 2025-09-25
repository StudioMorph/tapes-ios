import SwiftUI

struct ClipThumbnail {
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
        VStack(spacing: Tokens.Space.xs) {
            // Thumbnail image
            RoundedRectangle(cornerRadius: 8)
                .fill(Tokens.Colors.elevated)
                .frame(width: 80, height: 80 * 9/16)
                .overlay(
                    Group {
                        if thumbnail.isPlaceholder {
                            Image(systemName: "plus")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(Tokens.Colors.text)
                        } else {
                            // Placeholder for actual video thumbnail
                            Image(systemName: "video.fill")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(Tokens.Colors.text)
                        }
                    }
                )
                .overlay(
                    // Index label
                    VStack {
                        HStack {
                            Spacer()
                            Text("\(thumbnail.index)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(Tokens.Colors.onAccent)
                                .padding(Tokens.Space.xs)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(Tokens.Space.xs)
                        }
                        Spacer()
                    }
                    .padding(Tokens.Space.xs)
                )
                .overlay(
                    // Delete confirmation overlay
                    Group {
                        if isLongPressing {
                            VStack {
                                Image(systemName: "trash")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(Tokens.Colors.onAccent)
                                    .padding(Tokens.Space.s)
                                    .background(Tokens.Colors.brandRed)
                                    .clipShape(Circle())
                            }
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(8)
                        }
                    }
                )
                .offset(y: dragOffset)
                .gesture(
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
                )
        }
        .alert("Delete Clip", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {
                withAnimation(.spring()) {
                    dragOffset = 0
                }
            }
        } message: {
            Text("Are you sure you want to delete this clip?")
        }
    }
}

#Preview("Dark Mode") {
    Thumbnail(
        thumbnail: ClipThumbnail(id: "1", assetLocalId: "test", index: 1, isPlaceholder: false),
        onDelete: {}
    )
    .preferredColorScheme(.dark)
    .padding()
    .background(Tokens.Colors.bg)
}

#Preview("Light Mode") {
    Thumbnail(
        thumbnail: ClipThumbnail(id: "1", assetLocalId: "test", index: 1, isPlaceholder: false),
        onDelete: {}
    )
    .preferredColorScheme(.light)
    .padding()
    .background(Tokens.Colors.bg)
}