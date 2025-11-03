import Foundation
import Photos
import UIKit
import os

/// Provides thumbnails for timeline/carousel display using PHImageManager.
/// Requests thumbnails only (no AVAsset resolution) with network access disabled.
@MainActor
final class TimelineThumbnailProvider {
    
    // MARK: - Properties
    
    private let imageManager: PHCachingImageManager
    private var currentVisibleIndices: Set<Int> = []
    private let preheatWindow: Int = 3 // Preheat 3 clips ahead/behind visible range
    
    // MARK: - Initialization
    
    init(imageManager: PHCachingImageManager = PHCachingImageManager()) {
        self.imageManager = imageManager
    }
    
    // MARK: - Public API
    
    /// Request thumbnail for a single clip (Photos asset only).
    /// Network access is disabled - only local thumbnails will be returned.
    func requestThumbnail(
        for assetLocalId: String,
        targetSize: CGSize,
        completion: @escaping (UIImage?) -> Void
    ) {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetLocalId], options: nil)
        guard let asset = fetchResult.firstObject else {
            TapesLog.mediaPicker.warning("TimelineThumbnailProvider: Asset not found: \(assetLocalId)")
            completion(nil)
            return
        }
        
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false // ✅ Timeline only - no network
        options.deliveryMode = .fastFormat // ✅ Fastest - returns immediately
        options.resizeMode = .fast
        options.isSynchronous = false
        
        // Log request (debug only)
        #if DEBUG
        let assetPrefix = String(assetLocalId.prefix(8))
        TapesLog.mediaPicker.info("[THUMB] asset=\(assetPrefix)... targetSize=\(Int(targetSize.width))x\(Int(targetSize.height)) network=false")
        #endif
        
        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, info in
            #if DEBUG
            if let info = info {
                let isCached = (info[PHImageResultIsInCloudKey] as? Bool) == false
                let isDegraded = (info[PHImageResultIsDegradedKey] as? Bool) == true
                let assetPrefix = String(assetLocalId.prefix(8))
                TapesLog.mediaPicker.info("[THUMB] asset=\(assetPrefix)... cached=\(isCached) degraded=\(isDegraded)")
            }
            #endif
            
            completion(image)
        }
    }
    
    /// Start preheating thumbnails for visible clips + adjacent range.
    func startPreheating(assetLocalIds: [String], visibleStartIndex: Int, visibleEndIndex: Int, targetSize: CGSize) {
        let preheatStart = max(0, visibleStartIndex - preheatWindow)
        let preheatEnd = min(assetLocalIds.count, visibleEndIndex + preheatWindow)
        
        guard preheatStart < preheatEnd else { return }
        
        let preheatRange = preheatStart..<preheatEnd
        let preheatIndices = Set(preheatRange)
        
        // Only preheat if range changed
        guard preheatIndices != currentVisibleIndices else { return }
        currentVisibleIndices = preheatIndices
        
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: Array(assetLocalIds[preheatRange]), options: nil)
        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        
        guard !assets.isEmpty else { return }
        
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        
        imageManager.startCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: options)
        
        #if DEBUG
        TapesLog.mediaPicker.info("[PREHEAT] start=\(preheatStart) end=\(preheatEnd) count=\(assets.count)")
        #endif
    }
    
    /// Stop preheating thumbnails for clips that are no longer visible.
    func stopPreheating(assetLocalIds: [String], targetSize: CGSize) {
        guard !currentVisibleIndices.isEmpty else { return }
        
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: assetLocalIds, options: nil)
        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        
        guard !assets.isEmpty else { return }
        
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        
        imageManager.stopCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: options)
        
        currentVisibleIndices.removeAll()
        
        #if DEBUG
        TapesLog.mediaPicker.info("[PREHEAT] Cancelled for \(assets.count) assets")
        #endif
    }
    
    /// Extract metadata from PHAsset without creating AVAsset.
    func extractMetadata(for assetLocalId: String) -> (duration: TimeInterval, pixelWidth: Int, pixelHeight: Int, creationDate: Date?)? {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetLocalId], options: nil)
        guard let asset = fetchResult.firstObject else { return nil }
        
        return (
            duration: asset.duration,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            creationDate: asset.creationDate
        )
    }
}

