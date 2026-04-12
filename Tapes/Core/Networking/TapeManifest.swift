import Foundation

struct TapeManifest: Codable {
    let tapesVersion: String
    let tapeId: String
    let title: String
    let mode: String
    let expiresAt: String?
    let createdAt: String
    let updatedAt: String
    let ownerId: String
    let ownerName: String?
    let collaborators: [ManifestCollaborator]
    let clips: [ManifestClip]
    let tapeSettings: ManifestTapeSettings
    let permissions: ManifestPermissions
    let meta: ManifestMeta

    enum CodingKeys: String, CodingKey {
        case tapesVersion = "tapes_version"
        case tapeId = "tape_id"
        case title, mode
        case expiresAt = "expires_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case ownerId = "owner_id"
        case ownerName = "owner_name"
        case collaborators, clips
        case tapeSettings = "tape_settings"
        case permissions, meta
    }
}

struct ManifestCollaborator: Codable {
    let userId: String?
    let email: String?
    let name: String?
    let role: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case email, name, role, status
    }
}

struct ManifestClip: Codable, Identifiable {
    let clipId: String
    let type: String
    let cloudUrl: String?
    let thumbnailUrl: String?
    let contributorId: String?
    let recordedAt: String?
    let durationMs: Int
    let trimStartMs: Int?
    let trimEndMs: Int?
    let audioLevel: Double?
    let orderIndex: Int
    let kenBurns: ManifestKenBurns?
    let livePhotoAsVideo: Bool?
    let livePhotoSound: Bool?

    var id: String { clipId }

    enum CodingKeys: String, CodingKey {
        case clipId = "clip_id"
        case type
        case cloudUrl = "cloud_url"
        case thumbnailUrl = "thumbnail_url"
        case contributorId = "contributor_id"
        case recordedAt = "recorded_at"
        case durationMs = "duration_ms"
        case trimStartMs = "trim_start_ms"
        case trimEndMs = "trim_end_ms"
        case audioLevel = "audio_level"
        case orderIndex = "order_index"
        case kenBurns = "ken_burns"
        case livePhotoAsVideo = "live_photo_as_video"
        case livePhotoSound = "live_photo_sound"
    }
}

struct ManifestKenBurns: Codable {
    let startRect: ManifestRect
    let endRect: ManifestRect

    enum CodingKeys: String, CodingKey {
        case startRect = "start_rect"
        case endRect = "end_rect"
    }
}

struct ManifestRect: Codable {
    let x: Double
    let y: Double
    let w: Double
    let h: Double
}

struct ManifestTapeSettings: Codable {
    let defaultAudioLevel: Double?
    let transition: ManifestTransition?
    let backgroundMusic: ManifestBackgroundMusic?
    let mergeSettings: ManifestMergeSettings?

    enum CodingKeys: String, CodingKey {
        case defaultAudioLevel = "default_audio_level"
        case transition
        case backgroundMusic = "background_music"
        case mergeSettings = "merge_settings"
    }
}

struct ManifestTransition: Codable {
    let type: String
    let durationMs: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case durationMs = "duration_ms"
    }
}

struct ManifestBackgroundMusic: Codable {
    let type: String?
    let mood: String?
    let url: String?
    let level: Double?
}

struct ManifestMergeSettings: Codable {
    let orientation: String?
    let backgroundBlur: Bool?

    enum CodingKeys: String, CodingKey {
        case orientation
        case backgroundBlur = "background_blur"
    }
}

struct ManifestPermissions: Codable {
    let canContribute: Bool
    let canExport: Bool
    let canSaveToDevice: Bool
    let canReshare: Bool
    let canInvite: Bool

    enum CodingKeys: String, CodingKey {
        case canContribute = "can_contribute"
        case canExport = "can_export"
        case canSaveToDevice = "can_save_to_device"
        case canReshare = "can_reshare"
        case canInvite = "can_invite"
    }
}

struct ManifestMeta: Codable {
    let appVersion: String?
    let platform: String?

    enum CodingKeys: String, CodingKey {
        case appVersion = "app_version"
        case platform
    }
}
