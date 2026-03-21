import Foundation

// MARK: - Tape Orientation

public enum TapeOrientation: String, CaseIterable, Codable {
    case portrait = "portrait"
    case landscape = "landscape"
    
    public var aspectRatio: String {
        switch self {
        case .portrait:
            return "9:16"
        case .landscape:
            return "16:9"
        }
    }
    
    public var displayName: String {
        switch self {
        case .portrait:
            return "Portrait (9:16)"
        case .landscape:
            return "Landscape (16:9)"
        }
    }
}

// MARK: - Scale Mode

public enum ScaleMode: String, CaseIterable, Codable {
    case fit = "fit"
    case fill = "fill"
    
    public var displayName: String {
        switch self {
        case .fit:
            return "Fit"
        case .fill:
            return "Fill"
        }
    }
    
    public var description: String {
        switch self {
        case .fit:
            return "Shows entire clip, may have black bars"
        case .fill:
            return "Fills entire frame, may crop content"
        }
    }
}

// MARK: - Transition Type

public enum TransitionType: String, CaseIterable, Codable {
    case none = "none"
    case crossfade = "crossfade"
    case slideLR = "slideLR"
    case slideRL = "slideRL"
    case randomise = "randomise"
    
    public var displayName: String {
        switch self {
        case .none:
            return "None"
        case .crossfade:
            return "Crossfade"
        case .slideLR:
            return "Slide L→R"
        case .slideRL:
            return "Slide R→L"
        case .randomise:
            return "Randomise"
        }
    }
}

// MARK: - Export Orientation

public enum ExportOrientation: String, CaseIterable, Codable, Identifiable {
    case auto = "auto"
    case portrait = "portrait"
    case landscape = "landscape"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .portrait: return "Portrait"
        case .landscape: return "Landscape"
        }
    }

    public var description: String {
        switch self {
        case .auto: return "Based on majority of clips"
        case .portrait: return "Always export in 9:16"
        case .landscape: return "Always export in 16:9"
        }
    }

    public var icon: String {
        switch self {
        case .auto: return "arrow.triangle.2.circlepath"
        case .portrait: return "rectangle.portrait"
        case .landscape: return "rectangle"
        }
    }
}

// MARK: - Seam Transition Override

public struct SeamTransition: Codable, Equatable {
    public var style: TransitionType
    public var duration: Double

    public init(style: TransitionType = .crossfade, duration: Double = 0.5) {
        self.style = style
        self.duration = duration
    }

    /// Stable key for the boundary between two adjacent clips.
    public static func key(leftClipID: UUID, rightClipID: UUID) -> String {
        "\(leftClipID.uuidString)_\(rightClipID.uuidString)"
    }
}

// MARK: - Tape Model

public struct Tape: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var orientation: TapeOrientation
    public var scaleMode: ScaleMode
    public var transition: TransitionType
    public var transitionDuration: Double
    public var seamTransitions: [String: SeamTransition]
    public var clips: [Clip]
    public var createdAt: Date
    public var updatedAt: Date
    public var hasReceivedFirstContent: Bool
    public var albumLocalIdentifier: String?
    public var backgroundMusicMood: String?
    public var backgroundMusicVolume: Double?
    public var exportOrientation: ExportOrientation

    public init(
        id: UUID = UUID(),
        title: String = "New Tape",
        orientation: TapeOrientation = .portrait,
        scaleMode: ScaleMode = .fit,
        transition: TransitionType = .none,
        transitionDuration: Double = 0.5,
        seamTransitions: [String: SeamTransition] = [:],
        clips: [Clip] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        hasReceivedFirstContent: Bool = false,
        albumLocalIdentifier: String? = nil,
        backgroundMusicMood: String? = nil,
        backgroundMusicVolume: Double? = nil,
        exportOrientation: ExportOrientation = .auto
    ) {
        self.id = id
        self.title = title
        self.orientation = orientation
        self.scaleMode = scaleMode
        self.transition = transition
        self.transitionDuration = transitionDuration
        self.seamTransitions = seamTransitions
        self.clips = clips
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.hasReceivedFirstContent = hasReceivedFirstContent
        self.albumLocalIdentifier = albumLocalIdentifier
        self.backgroundMusicMood = backgroundMusicMood
        self.backgroundMusicVolume = backgroundMusicVolume
        self.exportOrientation = exportOrientation
    }
    
    // MARK: - Coding Keys
    
    private enum CodingKeys: String, CodingKey {
        case id, title, orientation, scaleMode, transition, transitionDuration
        case seamTransitions
        case clips, createdAt, updatedAt, hasReceivedFirstContent, albumLocalIdentifier
        case backgroundMusicMood, backgroundMusicVolume
        case exportOrientation
    }
    
    // MARK: - Custom Decoder for Backward Compatibility
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        orientation = try container.decode(TapeOrientation.self, forKey: .orientation)
        scaleMode = try container.decode(ScaleMode.self, forKey: .scaleMode)
        transition = try container.decode(TransitionType.self, forKey: .transition)
        transitionDuration = try container.decode(Double.self, forKey: .transitionDuration)
        seamTransitions = try container.decodeIfPresent([String: SeamTransition].self, forKey: .seamTransitions) ?? [:]
        clips = try container.decode([Clip].self, forKey: .clips)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        
        hasReceivedFirstContent = try container.decodeIfPresent(Bool.self, forKey: .hasReceivedFirstContent) ?? false
        albumLocalIdentifier = try container.decodeIfPresent(String.self, forKey: .albumLocalIdentifier)
        backgroundMusicMood = try container.decodeIfPresent(String.self, forKey: .backgroundMusicMood)
        backgroundMusicVolume = try container.decodeIfPresent(Double.self, forKey: .backgroundMusicVolume)
        exportOrientation = try container.decodeIfPresent(ExportOrientation.self, forKey: .exportOrientation) ?? .auto
    }
    
    // MARK: - Computed Properties
    
    public var duration: TimeInterval {
        // Calculate total duration including transitions
        let clipDuration = clips.reduce(0) { $0 + $1.duration }
        let transitionCount = max(0, clips.count - 1)
        let transitionsEnabled = transition != .none
        let transitionTime = transitionsEnabled ? Double(transitionCount) * transitionDuration : 0
        return clipDuration + transitionTime
    }
    
    public var isEmpty: Bool {
        return clips.isEmpty
    }

    var musicMood: MubertAPIClient.Mood {
        guard let raw = backgroundMusicMood,
              let mood = MubertAPIClient.Mood(rawValue: raw) else { return .none }
        return mood
    }

    var musicVolume: Float {
        Float(backgroundMusicVolume ?? 0.3)
    }
    
    public var clipCount: Int {
        return clips.count
    }

    public var hasAssociatedAlbum: Bool {
        return !(albumLocalIdentifier?.isEmpty ?? true)
    }
    
    // MARK: - Mutating Methods
    
    public mutating func addClip(_ clip: Clip, at index: Int? = nil) {
        let insertIndex = index ?? clips.count
        let boundedIndex = max(0, min(insertIndex, clips.count))
        clips.insert(clip, at: boundedIndex)
        updatedAt = Date()
    }
    
    public mutating func removeClip(at index: Int) {
        guard index >= 0 && index < clips.count else { return }
        clips.remove(at: index)
        updatedAt = Date()
    }
    
    public mutating func removeClip(_ clip: Clip) {
        clips.removeAll { $0.id == clip.id }
        updatedAt = Date()
    }
    
    public mutating func reorderClips(from source: IndexSet, to destination: Int) {
        clips.move(fromOffsets: source, toOffset: destination)
        updatedAt = Date()
    }
    
    public mutating func updateClip(_ clip: Clip) {
        if let index = clips.firstIndex(where: { $0.id == clip.id }) {
            clips[index] = clip
            updatedAt = Date()
        }
    }
    
    public mutating func updateSettings(
        title: String? = nil,
        orientation: TapeOrientation? = nil,
        scaleMode: ScaleMode? = nil,
        transition: TransitionType? = nil,
        transitionDuration: Double? = nil
    ) {
        if let title = title { self.title = title }
        if let orientation = orientation { self.orientation = orientation }
        if let scaleMode = scaleMode { self.scaleMode = scaleMode }
        if let transition = transition { self.transition = transition }
        if let transitionDuration = transitionDuration { 
            self.transitionDuration = transitionDuration 
        }
        updatedAt = Date()
    }
    
    // MARK: - Seam Transition Overrides

    /// Returns the override for the boundary between two adjacent clips, if any.
    public func seamTransition(leftClipID: UUID, rightClipID: UUID) -> SeamTransition? {
        let key = SeamTransition.key(leftClipID: leftClipID, rightClipID: rightClipID)
        return seamTransitions[key]
    }

    /// Sets or removes the override for a specific seam.
    public mutating func setSeamTransition(_ override: SeamTransition?, leftClipID: UUID, rightClipID: UUID) {
        let key = SeamTransition.key(leftClipID: leftClipID, rightClipID: rightClipID)
        seamTransitions[key] = override
        updatedAt = Date()
    }

    public func removingPlaceholders() -> Tape {
        var copy = self
        copy.clips.removeAll { $0.isPlaceholder }
        return copy
    }
    
    // MARK: - Sample Data
    
    public static var sampleTapes: [Tape] {
        [
            Tape(
                title: "New Tape",
                orientation: .portrait,
                scaleMode: .fit,
                transition: .none,
                transitionDuration: 0.5
            ),
            Tape(
                title: "Summer Holidays 2025 - P...",
                orientation: .portrait,
                scaleMode: .fill,
                transition: .crossfade,
                transitionDuration: 0.8,
        clips: [
            Clip(assetLocalId: "sample1", clipType: .video, duration: 5.0, rotateQuarterTurns: 0, overrideScaleMode: nil),
            Clip(assetLocalId: "sample2", clipType: .video, duration: 5.0, rotateQuarterTurns: 0, overrideScaleMode: nil)
        ]
            ),
            Tape(
                title: "Summer Holidays 2025 - L...",
                orientation: .landscape,
                scaleMode: .fit,
                transition: .slideLR,
                transitionDuration: 0.6,
        clips: [
            Clip(assetLocalId: "sample3", clipType: .video, duration: 5.0, rotateQuarterTurns: 0, overrideScaleMode: nil)
        ]
            )
        ]
    }
}

// MARK: - Equatable

extension Tape {
    public static func == (lhs: Tape, rhs: Tape) -> Bool {
        return lhs.id == rhs.id
    }
}
