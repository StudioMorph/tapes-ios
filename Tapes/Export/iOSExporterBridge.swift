import Foundation
import AVFoundation

// MARK: - iOS Exporter Bridge

/// Bridge to the iOS TapeExporter for use within the Tapes module
public class iOSExporterBridge {
    
    public static func export(tape: Tape, completion: @escaping (URL?, String?) -> Void) {
        TapeExporter.export(tape: tape, completion: completion)
    }
}

// MARK: - Transition Type Conversion

extension TransitionType {
    /// Convert to the iOS exporter's TransitionStyle
    var toTransitionStyle: TransitionStyle {
        switch self {
        case .none:
            return .none
        case .crossfade:
            return .crossfade
        case .slideLR:
            return .slideLR
        case .slideRL:
            return .slideRL
        case .randomise:
            return .randomise
        }
    }
}
