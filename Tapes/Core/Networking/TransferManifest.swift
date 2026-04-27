import Foundation
import os

/// Tracks a single in-flight background transfer so cleanup can resume after
/// the app is relaunched.
struct TransferEntry: Codable, Identifiable {
    let id: String
    let taskIdentifier: Int
    let clipId: String
    let tapeId: String
    let kind: TransferKind
    let tempFilePath: String?
    let createdAt: Date
    var batchId: String?
    var status: TransferStatus
    var cloudUrl: String?

    enum TransferKind: String, Codable {
        case uploadMedia
        case uploadThumbnail
        case uploadMovie
        case downloadMedia
        case downloadMovie
        case downloadThumbnail
    }

    enum TransferStatus: String, Codable {
        case pending
        case completed
        case failed
    }

    init(id: String = UUID().uuidString,
         taskIdentifier: Int,
         clipId: String,
         tapeId: String,
         kind: TransferKind,
         tempFilePath: String? = nil,
         createdAt: Date = Date(),
         batchId: String? = nil,
         status: TransferStatus = .pending,
         cloudUrl: String? = nil) {
        self.id = id
        self.taskIdentifier = taskIdentifier
        self.clipId = clipId
        self.tapeId = tapeId
        self.kind = kind
        self.tempFilePath = tempFilePath
        self.createdAt = createdAt
        self.batchId = batchId
        self.status = status
        self.cloudUrl = cloudUrl
    }
}

/// Lightweight persistent manifest of in-flight background transfers.
///
/// Written atomically after every add/remove so state survives termination.
/// Stale entries (presigned URL expiry window) are cleaned up on launch.
final class TransferManifest: @unchecked Sendable {

    private let log = Logger(subsystem: "com.studiomorph.tapes", category: "TransferManifest")
    private let lock = NSLock()
    private var entries: [TransferEntry] = []

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("transfer_manifest.json")
    }

    init() { load() }

    // MARK: - Mutation

    func add(_ entry: TransferEntry) {
        lock.lock()
        entries.append(entry)
        lock.unlock()
        persist()
    }

    func remove(taskIdentifier: Int) {
        lock.lock()
        entries.removeAll { $0.taskIdentifier == taskIdentifier }
        lock.unlock()
        persist()
    }

    func markCompleted(taskIdentifier: Int, cloudUrl: String? = nil) {
        lock.lock()
        if let idx = entries.firstIndex(where: { $0.taskIdentifier == taskIdentifier }) {
            entries[idx].status = .completed
            if let url = cloudUrl {
                entries[idx].cloudUrl = url
            }
        }
        lock.unlock()
        persist()
    }

    func markFailed(taskIdentifier: Int) {
        lock.lock()
        if let idx = entries.firstIndex(where: { $0.taskIdentifier == taskIdentifier }) {
            entries[idx].status = .failed
        }
        lock.unlock()
        persist()
    }

    func removeAll(batchId: String) {
        lock.lock()
        let toRemove = entries.filter { $0.batchId == batchId }
        entries.removeAll { $0.batchId == batchId }
        lock.unlock()
        for entry in toRemove {
            if let path = entry.tempFilePath {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
            }
        }
        persist()
    }

    // MARK: - Query

    func entry(for taskIdentifier: Int) -> TransferEntry? {
        lock.lock()
        defer { lock.unlock() }
        return entries.first { $0.taskIdentifier == taskIdentifier }
    }

    var all: [TransferEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    func entries(forBatch batchId: String) -> [TransferEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries.filter { $0.batchId == batchId }
    }

    func completedEntries(forBatch batchId: String) -> [TransferEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries.filter { $0.batchId == batchId && $0.status == .completed }
    }

    func failedEntries(forBatch batchId: String) -> [TransferEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries.filter { $0.batchId == batchId && $0.status == .failed }
    }

    func pendingEntries(forBatch batchId: String) -> [TransferEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries.filter { $0.batchId == batchId && $0.status == .pending }
    }

    /// Returns batch IDs that have at least one entry.
    var activeBatchIds: [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(Set(entries.compactMap(\.batchId)))
    }

    // MARK: - Cleanup

    /// Removes entries older than `interval` and deletes their temp files.
    func removeStale(olderThan interval: TimeInterval = 3600) {
        let cutoff = Date().addingTimeInterval(-interval)
        var stale: [TransferEntry] = []
        lock.lock()
        stale = entries.filter { $0.createdAt < cutoff }
        entries.removeAll { $0.createdAt < cutoff }
        lock.unlock()

        for entry in stale {
            if let path = entry.tempFilePath {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
            }
        }
        if !stale.isEmpty {
            log.info("Cleaned up \(stale.count) stale transfer manifest entries")
            persist()
        }
    }

    // MARK: - Persistence

    private func load() {
        let url = Self.fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([TransferEntry].self, from: data)
            lock.lock()
            entries = decoded
            lock.unlock()
        } catch {
            log.error("Failed to load transfer manifest: \(error.localizedDescription)")
        }
    }

    private func persist() {
        lock.lock()
        let snapshot = entries
        lock.unlock()
        do {
            let url = Self.fileURL
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            log.error("Failed to save transfer manifest: \(error.localizedDescription)")
        }
    }
}
