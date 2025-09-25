import SwiftUI
import PhotosUI

// MARK: - Thumbnail Data Model

public struct ClipThumbnail: Identifiable, Equatable {
    public let id: String
    public let asset: PHAsset?
    public let isPlaceholder: Bool
    public let index: Int
    public let tapeName: String
    
    public init(id: String, asset: PHAsset? = nil, isPlaceholder: Bool = false, index: Int, tapeName: String) {
        self.id = id
        self.asset = asset
        self.isPlaceholder = isPlaceholder
        self.index = index
        self.tapeName = tapeName
    }
    
    var displayLabel: String {
        if isPlaceholder {
            return "+"
        }
        return "\(tapeName)/pos:\(index)"
    }
}

// MARK: - Thumbnail Component

public struct Thumbnail: View {
    let thumbnail: ClipThumbnail
    let width: CGFloat
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onDelete: () -> Void
    
    @State private var isPressed: Bool = false
    @State private var image: UIImage?
    @State private var dragOffset: CGSize = .zero
    @State private var isLongPressing: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    
    public init(
        thumbnail: ClipThumbnail,
        width: CGFloat,
        onTap: @escaping () -> Void,
        onLongPress: @escaping () -> Void = {},
        onDelete: @escaping () -> Void = {}
    ) {
        self.thumbnail = thumbnail
        self.width = width
        self.onTap = onTap
        self.onLongPress = onLongPress
        self.onDelete = onDelete
    }
    
    private var height: CGFloat {
        width * 9 / 16 // 16:9 aspect ratio
    }
    
    public var body: some View {
        Button(action: onTap) {
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: DesignTokens.Radius.thumbnail)
                    .fill(thumbnail.isPlaceholder ? 
                          DesignTokens.Colors.muted(20) : 
                          DesignTokens.Colors.muted(40))
                    .frame(width: width, height: height)
                
                // Content
                if thumbnail.isPlaceholder {
                    // Placeholder content
                    VStack(spacing: DesignTokens.Spacing.s8) {
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(DesignTokens.Colors.muted(60))
                        
                        Text("Add Clip")
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(DesignTokens.Colors.muted(60))
                    }
                } else {
                    // Thumbnail content
                    if let image = image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: width, height: height)
                            .clipped()
                            .cornerRadius(DesignTokens.Radius.thumbnail)
                    } else {
                        // Loading state
                        VStack(spacing: DesignTokens.Spacing.s8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading...")
                                .font(DesignTokens.Typography.caption)
                                .foregroundColor(DesignTokens.Colors.muted(60))
                        }
                    }
                }
                
                // Index label overlay
                if !thumbnail.isPlaceholder {
                    VStack {
                        HStack {
                            Spacer()
                            Text(thumbnail.displayLabel)
                                .font(DesignTokens.Typography.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, DesignTokens.Spacing.s8)
                                .padding(.vertical, DesignTokens.Spacing.s4)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignTokens.Radius.thumbnail)
                                        .fill(.black.opacity(0.7))
                                )
                                .padding(.top, DesignTokens.Spacing.s8)
                                .padding(.trailing, DesignTokens.Spacing.s8)
                        }
                        Spacer()
                    }
                }
                
                // Delete indicator overlay (when dragging up)
                if isLongPressing && dragOffset.height < -50 {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "trash.fill")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, DesignTokens.Spacing.s8)
                                .padding(.vertical, DesignTokens.Spacing.s4)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignTokens.Radius.thumbnail)
                                        .fill(DesignTokens.Colors.primaryRed)
                                )
                                .padding(.bottom, DesignTokens.Spacing.s8)
                                .padding(.trailing, DesignTokens.Spacing.s8)
                        }
                    }
                }
            }
        }
        .buttonStyle(ThumbnailButtonStyle())
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .offset(dragOffset)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .animation(.easeInOut(duration: 0.2), value: dragOffset)
        .onLongPressGesture(minimumDuration: 0.5) {
            isLongPressing = true
            onLongPress()
        } onPressingChanged: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
            if !pressing {
                isLongPressing = false
                dragOffset = .zero
            }
        }
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    if isLongPressing && !thumbnail.isPlaceholder {
                        dragOffset = value.translation
                    }
                }
                .onEnded { value in
                    if isLongPressing && !thumbnail.isPlaceholder {
                        // Check if dragged up significantly
                        if value.translation.height < -50 {
                            showDeleteConfirmation = true
                        }
                        dragOffset = .zero
                        isLongPressing = false
                    }
                }
        )
        .alert("Delete Clip", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Are you sure you want to delete this clip? This action cannot be undone.")
        }
        .onAppear {
            loadThumbnailImage()
        }
        .onChange(of: thumbnail.asset) { _ in
            loadThumbnailImage()
        }
    }
    
    private func loadThumbnailImage() {
        guard let asset = thumbnail.asset else {
            image = nil
            return
        }
        
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .fastFormat
        options.resizeMode = .exact
        
        let targetSize = CGSize(width: width * UIScreen.main.scale, 
                               height: height * UIScreen.main.scale)
        
        manager.requestImage(for: asset, 
                           targetSize: targetSize, 
                           contentMode: .aspectFill, 
                           options: options) { result, _ in
            DispatchQueue.main.async {
                self.image = result
            }
        }
    }
}

// MARK: - Thumbnail Button Style

private struct ThumbnailButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Preview

struct Thumbnail_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Placeholder thumbnail
            Thumbnail(
                thumbnail: ClipThumbnail(
                    id: "placeholder",
                    isPlaceholder: true,
                    index: 0,
                    tapeName: "My Tape"
                ),
                width: 150,
                onTap: { print("Placeholder tapped") },
                onLongPress: { print("Placeholder long pressed") },
                onDelete: { print("Placeholder delete") }
            )
            
            // Regular thumbnail
            Thumbnail(
                thumbnail: ClipThumbnail(
                    id: "clip1",
                    index: 1,
                    tapeName: "My Tape"
                ),
                width: 150,
                onTap: { print("Clip tapped") },
                onLongPress: { print("Clip long pressed") },
                onDelete: { print("Clip delete") }
            )
        }
        .padding()
        .background(DesignTokens.Colors.surface(.light))
        .previewDisplayName("Thumbnail Component")
    }
}
