import Foundation
import PhotosUI
import UniformTypeIdentifiers
import os

enum MediaLoaderError: Error {
    case noMovieUTI
    case loadFailed(Error?)
    case noURL
    case copyFailed(Error)
    case imageFailed(Error?)
}

public enum PickedMedia {
    case video(URL)
    case photo(UIImage)
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

/// Preserve selection order, loading items concurrently but returning in-order.
func resolvePickedMediaOrdered(_ results: [PHPickerResult]) async -> [PickedMedia] {
    if results.isEmpty { return [] }
    var out = Array<PickedMedia?>(repeating: nil, count: results.count)

    await withTaskGroup(of: (Int, PickedMedia?).self) { group in
        for (idx, r) in results.enumerated() {
            group.addTask {
                do {
                    if r.itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                        let url = try await loadMovieURL(from: r)
                        return (idx, .video(url))
                    } else if r.itemProvider.canLoadObject(ofClass: UIImage.self) || r.itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                        let img = try await loadImage(from: r)
                        return (idx, .photo(img))
                    } else {
                        log.error("❌ Unsupported media type at index \(idx)")
                        return (idx, nil)
                    }
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
