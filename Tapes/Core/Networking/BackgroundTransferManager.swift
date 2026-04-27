import Foundation
import os

/// Owns the background `URLSession` for R2 uploads and downloads.
///
/// Transfers handed to the background session are managed by the OS daemon
/// (`nsurlsessiond`) and continue even when the app is suspended, terminated,
/// or the device is locked.
///
/// Singleton justification: iOS requires a single session per identifier for
/// reconnection across launches, and `AppDelegate` must deliver the system
/// completion handler to a stable target. See CLAUDE.md singleton list.
final class BackgroundTransferManager: NSObject, @unchecked Sendable {

    static let shared = BackgroundTransferManager()
    static let sessionIdentifier = "com.studiomorph.tapes.bgTransfers"

    let manifest = TransferManifest()

    /// System completion handler stored by `AppDelegate` when iOS relaunches
    /// the app to deliver background session events.
    var systemCompletionHandler: (() -> Void)?

    // MARK: - Private State

    private let log = Logger(subsystem: "com.studiomorph.tapes", category: "BackgroundTransfer")
    private let lock = NSLock()
    private var uploadContinuations: [Int: CheckedContinuation<Void, Error>] = [:]
    private var downloadContinuations: [Int: CheckedContinuation<URL, Error>] = [:]
    private var downloadedFileURLs: [Int: URL] = [:]
    private var uploadTempFiles: [Int: URL] = [:]
    private var _session: URLSession?

    /// Active batch contexts keyed by batchId.
    private var activeBatches: [String: TransferBatch] = [:]

    // MARK: - Batch Types

    struct TransferContext {
        let clipId: String
        let tapeId: String
        let kind: TransferEntry.TransferKind
        let batchId: String
        let remoteBaseUrl: String
    }

    struct TransferBatch {
        let batchId: String
        let tapeId: String
        var totalTasks: Int
        var completedTasks: Int = 0
        var failedTasks: Int = 0
        var completion: ((String) -> Void)?
    }

    /// Per-task context for batch transfers, keyed by task identifier.
    private var taskContexts: [Int: TransferContext] = [:]

    // MARK: - Session

    var session: URLSession {
        if let s = _session { return s }
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        let cellularAllowed = UserDefaults.standard.object(forKey: "allowCellularUploads") == nil
            || UserDefaults.standard.bool(forKey: "allowCellularUploads")
        config.allowsCellularAccess = cellularAllowed
        config.timeoutIntervalForResource = 600
        config.httpMaximumConnectionsPerHost = 4
        let s = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        _session = s
        return s
    }

    private override init() {
        super.init()
        manifest.removeStale()
        cleanupStaleTempFiles()
    }

    /// Force-creates the session so iOS can deliver any pending events from
    /// transfers that completed while the app was terminated.
    func reconnect() { _ = session }

    /// Invalidates the current session (in-flight tasks finish) and ensures
    /// the next access creates a fresh session with updated configuration
    /// (e.g. after the cellular-uploads toggle changes).
    func refreshSession() {
        _session?.finishTasksAndInvalidate()
        _session = nil
    }

    // MARK: - Upload

    /// Uploads a local file to a remote URL via the background session.
    /// Returns when the upload completes successfully; throws on failure.
    func uploadFile(from fileURL: URL, to remoteURL: URL, contentType: String) async throws {
        var request = URLRequest(url: remoteURL)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        let task = session.uploadTask(with: request, fromFile: fileURL)
        let taskId = task.taskIdentifier

        lock.lock()
        uploadTempFiles[taskId] = fileURL
        lock.unlock()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            uploadContinuations[taskId] = continuation
            lock.unlock()
            task.resume()
        }
    }

    // MARK: - Download

    /// Downloads a remote file via the background session.
    /// Returns the local URL of the downloaded file.
    func downloadFile(from remoteURL: URL) async throws -> URL {
        let task = session.downloadTask(with: remoteURL)
        let taskId = task.taskIdentifier

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            lock.lock()
            downloadContinuations[taskId] = continuation
            lock.unlock()
            task.resume()
        }
    }

    // MARK: - Batch Upload

    struct BatchUploadTask {
        let fileURL: URL
        let remoteURL: URL
        let contentType: String
        let clipId: String
        let kind: TransferEntry.TransferKind
    }

    /// Submits all upload tasks at once to the background session.
    /// Each task's completion is tracked in the manifest. When all tasks
    /// in the batch finish, `completion` fires with the batchId.
    func submitBatchUpload(
        batchId: String,
        tapeId: String,
        tasks: [BatchUploadTask],
        completion: @escaping (String) -> Void
    ) {
        lock.lock()
        activeBatches[batchId] = TransferBatch(
            batchId: batchId,
            tapeId: tapeId,
            totalTasks: tasks.count,
            completion: completion
        )
        lock.unlock()

        for batchTask in tasks {
            var request = URLRequest(url: batchTask.remoteURL)
            request.httpMethod = "PUT"
            request.setValue(batchTask.contentType, forHTTPHeaderField: "Content-Type")

            let task = session.uploadTask(with: request, fromFile: batchTask.fileURL)
            let taskId = task.taskIdentifier

            let baseUrl = batchTask.remoteURL.absoluteString.components(separatedBy: "?").first
                ?? batchTask.remoteURL.absoluteString

            let context = TransferContext(
                clipId: batchTask.clipId,
                tapeId: tapeId,
                kind: batchTask.kind,
                batchId: batchId,
                remoteBaseUrl: baseUrl
            )

            let entry = TransferEntry(
                taskIdentifier: taskId,
                clipId: batchTask.clipId,
                tapeId: tapeId,
                kind: batchTask.kind,
                tempFilePath: batchTask.fileURL.path,
                batchId: batchId
            )

            lock.lock()
            taskContexts[taskId] = context
            uploadTempFiles[taskId] = batchTask.fileURL
            lock.unlock()

            manifest.add(entry)
            task.resume()
        }

        log.info("Batch \(batchId): submitted \(tasks.count) upload tasks")
    }

    // MARK: - Batch Download

    struct BatchDownloadTask {
        let remoteURL: URL
        let clipId: String
        let kind: TransferEntry.TransferKind
    }

    /// Submits all download tasks at once to the background session.
    func submitBatchDownload(
        batchId: String,
        tapeId: String,
        tasks: [BatchDownloadTask],
        completion: @escaping (String) -> Void
    ) {
        lock.lock()
        activeBatches[batchId] = TransferBatch(
            batchId: batchId,
            tapeId: tapeId,
            totalTasks: tasks.count,
            completion: completion
        )
        lock.unlock()

        for batchTask in tasks {
            let task = session.downloadTask(with: batchTask.remoteURL)
            let taskId = task.taskIdentifier

            let context = TransferContext(
                clipId: batchTask.clipId,
                tapeId: tapeId,
                kind: batchTask.kind,
                batchId: batchId,
                remoteBaseUrl: batchTask.remoteURL.absoluteString.components(separatedBy: "?").first
                    ?? batchTask.remoteURL.absoluteString
            )

            let entry = TransferEntry(
                taskIdentifier: taskId,
                clipId: batchTask.clipId,
                tapeId: tapeId,
                kind: batchTask.kind,
                batchId: batchId
            )

            lock.lock()
            taskContexts[taskId] = context
            lock.unlock()

            manifest.add(entry)
            task.resume()
        }

        log.info("Batch \(batchId): submitted \(tasks.count) download tasks")
    }

    // MARK: - Batch Progress

    func batchProgress(batchId: String) -> (completed: Int, failed: Int, total: Int) {
        lock.lock()
        let batch = activeBatches[batchId]
        lock.unlock()
        guard let batch else { return (0, 0, 0) }
        return (batch.completedTasks, batch.failedTasks, batch.totalTasks)
    }

    // MARK: - Cancellation

    func cancelAllTasks() {
        lock.lock()
        activeBatches.removeAll()
        taskContexts.removeAll()
        lock.unlock()

        session.getAllTasks { tasks in
            for task in tasks { task.cancel() }
        }
    }

    // MARK: - Temp File Management

    static var uploadTempDir: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BackgroundUploads", isDirectory: true)
    }

    private static var downloadTempDir: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("bg_downloads", isDirectory: true)
    }

    private func cleanupStaleTempFiles() {
        let fm = FileManager.default
        for dir in [Self.uploadTempDir, Self.downloadTempDir] {
            guard fm.fileExists(atPath: dir.path),
                  let contents = try? fm.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: [.creationDateKey]
                  )
            else { continue }
            let cutoff = Date().addingTimeInterval(-3600)
            for url in contents {
                if let values = try? url.resourceValues(forKeys: [.creationDateKey]),
                   let created = values.creationDate, created < cutoff {
                    try? fm.removeItem(at: url)
                }
            }
        }
    }
}

// MARK: - URLSessionDownloadDelegate

extension BackgroundTransferManager: URLSessionDownloadDelegate {

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let dir = Self.downloadTempDir
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: location, to: dest)
            lock.lock()
            downloadedFileURLs[downloadTask.taskIdentifier] = dest
            lock.unlock()
        } catch {
            log.error("Failed to move downloaded file: \(error.localizedDescription)")
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        // Per-byte progress tracking reserved for future use.
    }
}

// MARK: - URLSessionTaskDelegate

extension BackgroundTransferManager {

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let taskId = task.taskIdentifier

        lock.lock()
        let uploadCont = uploadContinuations.removeValue(forKey: taskId)
        let downloadCont = downloadContinuations.removeValue(forKey: taskId)
        let downloadedURL = downloadedFileURLs.removeValue(forKey: taskId)
        let tempFile = uploadTempFiles.removeValue(forKey: taskId)
        let context = taskContexts.removeValue(forKey: taskId)
        lock.unlock()

        let isBatchTask = context != nil

        if let tempFile {
            try? FileManager.default.removeItem(at: tempFile)
        }

        // Network-level error (timeout, connection lost, cancelled)
        if let error {
            log.error("Transfer \(taskId) failed: \(error.localizedDescription)")

            if isBatchTask {
                manifest.markFailed(taskIdentifier: taskId)
                if let ctx = context { advanceBatch(ctx.batchId, success: false) }
            } else {
                manifest.remove(taskIdentifier: taskId)
            }

            uploadCont?.resume(throwing: error)
            downloadCont?.resume(throwing: error)
            return
        }

        // HTTP-level error (403 expired URL, 5xx server error, etc.)
        if let http = task.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            if let url = downloadedURL {
                try? FileManager.default.removeItem(at: url)
            }
            let transferError = TransferError.httpFailure(statusCode: http.statusCode)
            log.error("Transfer \(taskId) HTTP \(http.statusCode)")

            if isBatchTask {
                manifest.markFailed(taskIdentifier: taskId)
                if let ctx = context { advanceBatch(ctx.batchId, success: false) }
            } else {
                manifest.remove(taskIdentifier: taskId)
            }

            uploadCont?.resume(throwing: transferError)
            downloadCont?.resume(throwing: transferError)
            return
        }

        // --- Success ---

        if isBatchTask, let ctx = context {
            manifest.markCompleted(taskIdentifier: taskId, cloudUrl: ctx.remoteBaseUrl)
            advanceBatch(ctx.batchId, success: true)
        } else {
            manifest.remove(taskIdentifier: taskId)
        }

        if let uploadCont {
            log.info("Upload \(taskId) completed")
            uploadCont.resume()
        }

        if let downloadCont {
            if let url = downloadedURL {
                log.info("Download \(taskId) completed")
                downloadCont.resume(returning: url)
            } else {
                log.error("Download \(taskId) completed but moved file not found")
                downloadCont.resume(throwing: TransferError.fileNotFound)
            }
        }

        if uploadCont == nil && downloadCont == nil && !isBatchTask {
            log.info("Transfer \(taskId) completed after relaunch (no continuation)")
        }
    }

    private func advanceBatch(_ batchId: String, success: Bool) {
        lock.lock()
        guard var batch = activeBatches[batchId] else {
            lock.unlock()
            return
        }
        if success {
            batch.completedTasks += 1
        } else {
            batch.failedTasks += 1
        }
        let finished = (batch.completedTasks + batch.failedTasks) >= batch.totalTasks
        let completion = finished ? batch.completion : nil
        activeBatches[batchId] = batch
        if finished { activeBatches.removeValue(forKey: batchId) }
        lock.unlock()

        let processed = batch.completedTasks + batch.failedTasks
        log.info("Batch \(batchId): \(processed)/\(batch.totalTasks) (success=\(success))")

        if let completion {
            completion(batchId)
        }
    }
}

// MARK: - URLSessionDelegate

extension BackgroundTransferManager {

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        log.info("All background session events delivered")
        DispatchQueue.main.async { [weak self] in
            self?.systemCompletionHandler?()
            self?.systemCompletionHandler = nil
        }
    }
}

// MARK: - TransferError

enum TransferError: LocalizedError {
    case httpFailure(statusCode: Int)
    case fileNotFound
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .httpFailure(let code): "Transfer failed (HTTP \(code))."
        case .fileNotFound:          "Downloaded file could not be found."
        case .invalidURL:            "Invalid transfer URL."
        }
    }

    var isExpiredURL: Bool {
        if case .httpFailure(let code) = self { return code == 403 }
        return false
    }
}
