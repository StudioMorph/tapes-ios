import Foundation
import os

@MainActor
enum TapeFileGenerator {

    private static let log = Logger(subsystem: "com.studiomorph.tapes", category: "TapeFile")

    static func generateTapeFile(
        tape: Tape,
        shareId: String,
        tapeId: String,
        api: TapesAPIClient
    ) async throws -> URL {
        let manifest = try await api.getManifest(tapeId: tapeId)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)

        let fileName = sanitiseFilename(tape.title) + ".tape"
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tape_exports", isDirectory: true)

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let fileURL = tempDir.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }

        try data.write(to: fileURL)

        log.info("Generated .tape file at \(fileURL.lastPathComponent) (\(data.count) bytes)")
        return fileURL
    }

    static func generateLocalTapeFile(tape: Tape) throws -> URL {
        let info: [String: Any] = [
            "tapes_version": "1.0",
            "tape_id": tape.id.uuidString.lowercased(),
            "title": tape.title,
            "mode": "view_only",
            "created_at": ISO8601DateFormatter().string(from: tape.createdAt),
            "updated_at": ISO8601DateFormatter().string(from: tape.updatedAt),
            "clips": tape.clips.enumerated().map { index, clip in
                [
                    "clip_id": clip.id.uuidString.lowercased(),
                    "type": clip.clipType == .video ? "video" : "image",
                    "duration_ms": Int(clip.duration * 1000),
                    "order_index": index,
                    "audio_level": clip.volume ?? 1.0,
                ] as [String: Any]
            },
            "tape_settings": [
                "transition": [
                    "type": tape.transition.rawValue,
                    "duration_ms": Int(tape.transitionDuration * 1000),
                ] as [String: Any],
                "merge_settings": [
                    "orientation": tape.exportOrientation.rawValue,
                    "background_blur": tape.blurExportBackground,
                ] as [String: Any],
            ] as [String: Any],
            "meta": [
                "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                "platform": "ios",
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])

        let fileName = sanitiseFilename(tape.title) + ".tape"
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tape_exports", isDirectory: true)

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let fileURL = tempDir.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }

        try data.write(to: fileURL)
        return fileURL
    }

    private static func sanitiseFilename(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: " -_"))
        let sanitised = name.unicodeScalars.filter { allowed.contains($0) }
        let result = String(String.UnicodeScalarView(sanitised))
            .trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? "Tape" : result
    }
}
