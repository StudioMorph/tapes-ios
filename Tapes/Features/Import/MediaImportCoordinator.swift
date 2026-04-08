import Foundation
import PhotosUI
import SwiftUI

@MainActor
public class MediaImportCoordinator: ObservableObject {

    @Published var isImporting = false
    @Published var totalCount = 0
    @Published var resolvedCount = 0
    @Published var failedCount = 0

    private(set) var resolvedClips: [Clip] = []
    private var importTask: Task<Void, Never>?
    private var targetTapeID: UUID?
    private var insertionIndex: Int = 0

    var processedCount: Int { resolvedCount + failedCount }

    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(processedCount) / Double(totalCount)
    }

    var progressLabel: String {
        "Importing \(processedCount)/\(totalCount)"
    }

    func startImport(
        results: [PHPickerResult],
        tapeID: UUID,
        insertionIndex: Int
    ) {
        guard !isImporting else { return }

        self.targetTapeID = tapeID
        self.insertionIndex = insertionIndex
        self.totalCount = results.count
        self.resolvedCount = 0
        self.failedCount = 0
        self.resolvedClips = []
        self.isImporting = true

        importTask = Task { [weak self] in
            guard let self else { return }

            var clips: [(index: Int, clip: Clip)] = []

            for (idx, result) in results.enumerated() {
                guard !Task.isCancelled else { break }

                do {
                    let media = try await resolvePickedMedia(from: result)
                    if let clip = Self.buildClip(from: media) {
                        clips.append((idx, clip))
                        self.resolvedCount += 1
                    } else {
                        self.failedCount += 1
                    }
                } catch {
                    TapesLog.mediaPicker.error("Import failed for item \(idx): \(error.localizedDescription, privacy: .public)")
                    self.failedCount += 1
                }
            }

            guard !Task.isCancelled else {
                self.reset()
                return
            }

            self.resolvedClips = clips.sorted { $0.index < $1.index }.map(\.clip)
            self.isImporting = false
        }
    }

    func cancelImport() {
        importTask?.cancel()
        importTask = nil
        reset()
    }

    func reset() {
        isImporting = false
        totalCount = 0
        resolvedCount = 0
        failedCount = 0
        resolvedClips = []
        targetTapeID = nil
        insertionIndex = 0
        importTask = nil
    }

    func consumeResults(for requestingTapeID: UUID) -> (clips: [Clip], tapeID: UUID, insertionIndex: Int)? {
        guard !resolvedClips.isEmpty,
              let tapeID = targetTapeID,
              tapeID == requestingTapeID else { return nil }
        let result = (clips: resolvedClips, tapeID: tapeID, insertionIndex: insertionIndex)
        reset()
        return result
    }

    private static func buildClip(from media: PickedMedia) -> Clip? {
        switch media {
        case let .video(url, duration, assetIdentifier):
            var clip = Clip(
                assetLocalId: assetIdentifier,
                localURL: url,
                clipType: .video,
                duration: duration,
                thumbnail: nil
            )
            clip.updatedAt = Date()
            return clip
        case let .photo(image, assetIdentifier):
            let thumbnailData = image.jpegData(compressionQuality: 0.9)
            let imageData: Data?
            if assetIdentifier == nil {
                imageData = image.jpegData(compressionQuality: 0.85)
            } else {
                imageData = nil
            }
            guard assetIdentifier != nil || imageData != nil else { return nil }
            var clip = Clip(
                assetLocalId: assetIdentifier,
                imageData: imageData,
                clipType: .image,
                duration: Tokens.Timing.photoDefaultDuration,
                thumbnail: thumbnailData
            )
            clip.updatedAt = Date()
            return clip
        }
    }
}
