import Foundation
import UIKit

enum SharedTapeBuilder {

    static func buildTape(from manifest: TapeManifest, downloadManager: CloudDownloadManager) -> Tape? {
        var clips: [Clip] = []

        for manifestClip in manifest.clips {
            guard let localURL = downloadManager.localURL(for: manifestClip.clipId) else {
                continue
            }

            let clipType: ClipType
            switch manifestClip.type {
            case "video": clipType = .video
            case "live_photo": clipType = .video
            default: clipType = .image
            }

            let thumbURL = CloudDownloadManager.thumbnailCacheURL(
                tapeId: manifest.tapeId,
                clipId: manifestClip.clipId
            )
            let thumbData = try? Data(contentsOf: thumbURL)

            var imageData: Data?
            if clipType == .image {
                imageData = try? Data(contentsOf: localURL)
            }

            let clip = Clip(
                id: UUID(uuidString: manifestClip.clipId) ?? UUID(),
                localURL: clipType == .video ? localURL : nil,
                imageData: imageData,
                clipType: clipType,
                duration: Double(manifestClip.durationMs) / 1000.0,
                thumbnail: thumbData,
                trimStart: Double(manifestClip.trimStartMs ?? 0) / 1000.0,
                trimEnd: Double(manifestClip.trimEndMs ?? 0) / 1000.0,
                volume: manifestClip.audioLevel,
                isPlaceholder: false
            )
            clips.append(clip)
        }

        guard !clips.isEmpty else { return nil }

        let transitionType: TransitionType
        if let t = manifest.tapeSettings.transition?.type {
            transitionType = TransitionType(rawValue: t) ?? .none
        } else {
            transitionType = .none
        }

        let transitionDuration: Double
        if let ms = manifest.tapeSettings.transition?.durationMs {
            transitionDuration = Double(ms) / 1000.0
        } else {
            transitionDuration = 0.5
        }

        var tape = Tape(title: manifest.title, clips: clips)
        tape.updateSettings(
            orientation: .auto,
            scaleMode: .aspectFit,
            transition: transitionType,
            transitionDuration: transitionDuration
        )

        return tape
    }
}
