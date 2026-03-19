import Foundation
import AVFoundation

public enum iOSExporterBridge {

    public static func export(tape: Tape) async throws -> (url: URL, assetIdentifier: String?) {
        let session = TapeExportSession()
        return try await session.run(tape: tape)
    }
}
