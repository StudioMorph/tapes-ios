import Foundation
import Photos
import UIKit

// MARK: - Clip Model

public enum ClipType: String, Codable, CaseIterable {
    case video
    case image
}

public enum MotionStyle: String, Codable, CaseIterable {
    case none
    case kenBurns
    case pan
    case zoomIn
    case zoomOut
    case drift

    public var displayName: String {
        switch self {
        case .none: return "None"
        case .kenBurns: return "Ken Burns"
        case .pan: return "Pan"
        case .zoomIn: return "Zoom In"
        case .zoomOut: return "Zoom Out"
        case .drift: return "Drift"
        }
    }

    public var description: String {
        switch self {
        case .none: return "Static image, no movement"
        case .kenBurns: return "Classic slow zoom and pan"
        case .pan: return "Horizontal pan across the image"
        case .zoomIn: return "Gradual zoom into the image"
        case .zoomOut: return "Gradual zoom out from the image"
        case .drift: return "Subtle slow floating movement"
        }
    }
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
    public var trimStart: TimeInterval
    public var trimEnd: TimeInterval
    public var motionStyle: MotionStyle
    public var imageDuration: TimeInterval
    public var isLivePhoto: Bool
    public var livePhotoAsVideo: Bool?
    public var livePhotoMuted: Bool?
    public var volume: Double?
    public var musicVolume: Double?
    public var createdAt: Date
    public var updatedAt: Date
    public var isPlaceholder: Bool
    public var isSynced: Bool
    
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
        case trimStart
        case trimEnd
        case motionStyle
        case imageDuration
        case isLivePhoto
        case livePhotoAsVideo
        case livePhotoMuted
        case volume
        case musicVolume
        case createdAt
        case updatedAt
        case isPlaceholder
        case isSynced
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
        trimStart: TimeInterval = 0,
        trimEnd: TimeInterval = 0,
        motionStyle: MotionStyle = .kenBurns,
        imageDuration: TimeInterval = 4.0,
        isLivePhoto: Bool = false,
        livePhotoAsVideo: Bool? = nil,
        livePhotoMuted: Bool? = nil,
        volume: Double? = nil,
        musicVolume: Double? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isPlaceholder: Bool = false,
        isSynced: Bool = false
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
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.motionStyle = motionStyle
        self.imageDuration = imageDuration
        self.isLivePhoto = isLivePhoto
        self.livePhotoAsVideo = livePhotoAsVideo
        self.livePhotoMuted = livePhotoMuted
        self.volume = volume
        self.musicVolume = musicVolume
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPlaceholder = isPlaceholder
        self.isSynced = isSynced
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
        trimStart = try container.decodeIfPresent(TimeInterval.self, forKey: .trimStart) ?? 0
        trimEnd = try container.decodeIfPresent(TimeInterval.self, forKey: .trimEnd) ?? 0
        motionStyle = try container.decodeIfPresent(MotionStyle.self, forKey: .motionStyle) ?? .kenBurns
        imageDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .imageDuration) ?? 4.0
        isLivePhoto = try container.decodeIfPresent(Bool.self, forKey: .isLivePhoto) ?? false
        livePhotoAsVideo = try container.decodeIfPresent(Bool.self, forKey: .livePhotoAsVideo)
        livePhotoMuted = try container.decodeIfPresent(Bool.self, forKey: .livePhotoMuted)
        volume = try container.decodeIfPresent(Double.self, forKey: .volume)
        musicVolume = try container.decodeIfPresent(Double.self, forKey: .musicVolume)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isPlaceholder = try container.decodeIfPresent(Bool.self, forKey: .isPlaceholder) ?? false
        isSynced = try container.decodeIfPresent(Bool.self, forKey: .isSynced) ?? false
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
        if trimStart > 0 { try container.encode(trimStart, forKey: .trimStart) }
        if trimEnd > 0 { try container.encode(trimEnd, forKey: .trimEnd) }
        if motionStyle != .kenBurns { try container.encode(motionStyle, forKey: .motionStyle) }
        if imageDuration != 4.0 { try container.encode(imageDuration, forKey: .imageDuration) }
        if isLivePhoto { try container.encode(true, forKey: .isLivePhoto) }
        if let override = livePhotoAsVideo { try container.encode(override, forKey: .livePhotoAsVideo) }
        if let muted = livePhotoMuted { try container.encode(muted, forKey: .livePhotoMuted) }
        if let vol = volume { try container.encode(vol, forKey: .volume) }
        if let mVol = musicVolume { try container.encode(mVol, forKey: .musicVolume) }
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        if isPlaceholder {
            try container.encode(true, forKey: .isPlaceholder)
        }
        if isSynced {
            try container.encode(true, forKey: .isSynced)
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

    /// Effective playable duration after trimming.
    public var trimmedDuration: TimeInterval {
        max(0, duration - trimStart - trimEnd)
    }

    public var isTrimmed: Bool {
        trimStart > 0 || trimEnd > 0
    }

    // MARK: - Mutating Methods

    public mutating func setTrim(start: TimeInterval, end: TimeInterval) {
        trimStart = max(0, start)
        trimEnd = max(0, end)
        updatedAt = Date()
    }

    public mutating func clearTrim() {
        trimStart = 0
        trimEnd = 0
        updatedAt = Date()
    }
    
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
    
    // MARK: - Blob File Storage

    private static let thumbnailCache: NSCache<NSUUID, UIImage> = {
        let cache = NSCache<NSUUID, UIImage>()
        cache.countLimit = 80
        cache.totalCostLimit = 30 * 1024 * 1024
        return cache
    }()

    private static var mediaDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("clip_media", isDirectory: true)
    }

    public var thumbnailImage: UIImage? {
        let key = id as NSUUID
        if let cached = Self.thumbnailCache.object(forKey: key) { return cached }

        let data: Data?
        if let mem = thumbnail {
            data = mem
        } else {
            let url = Self.mediaDirectory.appendingPathComponent("\(id)_thumb.jpg")
            data = try? Data(contentsOf: url)
        }

        guard let data, let image = UIImage(data: data) else { return nil }
        Self.thumbnailCache.setObject(image, forKey: key, cost: data.count)
        return image
    }

    /// Returns in-memory imageData, or loads from file if stored externally.
    public var resolvedImageData: Data? {
        if let data = imageData { return data }
        let url = Self.mediaDirectory.appendingPathComponent("\(id)_image.dat")
        return try? Data(contentsOf: url)
    }

    /// Whether a thumbnail exists (in-memory or on disk).
    public var hasThumbnail: Bool {
        if thumbnail != nil { return true }
        let url = Self.mediaDirectory.appendingPathComponent("\(id)_thumb.jpg")
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Whether this clip should play as a Live Photo video, given the tape-level default.
    public func shouldPlayAsLiveVideo(tapeDefault: Bool) -> Bool {
        guard isLivePhoto else { return false }
        return livePhotoAsVideo ?? tapeDefault
    }

    /// Whether this Live Photo clip's audio should be muted, given the tape-level default.
    public func shouldMuteLiveAudio(tapeDefault: Bool) -> Bool {
        guard isLivePhoto else { return false }
        return livePhotoMuted ?? tapeDefault
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
