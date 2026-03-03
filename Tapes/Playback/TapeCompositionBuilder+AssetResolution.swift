import AVFoundation
import Photos
import UIKit

extension TapeCompositionBuilder {

    func resolveAsset(for clip: Clip) async throws -> ResolvedAsset {
        switch clip.clipType {
        case .video:
            let asset = try await resolveVideoAsset(for: clip)
            return ResolvedAsset(asset: asset, isTemporary: false, motionEffect: nil)
        case .image:
            let image = try await loadImage(for: clip)
            let durationSeconds = clip.duration > 0 ? clip.duration : imageConfiguration.defaultDuration
            let asset = try await createVideoAsset(from: image, clip: clip, duration: durationSeconds)
            return ResolvedAsset(
                asset: asset,
                isTemporary: true,
                motionEffect: imageConfiguration.defaultMotionEffect
            )
        }
    }

    static func fetchAVAssetFromPhotos(localIdentifier: String) async throws -> AVAsset {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw BuilderError.photosAccessDenied
        }

        return try await withCheckedThrowingContinuation { continuation in
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
            guard let phAsset = fetchResult.firstObject else {
                continuation.resume(throwing: BuilderError.photosAssetMissing)
                return
            }

            let mediaType = phAsset.mediaType
            let duration = phAsset.duration
            let pixelWidth = phAsset.pixelWidth
            let pixelHeight = phAsset.pixelHeight
            let creationDate = phAsset.creationDate
            let modificationDate = phAsset.modificationDate

            TapesLog.player.info("TapeCompositionBuilder: [\(localIdentifier)] Starting fetch - type: \(mediaType == .video ? "video" : "unknown"), duration: \(String(format: "%.2f", duration))s, size: \(pixelWidth)x\(pixelHeight), created: \(creationDate?.description ?? "unknown"), modified: \(modificationDate?.description ?? "unknown")")

            let options = PHVideoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true

            let startTime = Date()
            var callbackCount = 0
            var timeToFirstCallback: TimeInterval = 0
            var isComplete = false

            let monitoringTask = Task {
                while !isComplete && !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if isComplete { break }
                    let elapsed = Date().timeIntervalSince(startTime)
                    if callbackCount == 0 {
                        TapesLog.player.warning("TapeCompositionBuilder: [\(localIdentifier)] Still no callbacks after \(String(format: "%.1f", elapsed))s")
                    }
                }
            }

            TapesLog.player.info("TapeCompositionBuilder: [\(localIdentifier)] Initiating PHImageManager request...")

            PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { asset, _, info in
                callbackCount += 1
                if callbackCount == 1 {
                    timeToFirstCallback = Date().timeIntervalSince(startTime)
                    TapesLog.player.info("TapeCompositionBuilder: [\(localIdentifier)] First callback after \(String(format: "%.2f", timeToFirstCallback))s")
                }

                isComplete = true
                monitoringTask.cancel()

                if let asset = asset {
                    let totalTime = Date().timeIntervalSince(startTime)
                    if let urlAsset = asset as? AVURLAsset {
                        let fileName = urlAsset.url.lastPathComponent
                        if let fileSize = try? FileManager.default.attributesOfItem(atPath: urlAsset.url.path)[.size] as? Int64 {
                            let fileSizeMB = Double(fileSize) / 1_000_000.0
                            TapesLog.player.info("TapeCompositionBuilder: [\(localIdentifier)] Success in \(String(format: "%.2f", totalTime))s - file: \(fileName), size: \(String(format: "%.2f", fileSizeMB))MB")
                        } else {
                            TapesLog.player.info("TapeCompositionBuilder: [\(localIdentifier)] Success in \(String(format: "%.2f", totalTime))s - file: \(urlAsset.url.lastPathComponent)")
                        }
                    } else {
                        TapesLog.player.info("TapeCompositionBuilder: [\(localIdentifier)] Success in \(String(format: "%.2f", totalTime))s")
                    }
                    continuation.resume(returning: asset)
                } else {
                    let totalTime = Date().timeIntervalSince(startTime)
                    TapesLog.player.error("TapeCompositionBuilder: [\(localIdentifier)] Failed after \(String(format: "%.2f", totalTime))s")
                    continuation.resume(throwing: BuilderError.assetUnavailable(clipID: UUID()))
                }
            }
        }
    }

    static func defaultAssetResolver(_ clip: Clip) async throws -> AVAsset {
        switch clip.clipType {
        case .video:
            if let url = clip.localURL {
                let accessibleURL = try accessibleURL(for: clip, url: url)
                return AVURLAsset(url: accessibleURL)
            }
            if let assetLocalId = clip.assetLocalId {
                return try await fetchAVAssetFromPhotos(localIdentifier: assetLocalId)
            }
            throw BuilderError.assetUnavailable(clipID: clip.id)
        case .image:
            throw BuilderError.unsupportedClipType(.image)
        }
    }

    func resolveVideoAsset(for clip: Clip) async throws -> AVAsset {
        let fileManager = FileManager.default

        if let localURL = clip.localURL {
            if fileManager.fileExists(atPath: localURL.path) {
                let accessibleURL = try Self.accessibleURL(for: clip, url: localURL)
                return AVURLAsset(url: accessibleURL)
            } else {
                let cachedURL = Self.cachedURL(for: clip, originalURL: localURL)
                if fileManager.fileExists(atPath: cachedURL.path) {
                    return AVURLAsset(url: cachedURL)
                }
            }
        }

        if let assetLocalId = clip.assetLocalId {
            return try await Self.fetchAVAssetFromPhotos(localIdentifier: assetLocalId)
        }

        throw BuilderError.assetUnavailable(clipID: clip.id)
    }

    static func accessibleURL(for clip: Clip, url: URL) throws -> URL {
        var didAccessSecurityScope = false
        if url.startAccessingSecurityScopedResource() {
            didAccessSecurityScope = true
        }
        defer {
            if didAccessSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let fileManager = FileManager.default
        let cacheDirectory = fileManager.temporaryDirectory.appendingPathComponent("PlaybackCache", isDirectory: true)
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
        }

        let destinationURL = cachedURL(for: clip, originalURL: url)

        if fileManager.fileExists(atPath: destinationURL.path) {
            return destinationURL
        }

        try fileManager.copyItem(at: url, to: destinationURL)
        return destinationURL
    }

    static func cachedURL(for clip: Clip, originalURL: URL) -> URL {
        let fileManager = FileManager.default
        let cacheDirectory = fileManager.temporaryDirectory.appendingPathComponent("PlaybackCache", isDirectory: true)
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
        }
        let fileExtension = originalURL.pathExtension.isEmpty ? "mov" : originalURL.pathExtension
        let updatedAt = clip.updatedAt
        let timestamp = Int((updatedAt.timeIntervalSince1970 * 1_000).rounded())
        let versionComponent = "\(clip.id.uuidString)-\(timestamp)"
        return cacheDirectory.appendingPathComponent(versionComponent).appendingPathExtension(fileExtension)
    }

    func fetchPHAsset(localIdentifier: String) async throws -> PHAsset {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw BuilderError.photosAccessDenied
        }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let phAsset = fetchResult.firstObject else {
            throw BuilderError.photosAssetMissing
        }

        return phAsset
    }

    func loadImage(for clip: Clip) async throws -> UIImage {
        if let data = clip.imageData, let image = UIImage(data: data) {
            return image
        }
        if let url = clip.localURL, let image = UIImage(contentsOfFile: url.path) {
            return image
        }
        if let assetLocalId = clip.assetLocalId {
            return try await fetchImageFromPhotos(localIdentifier: assetLocalId)
        }
        throw BuilderError.assetUnavailable(clipID: clip.id)
    }

    func fetchImageFromPhotos(localIdentifier: String) async throws -> UIImage {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw BuilderError.photosAccessDenied
        }

        return try await withCheckedThrowingContinuation { continuation in
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
            guard let asset = fetchResult.firstObject else {
                continuation.resume(throwing: BuilderError.photosAssetMissing)
                return
            }
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            let targetSize = CGSize(width: 2160, height: 3840)
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                if let image = image {
                    continuation.resume(returning: image)
                } else if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: BuilderError.photosAssetMissing)
                }
            }
        }
    }
}
