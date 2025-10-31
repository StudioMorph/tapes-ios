import Foundation
import AVFoundation
import UIKit
import os

/// Generates and caches thumbnails for scrubbing UI
actor ThumbnailGenerator {
    
    // MARK: - Properties
    
    private let cacheDirectory: URL
    private var memoryCache: [String: UIImage] = [:]
    private let maxMemoryCacheSize = 50 // Max 50 thumbnails in memory
    
    // MARK: - Initialization
    
    init() {
        let fileManager = FileManager.default
        cacheDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Thumbnails", isDirectory: true)
        
        // Create cache directory if needed
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
        
        // Clean old cache on init
        Task {
            await cleanupOldCache()
        }
    }
    
    // MARK: - Public API
    
    /// Generate thumbnail for clip
    func generateThumbnail(
        for clip: Clip,
        index: Int,
        at time: CMTime? = nil,
        size: CGSize = CGSize(width: 160, height: 90)
    ) async throws -> UIImage {
        let cacheKey = cacheKey(for: clip, index: index, time: time)
        
        // Check memory cache
        if let cached = memoryCache[cacheKey] {
            return cached
        }
        
        // Check disk cache
        if let diskCached = try? loadFromDisk(key: cacheKey) {
            // Add to memory cache
            addToMemoryCache(key: cacheKey, image: diskCached)
            return diskCached
        }
        
        // Generate new thumbnail
        let asset = try await resolveAsset(for: clip)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = size
        
        let thumbnailTime = time ?? CMTime(seconds: 0.1, preferredTimescale: 600)
        let result = try await generator.image(at: thumbnailTime)
        let cgImage = result.image
        let image = UIImage(cgImage: cgImage)
        
        // Cache to disk and memory
        try? saveToDisk(key: cacheKey, image: image)
        addToMemoryCache(key: cacheKey, image: image)
        
        TapesLog.player.info("ThumbnailGenerator: Generated thumbnail for clip \(index)")
        
        return image
    }
    
    /// Generate multiple thumbnails for scrubbing
    func generateThumbnails(
        for clip: Clip,
        index: Int,
        count: Int,
        size: CGSize = CGSize(width: 160, height: 90)
    ) async throws -> [UIImage] {
        guard count > 0 else { return [] }
        
        let asset = try await resolveAsset(for: clip)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        
        guard durationSeconds > 0 else { return [] }
        
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = size
        
        var thumbnails: [UIImage] = []
        let interval = durationSeconds / Double(count + 1)
        
        for i in 1...count {
            let time = CMTime(seconds: Double(i) * interval, preferredTimescale: 600)
            let result = try await generator.image(at: time)
            let cgImage = result.image
            thumbnails.append(UIImage(cgImage: cgImage))
        }
        
        TapesLog.player.info("ThumbnailGenerator: Generated \(count) thumbnails for clip \(index)")
        
        return thumbnails
    }
    
    /// Clear all caches
    func clearCache() {
        memoryCache.removeAll()
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        TapesLog.player.info("ThumbnailGenerator: Cache cleared")
    }
    
    // MARK: - Private Implementation
    
    private func cacheKey(for clip: Clip, index: Int, time: CMTime?) -> String {
        let timestamp = time.map { "\(Int(CMTimeGetSeconds($0) * 1000))" } ?? "0"
        let updatedAt = clip.updatedAt.timeIntervalSince1970
        return "\(clip.id.uuidString)-\(index)-\(timestamp)-\(Int(updatedAt))"
    }
    
    private func resolveAsset(for clip: Clip) async throws -> AVAsset {
        let builder = TapeCompositionBuilder()
        let context = try await builder.resolveClipContext(for: clip, index: 0)
        return context.asset
    }
    
    private func addToMemoryCache(key: String, image: UIImage) {
        // Evict oldest if cache is full
        if memoryCache.count >= maxMemoryCacheSize {
            let oldestKey = memoryCache.keys.first!
            memoryCache.removeValue(forKey: oldestKey)
        }
        memoryCache[key] = image
    }
    
    private func loadFromDisk(key: String) throws -> UIImage? {
        let url = cacheDirectory.appendingPathComponent("\(key).jpg")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
    
    private func saveToDisk(key: String, image: UIImage) throws {
        let url = cacheDirectory.appendingPathComponent("\(key).jpg")
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        try data.write(to: url)
    }
    
    private func cleanupOldCache() {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return
        }
        
        let maxAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days
        let now = Date()
        
        var cleaned = 0
        for url in files {
            if let modDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                if now.timeIntervalSince(modDate) > maxAge {
                    try? fileManager.removeItem(at: url)
                    cleaned += 1
                }
            }
        }
        
        if cleaned > 0 {
            TapesLog.player.info("ThumbnailGenerator: Cleaned \(cleaned) old thumbnails")
        }
    }
}

