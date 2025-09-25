import Foundation
import Photos

// MARK: - Clip Model

public struct Clip: Identifiable, Codable, Equatable {
    public var id: UUID
    public var assetLocalId: String
    public var rotateQuarterTurns: Int
    public var overrideScaleMode: ScaleMode?
    public var createdAt: Date
    public var updatedAt: Date
    
    // Computed properties (not stored)
    public var duration: TimeInterval {
        // This would be fetched from PHAsset in real implementation
        // For now, return a default duration
        return 5.0
    }
    
    public init(
        id: UUID = UUID(),
        assetLocalId: String,
        rotateQuarterTurns: Int = 0,
        overrideScaleMode: ScaleMode? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.assetLocalId = assetLocalId
        self.rotateQuarterTurns = rotateQuarterTurns
        self.overrideScaleMode = overrideScaleMode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // MARK: - Computed Properties
    
    public var rotationDegrees: Double {
        return Double(rotateQuarterTurns) * 90.0
    }
    
    public var isRotated: Bool {
        return rotateQuarterTurns != 0
    }
    
    public var hasScaleOverride: Bool {
        return overrideScaleMode != nil
    }
    
    // MARK: - Mutating Methods
    
    public mutating func rotate() {
        rotateQuarterTurns = (rotateQuarterTurns + 1) % 4
        updatedAt = Date()
    }
    
    public mutating func setRotation(_ quarterTurns: Int) {
        rotateQuarterTurns = quarterTurns % 4
        updatedAt = Date()
    }
    
    public mutating func setScaleMode(_ scaleMode: ScaleMode?) {
        overrideScaleMode = scaleMode
        updatedAt = Date()
    }
    
    public mutating func clearScaleOverride() {
        overrideScaleMode = nil
        updatedAt = Date()
    }
}

// MARK: - Equatable

extension Clip {
    public static func == (lhs: Clip, rhs: Clip) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - PHAsset Integration

extension Clip {
    /// Fetches the PHAsset for this clip
    public func fetchAsset() -> PHAsset? {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetLocalId], options: nil)
        return fetchResult.firstObject
    }
    
    /// Creates a Clip from a PHAsset
    public static func from(asset: PHAsset) -> Clip {
        return Clip(assetLocalId: asset.localIdentifier)
    }
    
    /// Creates a Clip from a PHAsset with initial settings
    public static func from(
        asset: PHAsset,
        rotateQuarterTurns: Int = 0,
        overrideScaleMode: ScaleMode? = nil
    ) -> Clip {
        return Clip(
            assetLocalId: asset.localIdentifier,
            rotateQuarterTurns: rotateQuarterTurns,
            overrideScaleMode: overrideScaleMode
        )
    }
}
