import Foundation
import os

@MainActor
final class CloudUploadManager: ObservableObject {

    enum UploadState: Equatable {
        case idle
        case uploading(progress: Double)
        case confirming
        case completed
        case failed(String)
    }

    struct UploadTask: Identifiable {
        let id: String
        let tapeId: String
        let clipId: String
        let fileURL: URL
        let thumbnailData: Data?
        let clipType: String
        let durationMs: Int
        var state: UploadState = .idle
        var attempt: Int = 0
    }

    @Published private(set) var activeTasks: [UploadTask] = []
    @Published private(set) var totalProgress: Double = 0

    private let api: TapesAPIClient
    private let log = Logger(subsystem: "com.studiomorph.tapes", category: "Upload")
    private let maxRetries = 3

    init(api: TapesAPIClient) {
        self.api = api
    }

    var hasActiveUploads: Bool {
        activeTasks.contains { if case .uploading = $0.state { return true }; return false }
    }

    // MARK: - Upload

    func upload(tapeId: String, clipId: String, fileURL: URL, thumbnailData: Data?,
                clipType: String, durationMs: Int) {
        let task = UploadTask(
            id: clipId,
            tapeId: tapeId,
            clipId: clipId,
            fileURL: fileURL,
            thumbnailData: thumbnailData,
            clipType: clipType,
            durationMs: durationMs
        )
        activeTasks.append(task)
        Task { await executeUpload(clipId: clipId) }
    }

    // MARK: - Retry

    func retry(clipId: String) {
        guard let idx = activeTasks.firstIndex(where: { $0.clipId == clipId }) else { return }
        activeTasks[idx].state = .idle
        activeTasks[idx].attempt = 0
        Task { await executeUpload(clipId: clipId) }
    }

    // MARK: - Cancel

    func cancel(clipId: String) {
        activeTasks.removeAll { $0.clipId == clipId }
        updateTotalProgress()
    }

    // MARK: - Execution

    private func executeUpload(clipId: String) async {
        guard let idx = activeTasks.firstIndex(where: { $0.clipId == clipId }) else { return }
        var task = activeTasks[idx]

        task.attempt += 1
        task.state = .uploading(progress: 0)
        activeTasks[idx] = task

        do {
            // Step 1: Request presigned upload URL from API
            let createResponse = try await api.createClip(
                tapeId: task.tapeId,
                clipId: task.clipId,
                type: task.clipType,
                durationMs: task.durationMs
            )

            log.info("Got upload URL for clip \(task.clipId), order: \(createResponse.orderIndex)")

            // Step 2: Upload file to R2 via presigned URL
            guard let idx = activeTasks.firstIndex(where: { $0.clipId == clipId }) else { return }
            activeTasks[idx].state = .uploading(progress: 0.1)

            let fileData = try Data(contentsOf: task.fileURL)
            try await uploadToR2(
                url: createResponse.uploadUrl,
                data: fileData,
                contentType: contentType(for: task.clipType),
                clipId: clipId
            )

            // Step 3: Upload thumbnail if available
            if let thumbData = task.thumbnailData {
                try await uploadToR2(
                    url: createResponse.thumbnailUploadUrl,
                    data: thumbData,
                    contentType: "image/jpeg",
                    clipId: clipId,
                    isThumb: true
                )
            }

            // Step 4: Confirm upload with API
            guard let idx = activeTasks.firstIndex(where: { $0.clipId == clipId }) else { return }
            activeTasks[idx].state = .confirming

            let _ = try await api.confirmUpload(
                tapeId: task.tapeId,
                clipId: task.clipId,
                cloudUrl: createResponse.uploadUrl.components(separatedBy: "?").first ?? createResponse.uploadUrl,
                thumbnailUrl: createResponse.thumbnailUploadUrl.components(separatedBy: "?").first ?? createResponse.thumbnailUploadUrl
            )

            guard let idx = activeTasks.firstIndex(where: { $0.clipId == clipId }) else { return }
            activeTasks[idx].state = .completed
            log.info("Upload complete for clip \(task.clipId)")

        } catch {
            log.error("Upload failed for clip \(task.clipId): \(error.localizedDescription)")

            guard let idx = activeTasks.firstIndex(where: { $0.clipId == clipId }) else { return }

            if activeTasks[idx].attempt < maxRetries {
                let delay = pow(2.0, Double(activeTasks[idx].attempt))
                log.info("Retrying clip \(task.clipId) in \(delay)s (attempt \(activeTasks[idx].attempt + 1)/\(self.maxRetries))")

                try? await Task.sleep(for: .seconds(delay))
                await executeUpload(clipId: clipId)
            } else {
                activeTasks[idx].state = .failed(error.localizedDescription)
            }
        }

        updateTotalProgress()
    }

    // MARK: - R2 Upload

    private func uploadToR2(url: String, data: Data, contentType: String,
                            clipId: String, isThumb: Bool = false) async throws {
        guard let uploadURL = URL(string: url) else {
            throw APIError.validation("Invalid upload URL.")
        }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")

        let (_, response) = try await URLSession.shared.upload(for: request, from: data)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIError.server("R2 upload failed with status \(statusCode).")
        }

        if !isThumb {
            guard let idx = activeTasks.firstIndex(where: { $0.clipId == clipId }) else { return }
            activeTasks[idx].state = .uploading(progress: 0.9)
        }
    }

    // MARK: - Helpers

    private func contentType(for clipType: String) -> String {
        switch clipType {
        case "video": return "video/mp4"
        case "live_photo": return "video/quicktime"
        default: return "image/jpeg"
        }
    }

    private func updateTotalProgress() {
        guard !activeTasks.isEmpty else {
            totalProgress = 0
            return
        }

        let sum = activeTasks.reduce(0.0) { acc, task in
            switch task.state {
            case .idle: return acc
            case .uploading(let p): return acc + p
            case .confirming: return acc + 0.95
            case .completed: return acc + 1.0
            case .failed: return acc
            }
        }
        totalProgress = sum / Double(activeTasks.count)
    }
}
