import Foundation

/// A lightweight placeholder representing a tape invitation that hasn't been loaded yet.
/// Persisted locally so invites survive app restarts regardless of push delivery.
public struct PendingInvite: Identifiable, Codable, Equatable {
    public let tapeId: String
    public let title: String
    public let ownerName: String
    public let shareId: String
    public let mode: String
    public let receivedAt: Date

    public var id: String { tapeId }

    public var isCollaborative: Bool {
        mode == "collaborative" || mode == "collab_protected" || mode == "collab_open"
    }
}
