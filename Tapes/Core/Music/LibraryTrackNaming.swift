import Foundation

/// Mubert's library tracks have no human-readable name. We derive one
/// deterministically from the track ID so the same track always shows the
/// same name across sessions and devices. The noun pool is biased by the
/// track's intensity so the name loosely matches what you'll hear.
extension TapesAPIClient.LibraryTrack {
    var displayTitle: String {
        let seed = LibraryTrackNamer.stableHash(id)
        return LibraryTrackNamer.name(seed: seed, intensity: intensity)
    }
}

enum LibraryTrackNamer {

    static func name(seed: UInt64, intensity: String?) -> String {
        let adjective = adjectives[Int(seed % UInt64(adjectives.count))]
        let nouns = nounPool(for: intensity)
        let nounIndex = Int((seed >> 16) % UInt64(nouns.count))
        return "\(adjective) \(nouns[nounIndex])"
    }

    /// FNV-1a 64-bit. Deterministic across runs (unlike Swift's `String.hashValue`).
    static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 14_695_981_039_346_656_037
        for byte in s.utf8 {
            h ^= UInt64(byte)
            h = h &* 1_099_511_628_211
        }
        return h
    }

    private static let adjectives: [String] = [
        "Velvet", "Amber", "Quiet", "Slow", "Soft", "Pale", "Golden", "Hazy",
        "Deep", "Bright", "Luminous", "Wandering", "Hidden", "Open", "Faded",
        "Distant", "Echoing", "Liquid", "Crystal", "Silent", "Weathered",
        "Endless", "Restless", "Tender", "Rusted", "Salt", "Smoke", "Buried",
        "Northern", "Lonely", "Floating", "Burning", "Lantern", "Coastal",
        "Wild", "Sunlit", "Drifting", "Wintered", "Glass", "Hollow", "Mineral",
        "Paper", "Indigo", "Iron", "Cedar", "Marble", "Crimson"
    ]

    private static let calmNouns: [String] = [
        "Tide", "Bloom", "Drift", "Dawn", "Lantern", "Hour", "Cradle",
        "Hollow", "Breath", "Quiet", "Path", "Shore", "Horizon", "Window",
        "Garden", "Lullaby", "Rain", "Mist", "Veil", "Field", "Glade",
        "Stream", "Echo", "Memory", "Hush", "Letter", "Threshold", "Halo",
        "Lake", "Embers"
    ]

    private static let energeticNouns: [String] = [
        "Pulse", "Spark", "Surge", "Engine", "Riot", "Storm", "Bolt",
        "Furnace", "Anthem", "March", "Wire", "Drum", "Fire", "Beat",
        "Rush", "Voltage", "Flare", "Dynamo", "Hammer", "Signal", "Cascade",
        "Wave", "Pulse", "Forge", "Spire", "Thunder", "Spark", "Charge",
        "Pulse", "Rocket"
    ]

    private static func nounPool(for intensity: String?) -> [String] {
        switch intensity?.lowercased() {
        case "high":
            return energeticNouns
        case "low":
            return calmNouns
        default:
            return calmNouns + energeticNouns
        }
    }
}
