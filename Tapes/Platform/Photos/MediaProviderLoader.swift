import Foundation
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation
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
    case video(url: URL?, duration: TimeInterval, assetIdentifier: String?) // url is nil for Photos assets
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
    // If Photos asset, use PHAsset metadata directly (no AVAsset, no file copy)
    if let assetIdentifier = result.assetIdentifier {
        if let photosMedia = try? await resolvePhotosAsset(assetIdentifier: assetIdentifier, result: result) {
            return photosMedia
        }
    }
    
    // Fallback to file-based handling (camera captures, etc.)
    if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
        // For local files, still copy (needed for playback), but defer duration
        let url = try await loadMovieURL(from: result)
        // Don't create AVAsset here - duration can be 0 initially, resolved later if needed
        // For Photos assets, this path shouldn't be reached (handled above)
        return .video(url: url, duration: 0, assetIdentifier: result.assetIdentifier)
    }

    if result.itemProvider.canLoadObject(ofClass: UIImage.self) ||
        result.itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
        let image = try await loadImage(from: result)
        return .photo(image: image, assetIdentifier: result.assetIdentifier)
    }

    throw MediaLoaderError.loadFailed(nil)
}

/// Resolve Photos asset using PHAsset metadata (no AVAsset creation).
private func resolvePhotosAsset(assetIdentifier: String, result: PHPickerResult) async throws -> PickedMedia {
    let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
    guard let phAsset = fetchResult.firstObject else {
        throw MediaLoaderError.loadFailed(nil) // Not a Photos asset or not found
    }
    
    #if DEBUG
    let assetPrefix = String(assetIdentifier.prefix(8))
    TapesLog.mediaPicker.info("[INTAKE] asset=\(assetPrefix)... type=\(phAsset.mediaType.rawValue) duration=\(phAsset.duration)s size=\(phAsset.pixelWidth)x\(phAsset.pixelHeight) source=photos network=false")
    #endif
    
    switch phAsset.mediaType {
    case .video:
        // For Photos videos, don't copy file - use assetIdentifier only
        // Duration from PHAsset (no AVAsset needed)
        // URL will be nil (Photos assets don't have localURL in timeline)
        return .video(url: nil, duration: phAsset.duration, assetIdentifier: assetIdentifier)
        
    case .image:
        // Request thumbnail only (no full image load)
        // Use @2x scale for Retina: 150x84 display → 300x168 @2x
        let scale = UIScreen.main.scale
        let thumbnailSize = CGSize(width: 300 * scale, height: 168 * scale)
        let thumbnail = await requestPhotosThumbnail(for: phAsset, targetSize: thumbnailSize)
        return .photo(image: thumbnail ?? UIImage(), assetIdentifier: assetIdentifier)
        
    default:
        throw MediaLoaderError.loadFailed(nil)
    }
}

/// Request thumbnail from Photos asset (no network access).
private func requestPhotosThumbnail(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
    return await withCheckedContinuation { continuation in
        var hasResumed = false
        
        // Use @2x scale for Retina displays
        let scale = UIScreen.main.scale
        let scaledSize = CGSize(width: targetSize.width * scale, height: targetSize.height * scale)
        
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false // ✅ Timeline only - no network
        options.deliveryMode = .fastFormat // ✅ Fastest - returns immediately
        options.resizeMode = .fast
        options.isSynchronous = false
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: scaledSize,
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
            
            // With .fastFormat, we get whatever is available immediately (no degraded callback)
            hasResumed = true
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
