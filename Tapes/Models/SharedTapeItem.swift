import Foundation

struct SharedTapeItem: Identifiable, Decodable {
    let tapeId: String
    let title: String
    let mode: String
    let ownerName: String
    let clipCount: Int?
    let expiresAt: Date?
    let sharedAt: Date

    var id: String { tapeId }

    enum CodingKeys: String, CodingKey {
        case tapeId = "tape_id"
        case title, mode
        case ownerName = "owner_name"
        case clipCount = "clip_count"
        case expiresAt = "expires_at"
        case sharedAt = "shared_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tapeId = try container.decode(String.self, forKey: .tapeId)
        title = try container.decode(String.self, forKey: .title)
        mode = try container.decode(String.self, forKey: .mode)
        ownerName = try container.decode(String.self, forKey: .ownerName)
        clipCount = try container.decodeIfPresent(Int.self, forKey: .clipCount)
        sharedAt = try container.decode(Date.self, forKey: .sharedAt)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
    }
}
