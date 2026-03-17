import Foundation
import AVFoundation

public enum iOSExporterBridge {

    public static func export(tape: Tape) async throws -> (url: URL, assetIdentifier: String?) {
        try await TapeExporter.export(tape: tape)
    }
}
