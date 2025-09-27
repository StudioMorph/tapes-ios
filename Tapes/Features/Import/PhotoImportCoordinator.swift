import SwiftUI
import PhotosUI
import AVFoundation
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
                // Try to load as video first
                if let movie = try await item.loadTransferable(type: Movie.self) {
                    let thumbnail = await generateThumbnail(from: movie.url)
                    let duration = await getVideoDuration(url: movie.url)
                    
                    pickedMedia.append(.video(movie.url))
                } else if let image = try await item.loadTransferable(type: Data.self) {
                    // Load as image
                    if let uiImage = UIImage(data: image) {
                        let thumbnail = uiImage
                        let duration = Tokens.Timing.photoDefaultDuration
                        
                        pickedMedia.append(.photo(uiImage))
                    }
                }
            } catch {
                print("Error loading media item: \(error)")
            }
        }
        
        return pickedMedia
    }
    
    private func generateThumbnail(from url: URL) async -> UIImage? {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 320, height: 320)
        
        do {
            let cgImage = try await imageGenerator.image(at: .zero).image
            return UIImage(cgImage: cgImage)
        } catch {
            print("Error generating thumbnail: \(error)")
            return nil
        }
    }
    
    private func getVideoDuration(url: URL) async -> TimeInterval {
        let asset = AVAsset(url: url)
        let duration = try? await asset.load(.duration)
        return CMTimeGetSeconds(duration ?? .zero)
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
