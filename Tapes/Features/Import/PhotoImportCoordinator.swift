import SwiftUI
import PhotosUI
import AVFoundation
import Photos
import UIKit

// MARK: - Models

public enum PickedMediaType {
    case video
    case image
}


public enum InsertionStrategy {
    case replaceThenAppend(startIndex: Int)
    case insertAtCenter
}

// MARK: - PhotoImportCoordinator

public struct PhotoImportCoordinator: View {
    @Binding var isPresented: Bool
    let onMediaSelected: ([PickedMedia], InsertionStrategy) -> Void
    
    @State private var selection: [PhotosPickerItem] = []
    @State private var isProcessing = false
    
    public init(isPresented: Binding<Bool>, onMediaSelected: @escaping ([PickedMedia], InsertionStrategy) -> Void) {
        self._isPresented = isPresented
        self.onMediaSelected = onMediaSelected
    }
    
    public var body: some View {
        PhotosPicker(
            selection: $selection,
            maxSelectionCount: nil,
            matching: .any(of: [.images, .videos])
        ) {
            EmptyView()
        }
        .onChange(of: selection) { _, newSelection in
            guard !newSelection.isEmpty else { return }
            processSelection(newSelection)
        }
    }
    
    private func processSelection(_ items: [PhotosPickerItem]) {
        guard !isProcessing else { return }
        isProcessing = true
        
        Task {
            let pickedMedia = await loadMediaItems(items)
            
            await MainActor.run {
                // Determine insertion strategy based on current state
                // This will be set by the calling view
                let strategy: InsertionStrategy = .insertAtCenter // Default, will be overridden
                onMediaSelected(pickedMedia, strategy)
                isProcessing = false
                isPresented = false
            }
        }
    }
    
    private func loadMediaItems(_ items: [PhotosPickerItem]) async -> [PickedMedia] {
        var pickedMedia: [PickedMedia] = []
        
        for item in items {
            do {
                // For Photos assets, use PHAsset directly (no AVAsset, no file copy)
                if let assetIdentifier = item.itemIdentifier {
                    if let photosMedia = await resolvePhotosAsset(assetIdentifier: assetIdentifier, item: item) {
                        pickedMedia.append(photosMedia)
                        continue
                    }
                }
                
                // Fallback: Try to load as video file (camera captures, etc.)
                if let movie = try await item.loadTransferable(type: Movie.self) {
                    // Don't create AVAsset here - duration can be 0, resolved later if needed
                    pickedMedia.append(.video(url: movie.url, duration: 0, assetIdentifier: item.itemIdentifier))
                } else if let image = try await item.loadTransferable(type: Data.self) {
                    // Load as image
                    if let uiImage = UIImage(data: image) {
                        pickedMedia.append(.photo(image: uiImage, assetIdentifier: item.itemIdentifier))
                    }
                }
            } catch {
                TapesLog.mediaPicker.error("Failed to load media item: \(error.localizedDescription)")
            }
        }
        
        return pickedMedia
    }
    
    /// Resolve Photos asset using PHAsset metadata (no AVAsset creation, no file copy).
    private func resolvePhotosAsset(assetIdentifier: String, item: PhotosPickerItem) async -> PickedMedia? {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let phAsset = fetchResult.firstObject else { return nil }
        
        #if DEBUG
        let assetPrefix = String(assetIdentifier.prefix(8))
        TapesLog.mediaPicker.info("[INTAKE] asset=\(assetPrefix)... type=\(phAsset.mediaType.rawValue) duration=\(phAsset.duration)s size=\(phAsset.pixelWidth)x\(phAsset.pixelHeight) source=photos network=false")
        #endif
        
        switch phAsset.mediaType {
        case .video:
            // For Photos videos, don't copy file - use assetIdentifier only
            // Duration from PHAsset (no AVAsset needed)
            return .video(url: nil, duration: phAsset.duration, assetIdentifier: assetIdentifier)
            
        case .image:
            // Request thumbnail only (no full image load)
            // Use @2x scale for Retina: 150x84 display → 300x168 @2x
            let scale = UIScreen.main.scale
            let thumbnailSize = CGSize(width: 300 * scale, height: 168 * scale)
            let thumbnail = await requestPhotosThumbnail(for: phAsset, targetSize: thumbnailSize)
            return .photo(image: thumbnail ?? UIImage(), assetIdentifier: assetIdentifier)
            
        default:
            return nil
        }
    }
    
    /// Request thumbnail from Photos asset (no network access).
    private func requestPhotosThumbnail(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        return await withCheckedContinuation { continuation in
            var hasResumed = false
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = false // ✅ Timeline only - no network
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isSynchronous = false
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                guard !hasResumed else { return } // Guard against multiple resumes
                
                // Check if request was cancelled or failed
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let error = info?[PHImageErrorKey] as? Error
                if cancelled || error != nil {
                    hasResumed = true
                    continuation.resume(returning: nil)
                    return
                }
                
                // Only resume once - wait for final image (not degraded)
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded {
                    hasResumed = true
                    continuation.resume(returning: image)
                }
                // If degraded, wait for the next callback with final image
            }
        }
    }
}

// MARK: - Movie Transferable

struct Movie: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            // Copy to temp directory
            let tempDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            let tapesDir = tempDir.appendingPathComponent("TapesTemp")
            try? FileManager.default.createDirectory(at: tapesDir, withIntermediateDirectories: true)
            
            let fileName = UUID().uuidString + ".mp4"
            let outputURL = tapesDir.appendingPathComponent(fileName)
            
            try FileManager.default.copyItem(at: received.file, to: outputURL)
            return Movie(url: outputURL)
        }
    }
}
