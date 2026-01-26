import SwiftUI
import PhotosUI
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
                if let identifier = item.itemIdentifier,
                   let asset = fetchPHAsset(localIdentifier: identifier) {
                    switch asset.mediaType {
                    case .video:
                        pickedMedia.append(.video(url: nil, duration: asset.duration, assetIdentifier: identifier))
                        continue
                    case .image:
                        if let thumbnail = await requestThumbnail(for: asset) {
                            pickedMedia.append(.photo(image: thumbnail, assetIdentifier: identifier))
                            continue
                        }
                    default:
                        break
                    }
                }

                // Fallback for non-Photos sources
                if let movie = try await item.loadTransferable(type: Movie.self) {
                    let duration = durationFromPhotos(identifier: item.itemIdentifier)
                    pickedMedia.append(.video(url: movie.url, duration: duration, assetIdentifier: item.itemIdentifier))
                } else if let image = try await item.loadTransferable(type: Data.self) {
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
    
    private func durationFromPhotos(identifier: String?) -> TimeInterval {
        guard let identifier else { return 0 }
        return fetchPHAsset(localIdentifier: identifier)?.duration ?? 0
    }

    private func fetchPHAsset(localIdentifier: String) -> PHAsset? {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return nil }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        return fetch.firstObject
    }

    private func requestThumbnail(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            let targetSize = CGSize(width: 960, height: 960)
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                if let isDegraded = info?[PHImageResultIsDegradedKey] as? NSNumber, isDegraded.boolValue {
                    return
                }
                continuation.resume(returning: image)
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
