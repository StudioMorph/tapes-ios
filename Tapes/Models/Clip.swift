import Foundation
import Photos
import UIKit

// MARK: - Clip Model

public enum ClipType: String, Codable, CaseIterable {
    case video
    case image
}

public struct Clip: Identifiable, Codable, Equatable {
    public var id: UUID
    public var assetLocalId: String?
    public var localURL: URL?
    public var imageData: Data?
    public var clipType: ClipType
    public var duration: TimeInterval
    public var thumbnail: Data?
    public var rotateQuarterTurns: Int
    public var overrideScaleMode: ScaleMode?
    public var createdAt: Date
    public var updatedAt: Date
    public var isPlaceholder: Bool
    
    private enum CodingKeys: String, CodingKey {
        case id
        case assetLocalId
        case localURL
        case imageData
        case clipType
        case duration
        case thumbnail
        case rotateQuarterTurns
        case overrideScaleMode
        case createdAt
        case updatedAt
        case isPlaceholder
    }
    
    public init(
        id: UUID = UUID(),
        assetLocalId: String? = nil,
        localURL: URL? = nil,
        imageData: Data? = nil,
        clipType: ClipType = .video,
        duration: TimeInterval = 0,
        thumbnail: Data? = nil,
        rotateQuarterTurns: Int = 0,
        overrideScaleMode: ScaleMode? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isPlaceholder: Bool = false
    ) {
        self.id = id
        self.assetLocalId = assetLocalId
        self.localURL = localURL
        self.imageData = imageData
        self.clipType = clipType
        self.duration = duration
        self.thumbnail = thumbnail
        self.rotateQuarterTurns = rotateQuarterTurns
        self.overrideScaleMode = overrideScaleMode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPlaceholder = isPlaceholder
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        assetLocalId = try container.decodeIfPresent(String.self, forKey: .assetLocalId)
        localURL = try container.decodeIfPresent(URL.self, forKey: .localURL)
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        clipType = try container.decode(ClipType.self, forKey: .clipType)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        thumbnail = try container.decodeIfPresent(Data.self, forKey: .thumbnail)
        rotateQuarterTurns = try container.decode(Int.self, forKey: .rotateQuarterTurns)
        overrideScaleMode = try container.decodeIfPresent(ScaleMode.self, forKey: .overrideScaleMode)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isPlaceholder = try container.decodeIfPresent(Bool.self, forKey: .isPlaceholder) ?? false
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(assetLocalId, forKey: .assetLocalId)
        try container.encodeIfPresent(localURL, forKey: .localURL)
        try container.encodeIfPresent(imageData, forKey: .imageData)
        try container.encode(clipType, forKey: .clipType)
        try container.encode(duration, forKey: .duration)
        try container.encodeIfPresent(thumbnail, forKey: .thumbnail)
        try container.encode(rotateQuarterTurns, forKey: .rotateQuarterTurns)
        try container.encodeIfPresent(overrideScaleMode, forKey: .overrideScaleMode)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        if isPlaceholder {
            try container.encode(true, forKey: .isPlaceholder)
        }
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
    
    // MARK: - Convenience Initializers
    
    /// Creates a Clip from a local video file
    public static func fromVideo(
        url: URL,
        duration: TimeInterval,
        thumbnail: UIImage? = nil,
        assetLocalId: String? = nil
    ) -> Clip {
        return Clip(
            assetLocalId: assetLocalId,
            localURL: url,
            clipType: .video,
            duration: duration,
            thumbnail: thumbnail?.jpegData(compressionQuality: 0.8)
        )
    }
    
    public static func fromImage(
        imageData: Data,
        duration: TimeInterval = 3.0,
        thumbnail: UIImage? = nil,
        assetLocalId: String? = nil
    ) -> Clip {
        return Clip(
            assetLocalId: assetLocalId,
            imageData: imageData,
            clipType: .image,
            duration: duration,
            thumbnail: thumbnail?.jpegData(compressionQuality: 0.8)
        )
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

    public static func placeholder(id: UUID = UUID()) -> Clip {
        Clip(
            id: id,
            clipType: .video,
            duration: 0,
            createdAt: Date(),
            updatedAt: Date(),
            isPlaceholder: true
        )
    }
    
    // MARK: - Computed Properties
    
    public var thumbnailImage: UIImage? {
        guard let thumbnailData = thumbnail else { return nil }
        return UIImage(data: thumbnailData)
    }
    
    public var isLocalVideo: Bool {
        return localURL != nil
    }
    
    public var isPhotoAsset: Bool {
        return assetLocalId != nil
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
        guard let assetLocalId = assetLocalId else { return nil }
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetLocalId], options: nil)
        return fetchResult.firstObject
    }
}
