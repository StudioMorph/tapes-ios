import Foundation
import PhotosUI
import UniformTypeIdentifiers
import Photos
import os

enum MediaLoaderError: Error {
    case noMovieUTI
    case loadFailed(Error?)
    case noURL
    case copyFailed(Error)
    case imageFailed(Error?)
}

public enum PickedMedia {
    case video(url: URL?, duration: TimeInterval, assetIdentifier: String?)
    case photo(image: UIImage, assetIdentifier: String?)
}

private let log = Logger(subsystem: "com.studiomorph.tapes", category: "MediaPicker")

/// Copy the file we get from PHPicker into our own temp location (so it survives after the callback).
func loadMovieURL(from result: PHPickerResult) async throws -> URL {
    let provider = result.itemProvider
    guard provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else {
        throw MediaLoaderError.noMovieUTI
    }

    return try await withCheckedThrowingContinuation { cont in
        provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, err in
            if let err = err { 
                log.error("❌ Movie load failed: \(String(describing: err), privacy: .public)")
                cont.resume(throwing: MediaLoaderError.loadFailed(err))
                return 
            }
            guard let src = url else { 
                log.error("❌ No URL returned for movie")
                cont.resume(throwing: MediaLoaderError.noURL)
                return 
            }

            // Destination inside our sandbox tmp
            let importsDir = FileManager.default.temporaryDirectory.appendingPathComponent("Imports", isDirectory: true)
            try? FileManager.default.createDirectory(at: importsDir, withIntermediateDirectories: true)
            let ext = src.pathExtension.isEmpty ? "mov" : src.pathExtension
            let dest = importsDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)

            do {
                // Remove if exists (rare)
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: src, to: dest)
                log.info("✅ Copied movie to \(dest.path, privacy: .public)")
                cont.resume(returning: dest)
            } catch {
                log.error("❌ Copy movie failed: \(String(describing: error), privacy: .public)")
                cont.resume(throwing: MediaLoaderError.copyFailed(error))
            }
        }
    }
}

func loadImage(from result: PHPickerResult) async throws -> UIImage {
    let provider = result.itemProvider
    
    // Prefer loadObject for UIImage
    if provider.canLoadObject(ofClass: UIImage.self) {
        return try await withCheckedThrowingContinuation { cont in
            provider.loadObject(ofClass: UIImage.self) { obj, err in
                if let err = err { 
                    log.error("❌ Image loadObject failed: \(String(describing: err), privacy: .public)")
                    cont.resume(throwing: MediaLoaderError.imageFailed(err))
                    return 
                }
                guard let img = obj as? UIImage else { 
                    log.error("❌ No UIImage returned from loadObject")
                    cont.resume(throwing: MediaLoaderError.imageFailed(nil))
                    return 
                }
                
                // Write JPEG to temp file for consistency
                do {
                    let importsDir = FileManager.default.temporaryDirectory.appendingPathComponent("Imports", isDirectory: true)
                    try? FileManager.default.createDirectory(at: importsDir, withIntermediateDirectories: true)
                    let dest = importsDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
                    
                    if let jpegData = img.jpegData(compressionQuality: 0.8) {
                        try jpegData.write(to: dest)
                        log.info("✅ Copied image to \(dest.path, privacy: .public)")
                    }
                    
                    cont.resume(returning: img)
                } catch {
                    log.error("❌ Image temp file write failed: \(String(describing: error), privacy: .public)")
                    cont.resume(throwing: MediaLoaderError.copyFailed(error))
                }
            }
        }
    }
    
    // Fallback to loadFileRepresentation for UTType.image
    return try await withCheckedThrowingContinuation { cont in
        provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, err in
            if let err = err { 
                log.error("❌ Image loadFileRepresentation failed: \(String(describing: err), privacy: .public)")
                cont.resume(throwing: MediaLoaderError.loadFailed(err))
                return 
            }
            guard let src = url else { 
                log.error("❌ No URL returned for image")
                cont.resume(throwing: MediaLoaderError.noURL)
                return 
            }
            
            do {
                let importsDir = FileManager.default.temporaryDirectory.appendingPathComponent("Imports", isDirectory: true)
                try? FileManager.default.createDirectory(at: importsDir, withIntermediateDirectories: true)
                let ext = src.pathExtension.isEmpty ? "jpg" : src.pathExtension
                let dest = importsDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
                
                try FileManager.default.copyItem(at: src, to: dest)
                log.info("✅ Copied image file to \(dest.path, privacy: .public)")
                
                // Load as UIImage for return
                guard let image = UIImage(contentsOfFile: dest.path) else {
                    cont.resume(throwing: MediaLoaderError.imageFailed(nil))
                    return
                }
                
                cont.resume(returning: image)
            } catch {
                log.error("❌ Image file copy failed: \(String(describing: error), privacy: .public)")
                cont.resume(throwing: MediaLoaderError.copyFailed(error))
            }
        }
    }
}

func resolvePickedMedia(from result: PHPickerResult) async throws -> PickedMedia {
    if let assetIdentifier = result.assetIdentifier,
       let asset = fetchPHAsset(localIdentifier: assetIdentifier) {
        switch asset.mediaType {
        case .video:
            let seconds = asset.duration
            return .video(url: nil, duration: seconds, assetIdentifier: assetIdentifier)
        case .image:
            if let thumbnail = await requestThumbnail(for: asset) {
                return .photo(image: thumbnail, assetIdentifier: assetIdentifier)
            }
        default:
            break
        }
    }

    if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
        let url = try await loadMovieURL(from: result)
        let seconds = durationFromPhotos(assetIdentifier: result.assetIdentifier)
        return .video(url: url, duration: seconds, assetIdentifier: result.assetIdentifier)
    }

    if result.itemProvider.canLoadObject(ofClass: UIImage.self) ||
        result.itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
        let image = try await loadImage(from: result)
        return .photo(image: image, assetIdentifier: result.assetIdentifier)
    }

    throw MediaLoaderError.loadFailed(nil)
}

private func durationFromPhotos(assetIdentifier: String?) -> TimeInterval {
    guard let assetIdentifier else { return 0 }
    return fetchPHAsset(localIdentifier: assetIdentifier)?.duration ?? 0
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

/// Preserve selection order, loading items concurrently but returning in-order.
func resolvePickedMediaOrdered(_ results: [PHPickerResult]) async -> [PickedMedia] {
    if results.isEmpty { return [] }
    var out = Array<PickedMedia?>(repeating: nil, count: results.count)

    await withTaskGroup(of: (Int, PickedMedia?).self) { group in
        for (idx, r) in results.enumerated() {
            group.addTask {
                do {
                    let media = try await resolvePickedMedia(from: r)
                    return (idx, media)
                } catch {
                    log.error("❌ Resolving item failed at index \(idx): \(String(describing: error), privacy: .public)")
                    return (idx, nil)
                }
            }
        }
        
        for await (idx, media) in group {
            out[idx] = media
        }
    }

    return out.compactMap { $0 }
}

/// Optional persistence helper to move files from temp to Application Support
func moveToPersistentStorage(_ tempURL: URL) -> URL? {
    do {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let clipsDir = appSupport.appendingPathComponent("Clips", isDirectory: true)
        try FileManager.default.createDirectory(at: clipsDir, withIntermediateDirectories: true)
        
        let persistentURL = clipsDir.appendingPathComponent(tempURL.lastPathComponent)
        
        // Remove if exists
        if FileManager.default.fileExists(atPath: persistentURL.path) {
            try FileManager.default.removeItem(at: persistentURL)
        }
        
        try FileManager.default.moveItem(at: tempURL, to: persistentURL)
        log.info("✅ Moved to persistent storage: \(persistentURL.path, privacy: .public)")
        return persistentURL
    } catch {
        log.error("❌ Failed to move to persistent storage: \(String(describing: error), privacy: .public)")
        return nil
    }
}

/// Clean up temp imports directory
func cleanupTempImports() {
    do {
        let importsDir = FileManager.default.temporaryDirectory.appendingPathComponent("Imports", isDirectory: true)
        if FileManager.default.fileExists(atPath: importsDir.path) {
            try FileManager.default.removeItem(at: importsDir)
            log.info("✅ Cleaned up temp imports directory")
        }
    } catch {
        log.error("❌ Failed to clean up temp imports: \(String(describing: error), privacy: .public)")
    }
}
