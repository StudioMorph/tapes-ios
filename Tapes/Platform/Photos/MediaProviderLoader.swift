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
            if let err = err { cont.resume(throwing: MediaLoaderError.loadFailed(err)); return }
            guard let src = url else { cont.resume(throwing: MediaLoaderError.noURL); return }

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
    return try await withCheckedThrowingContinuation { cont in
        provider.loadObject(ofClass: UIImage.self) { obj, err in
            if let err = err { cont.resume(throwing: MediaLoaderError.imageFailed(err)); return }
            guard let img = obj as? UIImage else { cont.resume(throwing: MediaLoaderError.imageFailed(nil)); return }
            cont.resume(returning: img)
        }
    }
}

/// Preserve selection order, loading items concurrently but returning in-order.
func resolvePickedMediaOrdered(_ results: [PHPickerResult]) async -> [PickedMedia] {
    if results.isEmpty { return [] }
    var out = Array<PickedMedia?>(repeating: nil, count: results.count)

    await withTaskGroup(of: Void.self) { group in
        for (idx, r) in results.enumerated() {
            group.addTask {
                do {
                    if r.itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                        let url = try await loadMovieURL(from: r)
                        out[idx] = .video(url)
                    } else if r.itemProvider.canLoadObject(ofClass: UIImage.self) {
                        let img = try await loadImage(from: r)
                        out[idx] = .photo(img)
                    }
                } catch {
                    log.error("❌ Resolving item failed at index \(idx): \(String(describing: error), privacy: .public)")
                }
            }
        }
    }

    return out.compactMap { $0 }
}
