import Foundation
import os

/// Persists pending tape invitations as a lightweight JSON file.
/// Injected as an `@EnvironmentObject` so Shared/Collab tabs react to changes.
@MainActor
public class PendingInviteStore: ObservableObject {

    @Published public private(set) var invites: [PendingInvite] = []

    private let log = Logger(subsystem: "com.studiomorph.tapes", category: "PendingInvites")
    private let fileURL: URL

    public init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = docs.appendingPathComponent("pending_invites.json")
        load()
    }

    func add(_ invite: PendingInvite) {
        guard !invites.contains(where: { $0.tapeId == invite.tapeId }) else {
            log.info("Invite already exists for tape \(invite.tapeId)")
            return
        }
        invites.append(invite)
        save()
        log.info("Added invite: \(invite.title) from \(invite.ownerName)")
    }

    func remove(tapeId: String) {
        invites.removeAll { $0.tapeId == tapeId }
        save()
        log.info("Removed invite for tape \(tapeId)")
    }

    func contains(tapeId: String) -> Bool {
        invites.contains { $0.tapeId == tapeId }
    }

    /// Invites for the Shared tab (view-only mode).
    var viewOnlyInvites: [PendingInvite] {
        invites.filter { !$0.isCollaborative }
    }

    /// Invites for the Collab tab (collaborative mode).
    var collaborativeInvites: [PendingInvite] {
        invites.filter { $0.isCollaborative }
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(invites)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            log.error("Failed to save invites: \(error.localizedDescription)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            invites = try JSONDecoder().decode([PendingInvite].self, from: data)
            log.info("Loaded \(self.invites.count) pending invite(s)")
        } catch {
            log.error("Failed to load invites: \(error.localizedDescription)")
        }
    }
}
